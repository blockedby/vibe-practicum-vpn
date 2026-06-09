#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

if ! command -v sing-box >/dev/null 2>&1; then
  echo "skip: sing-box binary unavailable" >&2
  exit 0
fi

tmp=$(mktemp -d)
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

selected_out='{
  "type": "direct",
  "tag": "selected-native-out"
}'

render_and_check() {
  local template=$1
  local out=$2
  python3 - "$template" "$out" "$selected_out" <<'PY'
import pathlib, sys
src, dst, selected = sys.argv[1:]
text = pathlib.Path(src).read_text().replace('{{SELECTED_NATIVE_OUT_JSON}}', selected)
pathlib.Path(dst).write_text(text)
PY

  if grep -q '"address"[[:space:]]*:[[:space:]]*"tls://' "$out"; then
    echo "legacy DNS address form remains in $template" >&2
    return 1
  fi
  grep -q '"type"[[:space:]]*:[[:space:]]*"tls"' "$out" \
    || { echo "missing new DNS type=tls in $template" >&2; return 1; }
  grep -q '"server"[[:space:]]*:[[:space:]]*"8\.8\.8\.8"' "$out" \
    || { echo "missing new DNS server in $template" >&2; return 1; }
  grep -q '"default_domain_resolver"[[:space:]]*:[[:space:]]*"remote-dns"' "$out" \
    || { echo "missing route.default_domain_resolver in $template" >&2; return 1; }

  env -u ENABLE_DEPRECATED_LEGACY_DNS_SERVERS \
      -u ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER \
      sing-box check -c "$out" >/dev/null
}

render_and_check config/sing-box/config.json.template "$tmp/redirect.json"
render_and_check config/sing-box/config.tun.json.template "$tmp/tun.json"

if grep -R -n 'ENABLE_DEPRECATED_LEGACY_DNS_SERVERS\|ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER' \
  docker-compose.yml scripts/vpnkit-steamdeck-podman.sh config/sing-box >/tmp/deprecated-env-grep.out; then
  cat /tmp/deprecated-env-grep.out >&2
  echo "deprecated sing-box DNS compatibility env remains in tracked runtime wiring" >&2
  exit 1
fi

printf 'sing-box DNS schema tests passed\n'
