#!/usr/bin/env bash
set -Eeuo pipefail

SSH_TARGET=${DECK_HOTSPOT_SSH_TARGET:-${VPNKIT_STEAMDECK_SSH_TARGET:-deck}}
PODMAN_CMD=${DECK_HOTSPOT_PODMAN:-"sudo podman --root /home/deck/.local/share/vpnkit-root-podman --runroot /run/vpnkit-root-podman"}
HOTSPOT_CONTAINER=${DECK_HOTSPOT_CONTAINER:-vpnkit-deck-hotspot-ap}
NFT_TABLE=${DECK_HOTSPOT_NFT_TABLE:-vpnkit_deck_hotspot}
UPLINK_IFACE=${DECK_HOTSPOT_UPLINK_IFACE:-wlan0}
HOTSPOT_IFACE=${DECK_HOTSPOT_IFACE:-ap0}
REPORT_PATH=${DECK_HOTSPOT_REPORT_PATH:-}
SSH_OPTS=()

usage(){ cat <<'EOF'
Usage: scripts/deck-hotspot-vpn-down.sh [--ssh-target deck] [--hotspot-iface ap0] [--nft-table NAME] [--report PATH]

Idempotently remove this tool's Deck hotspot AP container, nft table, and
virtual AP interface. Does not stop the host OpenVPN client or existing vpnkit.
EOF
}
while [[ $# -gt 0 ]]; do case "$1" in
  --ssh-target) SSH_TARGET=${2:?}; shift 2;; --podman) PODMAN_CMD=${2:?}; shift 2;;
  --container) HOTSPOT_CONTAINER=${2:?}; shift 2;; --nft-table) NFT_TABLE=${2:?}; shift 2;;
  --uplink-iface) UPLINK_IFACE=${2:?}; shift 2;; --hotspot-iface) HOTSPOT_IFACE=${2:?}; shift 2;;
  --report) REPORT_PATH=${2:?}; shift 2;; --ssh-option) read -r -a opt <<< "${2:?}"; SSH_OPTS+=("${opt[@]}"); shift 2;;
  -h|--help) usage; exit 0;; *) echo "unknown argument: $1" >&2; usage >&2; exit 2;;
esac; done
[[ "$HOTSPOT_CONTAINER$NFT_TABLE$UPLINK_IFACE$HOTSPOT_IFACE" =~ ^[A-Za-z0-9_.:-]+$ ]] || { echo "unsafe name" >&2; exit 2; }
[[ -n "$REPORT_PATH" ]] || REPORT_PATH="reports/steam-deck-hotspot-down-$(date -u +%Y%m%dT%H%M%SZ).md"
mkdir -p "$(dirname "$REPORT_PATH")"
redact(){ sed -E -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' -e 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<MAC>/Ig' -e 's/[0-9a-f]{4}(:[0-9a-f]{0,4}){2,7}/<IPv6>/Ig' -e 's/[0-9a-f]{8}-[0-9a-f-]{27,}/<UUID>/Ig'; }
shell_quote(){ printf '%q' "$1"; }
{
  echo "# Steam Deck hotspot VPN down report"
  echo
  echo "- Timestamp: $(date -u +%FT%TZ)"
  echo "- SSH target: <redacted>"
  echo "- Container: $HOTSPOT_CONTAINER"
  echo "- nft table: $NFT_TABLE"
  echo "- hotspot iface: $HOTSPOT_IFACE"
  echo
  echo '```text'
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "PODMAN_CMD=$(shell_quote "$PODMAN_CMD") HOTSPOT_CONTAINER=$(shell_quote "$HOTSPOT_CONTAINER") NFT_TABLE=$(shell_quote "$NFT_TABLE") UPLINK_IFACE=$(shell_quote "$UPLINK_IFACE") HOTSPOT_IFACE=$(shell_quote "$HOTSPOT_IFACE") bash -s" <<'REMOTE'
set -Eeuo pipefail
read -r -a PODMAN <<<"$PODMAN_CMD"
log(){ printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
podman_cmd(){ "${PODMAN[@]}" "$@"; }
log "down start"
log "removing hotspot AP container $HOTSPOT_CONTAINER"
podman_cmd rm -f "$HOTSPOT_CONTAINER" || true
if command -v nft >/dev/null 2>&1; then
  log "deleting nft table inet $NFT_TABLE"
  sudo nft delete table inet "$NFT_TABLE" || true
fi
if [[ "$HOTSPOT_IFACE" != "$UPLINK_IFACE" ]] && ip link show "$HOTSPOT_IFACE" >/dev/null 2>&1; then
  log "deleting virtual AP interface $HOTSPOT_IFACE"
  sudo iw dev "$HOTSPOT_IFACE" del || true
fi
log "current status"
command -v nmcli >/dev/null 2>&1 && nmcli -f DEVICE,TYPE,STATE dev status || true
ip -br addr || true
sysctl net.ipv4.ip_forward || true
log "down done"
REMOTE
  echo '```'
} 2>&1 | redact | tee "$REPORT_PATH"
printf 'report_path=%s\n' "$REPORT_PATH"
