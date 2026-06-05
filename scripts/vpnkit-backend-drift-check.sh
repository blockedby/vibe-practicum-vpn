#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Read-only vpnkit backend drift check.

Checks one or more SSH targets without touching ASUS/router and without printing
private endpoints, generated profiles, rendered config contents, logs, or secrets.

Usage:
  scripts/vpnkit-backend-drift-check.sh <ssh-target> [<ssh-target> ...]
  VPNKIT_BACKEND_SSH_HOSTS="alias-a alias-b" scripts/vpnkit-backend-drift-check.sh

What it reads on each backend:
  - running Docker container whose name contains "vpnkit"
  - selected-native-out type in runtime /var/lib/vpnkit/sing-box/config.json
  - selected-native-out type in source /etc/sing-box/config.json
  - vibe-vpn status using /etc/vibe-vpn/config.yaml when present
  - host direct egress vs container SOCKS egress, reported only as equality/hash

No live mutation is performed. No router/ASUS access is attempted.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

declare -a TARGETS=()
if [[ $# -gt 0 ]]; then
  TARGETS=("$@")
elif [[ -n "${VPNKIT_BACKEND_SSH_HOSTS:-}" ]]; then
  # shellcheck disable=SC2206 # intentional whitespace-separated operator list
  TARGETS=(${VPNKIT_BACKEND_SSH_HOSTS})
else
  echo "Missing SSH targets. Pass aliases as arguments or set VPNKIT_BACKEND_SSH_HOSTS." >&2
  usage >&2
  exit 2
fi

REMOTE_SCRIPT='set -eu
hash8() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf "%s" "$1" | sha256sum | cut -c1-8
  elif command -v shasum >/dev/null 2>&1; then
    printf "%s" "$1" | shasum -a 256 | cut -c1-8
  else
    printf "unavailable"
  fi
}
selected_type() {
  f="$1"
  if [ ! -r "$f" ]; then
    printf "missing"
    return 0
  fi
  if ! grep -q "selected-native-out" "$f" 2>/dev/null; then
    printf "missing-tag"
    return 0
  fi
  line="$(grep -n "\\\"tag\\\"[[:space:]]*:[[:space:]]*\\\"selected-native-out\\\"" "$f" | head -1 | cut -d: -f1)"
  if [ -z "$line" ]; then
    printf "missing-outbound-tag"
    return 0
  fi
  start=$((line - 40)); [ "$start" -lt 1 ] && start=1
  end=$((line + 40))
  window="$(sed -n "${start},${end}p" "$f")"
  # The selected outbound is expected to be either direct or a proxy outbound
  # such as vless. Avoid reporting nested transport.type=grpc as the outbound
  # type by preferring known outbound types from the selected object window.
  if printf "%s\n" "$window" | grep -Eq "\"type\"[[:space:]]*:[[:space:]]*\"vless\""; then
    printf "vless"
  elif printf "%s\n" "$window" | grep -Eq "\"type\"[[:space:]]*:[[:space:]]*\"direct\""; then
    printf "direct"
  else
    typ="$(printf "%s\n" "$window" | sed -n "s/.*\"type\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | grep -v "remote" | head -1 || true)"
    [ -n "$typ" ] && printf "%s" "$typ" || printf "unknown"
  fi
}

container="$(docker ps --format "{{.Names}}" 2>/dev/null | grep -E "(^|[-_])vpnkit([-_]|$)|vpnkit" | head -1 || true)"
if [ -z "$container" ]; then
  echo "container=missing"
  exit 0
fi

echo "container=present"
echo "container_name_hash=$(hash8 "$container")"

runtime_type="$(docker exec "$container" sh -c "$(printf %s "$(declare -f selected_type); selected_type /var/lib/vpnkit/sing-box/config.json")" 2>/dev/null || printf "unreadable")"
source_type="$(docker exec "$container" sh -c "$(printf %s "$(declare -f selected_type); selected_type /etc/sing-box/config.json")" 2>/dev/null || printf "unreadable")"
echo "runtime_selected_native_out_type=$runtime_type"
echo "source_selected_native_out_type=$source_type"
if [ "$runtime_type" = "$source_type" ]; then
  echo "runtime_source_type_match=yes"
else
  echo "runtime_source_type_match=no"
fi

vibe_cmd="vibe-vpn"
if docker exec "$container" test -r /etc/vibe-vpn/config.yaml 2>/dev/null; then
  vibe_cmd="vibe-vpn --config /etc/vibe-vpn/config.yaml"
fi
status="$(docker exec "$container" sh -c "$vibe_cmd status" 2>/dev/null || true)"
if [ -n "$status" ]; then
  echo "vibe_vpn_status=ok"
  transport="$(printf "%s\n" "$status" | sed -n "s/^[[:space:]]*transport:[[:space:]]*//p" | head -1)"
  socks="$(printf "%s\n" "$status" | sed -n "s/^[[:space:]]*socks:[[:space:]]*//p" | head -1)"
  [ -n "$transport" ] && echo "vibe_vpn_current_transport=$transport" || true
  [ -n "$socks" ] && echo "vibe_vpn_live_socks=$socks" || true
else
  echo "vibe_vpn_status=unavailable"
fi

host_ip="$(curl -4fsS --max-time 8 https://ifconfig.me 2>/dev/null || true)"
socks_ip="$(docker exec "$container" sh -c "curl -4fsS --max-time 12 --socks5-hostname 127.0.0.1:2080 https://ifconfig.me" 2>/dev/null || true)"
if [ -n "$host_ip" ]; then
  echo "host_direct_egress_hash=$(hash8 "$host_ip")"
else
  echo "host_direct_egress_hash=unavailable"
fi
if [ -n "$socks_ip" ]; then
  echo "container_socks_egress_hash=$(hash8 "$socks_ip")"
else
  echo "container_socks_egress_hash=unavailable"
fi
if [ -n "$host_ip" ] && [ -n "$socks_ip" ]; then
  if [ "$host_ip" = "$socks_ip" ]; then
    echo "host_direct_equals_socks=yes"
  else
    echo "host_direct_equals_socks=no"
  fi
else
  echo "host_direct_equals_socks=unknown"
fi
'

redact() {
  # Defense in depth: remote script is designed not to print endpoints, but scrub
  # accidental IPv4s and common endpoint-looking key/value fields if they appear.
  sed -E \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' \
    -e 's/(server|host|endpoint|addr|address)=([^[:space:]]+)/\1=<redacted>/Ig' \
    -e 's/(server|host|endpoint|addr|address):[[:space:]]*[^[:space:]]+/\1: <redacted>/Ig'
}

for i in "${!TARGETS[@]}"; do
  n=$((i + 1))
  echo "=== backend[$n] ==="
  if ! ssh -o BatchMode=yes -o ConnectTimeout="${SSH_CONNECT_TIMEOUT:-8}" "${TARGETS[$i]}" "$REMOTE_SCRIPT" 2>&1 | redact; then
    echo "ssh_status=failed"
  fi
  echo
 done
