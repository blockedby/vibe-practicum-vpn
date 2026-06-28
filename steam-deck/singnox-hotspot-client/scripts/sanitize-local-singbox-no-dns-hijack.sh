#!/usr/bin/env bash
set -Eeuo pipefail

# Usage:
#   sudo ./scripts/sanitize-local-singbox-no-dns-hijack.sh [--input /path] [--output /path] [--service NAME] [--no-restart] [--keep-route-exclude]
#
# Rewrite a sing-box config to remove:
#   1) DNS pinning to hardcoded upstreams (replaces with local DNS)
#   2) route rules with action: hijack-dns
#   3) tun inbound route_exclude_address blocks (optional, can be kept with --keep-route-exclude)

INPUT="/etc/sing-box/config.json"
OUTPUT=""
RESTART_SERVICE="sing-box.service"
DO_RESTART=1
KEEP_ROUTE_EXCLUDE=0

USAGE='Usage: sanitize-local-singbox-no-dns-hijack.sh [--input /path] [--output /path] [--service NAME] [--no-restart] [--keep-route-exclude]'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT=${2:?}
      shift 2
      ;;
    --output)
      OUTPUT=${2:?}
      shift 2
      ;;
    --service)
      RESTART_SERVICE=${2:?}
      shift 2
      ;;
    --no-restart)
      DO_RESTART=0
      shift
      ;;
    --keep-route-exclude)
      KEEP_ROUTE_EXCLUDE=1
      shift
      ;;
    -h|--help)
      echo "$USAGE"
      exit 0
      ;;
    *)
      echo "unknown arg: $1"
      echo "$USAGE"
      exit 1
      ;;
  esac
done

if [[ ! -r "$INPUT" ]]; then
  echo "missing readable input config: $INPUT" >&2
  exit 1
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

KEEP_ROUTE_EXCLUDE_FLAG=$KEEP_ROUTE_EXCLUDE
python3 - "$INPUT" "$TMP" "$KEEP_ROUTE_EXCLUDE_FLAG" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
out = Path(sys.argv[2])
keep_route_exclude = sys.argv[3] == "1"
obj = json.loads(src.read_text())

# 1) Normalize DNS to local/system DNS
obj['dns'] = {
    'servers': [
        {'tag': 'local-dns', 'type': 'local'}
    ],
    'final': 'local-dns',
    'strategy': obj.get('dns', {}).get('strategy', 'ipv4_only')
}

# 2) Remove hijack-dns route rule
route = obj.get('route') or {}
rules = route.get('rules') or []
route['rules'] = [r for r in rules if not (isinstance(r, dict) and r.get('action') == 'hijack-dns')]
route['default_domain_resolver'] = 'local-dns'
obj['route'] = route

# 3) Remove tun route_exclude_address unless explicitly kept
if not keep_route_exclude:
    for inbound in obj.get('inbounds', []):
        if isinstance(inbound, dict) and inbound.get('type') == 'tun':
            inbound.pop('route_exclude_address', None)

out.write_text(json.dumps(obj, indent=2) + '\n')
PY

if [[ -z "$OUTPUT" ]]; then
  OUTPUT=$INPUT
  BACKUP="${INPUT}.backup.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -p "$INPUT" "$BACKUP"
  echo "backup=$BACKUP"
fi

cp "$TMP" "$OUTPUT"
chmod 600 "$OUTPUT"

echo "written=$OUTPUT"

# sanity summary
tmp_summary=$(mktemp)
cat >"$tmp_summary" <<'SH'
import json
import sys
obj = json.load(open(sys.argv[1]))
route = obj.get('route', {})
rules = route.get('rules', [])
route_excl = False
for inbound in obj.get('inbounds', []):
    if isinstance(inbound, dict) and inbound.get('type') == 'tun' and 'route_exclude_address' in inbound:
        route_excl = True
hijack = sum(1 for r in rules if isinstance(r, dict) and r.get('action') == 'hijack-dns')
print(f"dns_servers={len(obj.get('dns', {}).get('servers', []))}")
print(f"route_exclude_present={str(route_excl).lower()}")
print(f"route_rules={len(rules)}")
print(f"hijack_dns_rules={hijack}")
print(f"default_domain_resolver={route.get('default_domain_resolver')}")
SH
python3 "$tmp_summary" "$OUTPUT"
rm -f "$tmp_summary"

if [[ "$OUTPUT" == "$INPUT" && "$DO_RESTART" -eq 1 ]]; then
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart "$RESTART_SERVICE"
    echo "restart=$RESTART_SERVICE"
    systemctl status --no-pager "$RESTART_SERVICE" | sed -n '1,5p'
  else
    echo "systemctl unavailable; restart manually"
    exit 1
  fi
fi

if [[ "$DO_RESTART" -eq 0 ]]; then
  echo "restart skipped"
fi
