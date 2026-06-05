#!/usr/bin/env bash
set -Eeuo pipefail

SSH_TARGET=${DECK_HOTSPOT_SSH_TARGET:-${VPNKIT_STEAMDECK_SSH_TARGET:-deck}}
CONNECTION=${DECK_HOTSPOT_CONNECTION:-vpnkit-deck-hotspot}
NFT_TABLE=${DECK_HOTSPOT_NFT_TABLE:-vpnkit_deck_hotspot}
UPLINK_IFACE=${DECK_HOTSPOT_UPLINK_IFACE:-wlan0}
HOTSPOT_IFACE=${DECK_HOTSPOT_IFACE:-ap0}
REPORT_PATH=${DECK_HOTSPOT_REPORT_PATH:-}
SSH_OPTS=()

usage(){ cat <<'EOF'
Usage: scripts/deck-hotspot-vpn-down.sh [--ssh-target deck] [--connection NAME] [--nft-table NAME] [--hotspot-iface ap0] [--report PATH]

Idempotently remove this tool's Deck hotspot connection and nft table. Does not
stop the existing vpnkit container by default.
EOF
}
while [[ $# -gt 0 ]]; do case "$1" in
  --ssh-target) SSH_TARGET=${2:?}; shift 2;;
  --connection) CONNECTION=${2:?}; shift 2;;
  --nft-table) NFT_TABLE=${2:?}; shift 2;;
  --uplink-iface) UPLINK_IFACE=${2:?}; shift 2;;
  --hotspot-iface) HOTSPOT_IFACE=${2:?}; shift 2;;
  --report) REPORT_PATH=${2:?}; shift 2;;
  --ssh-option) read -r -a opt <<< "${2:?}"; SSH_OPTS+=("${opt[@]}"); shift 2;;
  -h|--help) usage; exit 0;;
  *) echo "unknown argument: $1" >&2; usage >&2; exit 2;;
esac; done
[[ "$CONNECTION" =~ ^[A-Za-z0-9_.:-]+$ && "$NFT_TABLE" =~ ^[A-Za-z0-9_:-]+$ && "$UPLINK_IFACE$HOTSPOT_IFACE" =~ ^[A-Za-z0-9_.:-]+$ ]] || { echo "unsafe connection/table name" >&2; exit 2; }
[[ -n "$REPORT_PATH" ]] || REPORT_PATH="reports/steam-deck-hotspot-down-$(date -u +%Y%m%dT%H%M%SZ).md"
mkdir -p "$(dirname "$REPORT_PATH")"
redact(){ sed -E -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' -e 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<MAC>/Ig' -e 's/[0-9a-f]{4}(:[0-9a-f]{0,4}){2,7}/<IPv6>/Ig' -e 's/[0-9a-f]{8}-[0-9a-f-]{27,}/<UUID>/Ig' -e 's/(Machine ID:).*/\1 <redacted>/I' -e 's/(Boot ID:).*/\1 <redacted>/I'; }
{
  echo "# Steam Deck hotspot VPN down report"
  echo
  echo "- Timestamp: $(date -u +%FT%TZ)"
  echo "- SSH target: <redacted>"
  echo "- Connection: $CONNECTION"
  echo "- nft table: $NFT_TABLE"
  echo "- hotspot iface: $HOTSPOT_IFACE"
  echo
  echo '```text'
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "CONNECTION='$CONNECTION' NFT_TABLE='$NFT_TABLE' UPLINK_IFACE='$UPLINK_IFACE' HOTSPOT_IFACE='$HOTSPOT_IFACE' bash -s" <<'REMOTE'
set -Eeuo pipefail
log(){ printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
log "down start"
if nmcli -t -f NAME con show | grep -Fxq "$CONNECTION"; then
  log "bringing down NetworkManager connection $CONNECTION"
  nmcli con down "$CONNECTION" || true
  log "deleting NetworkManager connection $CONNECTION"
  nmcli con delete "$CONNECTION" || true
else
  log "NetworkManager connection not present: $CONNECTION"
fi
if command -v nft >/dev/null 2>&1 && nft list table inet "$NFT_TABLE" >/dev/null 2>&1; then
  log "deleting nft table inet $NFT_TABLE"
  sudo nft delete table inet "$NFT_TABLE" || nft delete table inet "$NFT_TABLE" || true
else
  log "nft table not present: inet $NFT_TABLE"
fi
if [[ "$HOTSPOT_IFACE" != "$UPLINK_IFACE" ]] && ip link show "$HOTSPOT_IFACE" >/dev/null 2>&1; then
  log "deleting virtual AP interface $HOTSPOT_IFACE"
  sudo iw dev "$HOTSPOT_IFACE" del || true
fi
log "current hotspot-related status"
nmcli -f DEVICE,TYPE,STATE dev status || true
sysctl net.ipv4.ip_forward || true
log "down done"
REMOTE
  echo '```'
} 2>&1 | redact | tee "$REPORT_PATH"
printf 'report_path=%s\n' "$REPORT_PATH"
