#!/usr/bin/env bash
set -Eeuo pipefail

SSH_TARGET=${DECK_HOTSPOT_SSH_TARGET:-${VPNKIT_STEAMDECK_SSH_TARGET:-deck}}
REPORT_PATH=${DECK_HOTSPOT_REPORT_PATH:-}
SSH_OPTS=()

usage(){ cat <<'EOF'
Usage: scripts/deck-hotspot-vpn-discover.sh [--ssh-target deck] [--report PATH] [--ssh-option OPT]

Read-only Steam Deck hotspot/VPN gateway discovery. Writes a redacted report.
EOF
}
while [[ $# -gt 0 ]]; do case "$1" in
  --ssh-target) SSH_TARGET=${2:?}; shift 2;;
  --report) REPORT_PATH=${2:?}; shift 2;;
  --ssh-option) read -r -a opt <<< "${2:?}"; SSH_OPTS+=("${opt[@]}"); shift 2;;
  -h|--help) usage; exit 0;;
  *) echo "unknown argument: $1" >&2; usage >&2; exit 2;;
esac; done
[[ -n "$REPORT_PATH" ]] || REPORT_PATH="reports/steam-deck-hotspot-discovery-$(date -u +%Y%m%dT%H%M%SZ).md"
mkdir -p "$(dirname "$REPORT_PATH")"
redact(){ sed -E -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' -e 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<MAC>/Ig' -e 's/[0-9a-f]{4}(:[0-9a-f]{0,4}){2,7}/<IPv6>/Ig' -e 's/[0-9a-f]{8}-[0-9a-f-]{27,}/<UUID>/Ig' -e 's/(Machine ID:).*/\1 <redacted>/I' -e 's/(Boot ID:).*/\1 <redacted>/I' -e 's#(vless|trojan|ss|hysteria2)://[^[:space:]]+#\1://[redacted]#g' -e 's/(password|private[_-]?key|token|secret)[=: ][^[:space:]]+/\1=<redacted>/Ig'; }
log(){ printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
{
  echo "# Steam Deck hotspot VPN discovery"
  echo
  echo "- Timestamp: $(date -u +%FT%TZ)"
  echo "- SSH target: <redacted>"
  echo "- Mutation: none/read-only"
  echo
  echo '```text'
  log "host inventory"
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'bash -s' <<'REMOTE'
set -Eeuo pipefail
section(){ printf '\n## %s\n' "$1"; }
run(){ section "$1"; shift; "$@" 2>&1 || true; }
run "hostnamectl" hostnamectl
run "uname" uname -a
run "ip-link" ip -br link
run "ip-addr" ip -br addr
run "ip-route" ip route
run "nmcli-dev" nmcli -f DEVICE,TYPE,STATE dev status
run "nmcli-con" nmcli -f TYPE,DEVICE,AUTOCONNECT con show
run "runtime" bash -lc 'podman --version || true; docker --version || true; podman ps --filter "name=^vpnkit$" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" || true'
run "tun-forward-firewall" bash -lc 'ls -l /dev/net/tun || true; sysctl net.ipv4.ip_forward || true; command -v nft || true; command -v iptables || true'
run "wifi-dev" iw dev
run "wifi-supported-modes" bash -lc "iw list | sed -n '/Supported interface modes:/,/Band 1:/p' | head -120"
run "wifi-valid-combinations" bash -lc "iw list | sed -n '/valid interface combinations:/,/Device supports/p' | head -140"
REMOTE
  echo '```'
} 2>&1 | redact | tee "$REPORT_PATH"
printf 'report_path=%s\n' "$REPORT_PATH"
