#!/usr/bin/env bash
set -Eeuo pipefail

SSH_TARGET=${DECK_HOTSPOT_SSH_TARGET:-${VPNKIT_STEAMDECK_SSH_TARGET:-deck}}
UPLINK_IFACE=${DECK_HOTSPOT_UPLINK_IFACE:-wlan0}
HOTSPOT_IFACE=${DECK_HOTSPOT_IFACE:-ap0}
CONNECTION=${DECK_HOTSPOT_CONNECTION:-vpnkit-deck-hotspot}
SSID=${DECK_HOTSPOT_SSID:-vpnkit-deck}
PASSWORD=${DECK_HOTSPOT_PASSWORD:-}
VPN_IFACE=${DECK_HOTSPOT_VPN_IFACE:-tun0}
NFT_TABLE=${DECK_HOTSPOT_NFT_TABLE:-vpnkit_deck_hotspot}
REPORT_PATH=${DECK_HOTSPOT_REPORT_PATH:-}
DRY_RUN=1
YES=0
SSH_OPTS=()

usage(){ cat <<'EOF'
Usage: scripts/deck-hotspot-vpn-up.sh [options]

Prepare/bring up Steam Deck hotspot -> VPN gateway with durable report.
Default is --dry-run (no mutation). To mutate, pass --apply --yes and provide
DECK_HOTSPOT_PASSWORD or --password. This does not recreate the existing vpnkit
container; it expects the VPN interface/container to already exist or reports it.

Options:
  --ssh-target HOST      SSH target (default deck)
  --uplink-iface IFACE   Internet uplink iface (default wlan0)
  --hotspot-iface IFACE  Hotspot/AP iface; one-adapter default ap0 virtual AP
  --connection NAME      NM connection name (default vpnkit-deck-hotspot)
  --ssid SSID            Hotspot SSID (default vpnkit-deck)
  --password PASS        Hotspot WPA password (not printed)
  --vpn-iface IFACE      VPN tunnel iface expected for egress (default tun0)
  --nft-table NAME       Dedicated nft inet table name
  --report PATH          Report path under reports/
  --dry-run              Plan only, no mutation (default)
  --apply --yes          Actually create hotspot/nft rules/sysctl
EOF
}
while [[ $# -gt 0 ]]; do case "$1" in
  --ssh-target) SSH_TARGET=${2:?}; shift 2;; --uplink-iface) UPLINK_IFACE=${2:?}; shift 2;;
  --hotspot-iface) HOTSPOT_IFACE=${2:?}; shift 2;; --connection) CONNECTION=${2:?}; shift 2;;
  --ssid) SSID=${2:?}; shift 2;; --password) PASSWORD=${2:?}; shift 2;; --vpn-iface) VPN_IFACE=${2:?}; shift 2;;
  --nft-table) NFT_TABLE=${2:?}; shift 2;; --report) REPORT_PATH=${2:?}; shift 2;;
  --dry-run) DRY_RUN=1; shift;; --apply) DRY_RUN=0; shift;; --yes) YES=1; shift;;
  --ssh-option) read -r -a opt <<< "${2:?}"; SSH_OPTS+=("${opt[@]}"); shift 2;;
  -h|--help) usage; exit 0;; *) echo "unknown argument: $1" >&2; usage >&2; exit 2;;
esac; done
[[ "$UPLINK_IFACE$HOTSPOT_IFACE$VPN_IFACE" =~ ^[A-Za-z0-9_.:-]+$ && "$CONNECTION" =~ ^[A-Za-z0-9_.:-]+$ && "$NFT_TABLE" =~ ^[A-Za-z0-9_:-]+$ ]] || { echo "unsafe interface/connection/table name" >&2; exit 2; }
if [[ $DRY_RUN -eq 0 ]]; then
  [[ $YES -eq 1 || ${DECK_HOTSPOT_CONFIRM:-} == YES ]] || { echo "refusing mutation without --yes or DECK_HOTSPOT_CONFIRM=YES" >&2; exit 3; }
  [[ ${#PASSWORD} -ge 8 ]] || { echo "hotspot password must be at least 8 chars for --apply" >&2; exit 2; }
fi
[[ -n "$REPORT_PATH" ]] || REPORT_PATH="reports/steam-deck-hotspot-up-$(date -u +%Y%m%dT%H%M%SZ).md"
mkdir -p "$(dirname "$REPORT_PATH")"
redact(){
  if [[ -n "$PASSWORD" ]]; then
    sed -E -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' -e 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<MAC>/Ig' -e 's/[0-9a-f]{4}(:[0-9a-f]{0,4}){2,7}/<IPv6>/Ig' -e 's/[0-9a-f]{8}-[0-9a-f-]{27,}/<UUID>/Ig' -e 's/(Machine ID:).*/\1 <redacted>/I' -e 's/(Boot ID:).*/\1 <redacted>/I' -e "s/${PASSWORD//\//\/}/[redacted-password]/g"
  else
    sed -E -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' -e 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<MAC>/Ig' -e 's/[0-9a-f]{4}(:[0-9a-f]{0,4}){2,7}/<IPv6>/Ig' -e 's/[0-9a-f]{8}-[0-9a-f-]{27,}/<UUID>/Ig' -e 's/(Machine ID:).*/\1 <redacted>/I' -e 's/(Boot ID:).*/\1 <redacted>/I'
  fi
}
shell_quote(){ printf '%q' "$1"; }
{
  echo "# Steam Deck hotspot VPN up report"
  echo
  echo "- Timestamp: $(date -u +%FT%TZ)"
  echo "- SSH target: <redacted>"
  echo "- Mode: $([[ $DRY_RUN -eq 1 ]] && echo dry-run || echo apply)"
  echo "- Topology: $UPLINK_IFACE uplink, $HOTSPOT_IFACE hotspot/AP, $VPN_IFACE VPN egress"
  echo
  echo '```text'
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
    "DRY_RUN=$(shell_quote "$DRY_RUN") UPLINK_IFACE=$(shell_quote "$UPLINK_IFACE") HOTSPOT_IFACE=$(shell_quote "$HOTSPOT_IFACE") CONNECTION=$(shell_quote "$CONNECTION") SSID=$(shell_quote "$SSID") PASSWORD=$(shell_quote "$PASSWORD") VPN_IFACE=$(shell_quote "$VPN_IFACE") NFT_TABLE=$(shell_quote "$NFT_TABLE") bash -s" <<'REMOTE'
set -Eeuo pipefail
log(){ printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
run(){ log "+ $*"; "$@"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 10; }; }
need nmcli; need ip; need sysctl; need sudo
log "preflight"
nmcli -f DEVICE,TYPE,STATE dev status || true
ip -br addr || true
ip route get 1.1.1.1 || true
if ! ip link show "$UPLINK_IFACE" >/dev/null 2>&1; then echo "uplink iface missing: $UPLINK_IFACE"; exit 11; fi
if ! ip link show "$HOTSPOT_IFACE" >/dev/null 2>&1; then
  if [[ "$HOTSPOT_IFACE" != "$UPLINK_IFACE" ]]; then
    log "hotspot iface missing: $HOTSPOT_IFACE; will create virtual AP iface from $UPLINK_IFACE on apply"
  else
    echo "hotspot iface missing: $HOTSPOT_IFACE"; exit 12
  fi
fi
VPN_IFACE_PRESENT=1
if ! ip link show "$VPN_IFACE" >/dev/null 2>&1; then
  VPN_IFACE_PRESENT=0
  log "warning: vpn iface missing: $VPN_IFACE (host-namespace VPN tunnel must exist before apply can succeed)"
fi
HOTSPOT_SUBNET="10.42.0.0/24"
if [[ "$DRY_RUN" = 1 ]]; then
  if ! ip link show "$HOTSPOT_IFACE" >/dev/null 2>&1 && [[ "$HOTSPOT_IFACE" != "$UPLINK_IFACE" ]]; then
    log "dry-run plan: would create virtual AP iface: sudo iw dev $UPLINK_IFACE interface add $HOTSPOT_IFACE type __ap"
  fi
  log "dry-run plan: would create NM AP connection $CONNECTION on $HOTSPOT_IFACE"
  log "dry-run plan: would enable net.ipv4.ip_forward=1"
  log "dry-run plan: would create nft inet $NFT_TABLE allowing $HOTSPOT_IFACE->$VPN_IFACE, replies, masquerade, and rejecting $HOTSPOT_IFACE->$UPLINK_IFACE"
  if [[ "$VPN_IFACE_PRESENT" = 0 ]]; then log "dry-run blocker: start/reuse a host-namespace VPN tunnel first; existing container may keep tun inside container only"; fi
  exit 0
fi
if [[ "$VPN_IFACE_PRESENT" = 0 ]]; then echo "vpn iface missing: $VPN_IFACE (start/reuse host-namespace VPN first)"; exit 13; fi
cleanup_on_fail(){ rc=$?; if [[ $rc -ne 0 ]]; then log "failure rc=$rc; invoking down cleanup"; sudo nmcli con down "$CONNECTION" || true; sudo nmcli con delete "$CONNECTION" || true; command -v nft >/dev/null 2>&1 && sudo nft delete table inet "$NFT_TABLE" || true; if [[ "$HOTSPOT_IFACE" != "$UPLINK_IFACE" ]]; then sudo iw dev "$HOTSPOT_IFACE" del || true; fi; fi; exit $rc; }
trap cleanup_on_fail EXIT
if nmcli -t -f NAME con show | grep -Fxq "$CONNECTION"; then run sudo nmcli con delete "$CONNECTION" || true; fi
if ! ip link show "$HOTSPOT_IFACE" >/dev/null 2>&1 && [[ "$HOTSPOT_IFACE" != "$UPLINK_IFACE" ]]; then
  need iw
  run sudo iw dev "$UPLINK_IFACE" interface add "$HOTSPOT_IFACE" type __ap
  run sudo ip link set "$HOTSPOT_IFACE" up || true
fi
run sudo nmcli con add type wifi ifname "$HOTSPOT_IFACE" con-name "$CONNECTION" autoconnect no ssid "$SSID"
run sudo nmcli con modify "$CONNECTION" 802-11-wireless.mode ap 802-11-wireless.band bg ipv4.method shared
run sudo nmcli con modify "$CONNECTION" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$PASSWORD"
run sudo sysctl -w net.ipv4.ip_forward=1
if command -v nft >/dev/null 2>&1; then
  sudo nft delete table inet "$NFT_TABLE" >/dev/null 2>&1 || true
  cat > /tmp/${NFT_TABLE}.nft <<EOF_NFT
table inet $NFT_TABLE {
 chain forward {
  type filter hook forward priority 0; policy accept;
  iifname "$HOTSPOT_IFACE" oifname "$VPN_IFACE" accept
  iifname "$VPN_IFACE" oifname "$HOTSPOT_IFACE" ct state established,related accept
  iifname "$HOTSPOT_IFACE" oifname "$UPLINK_IFACE" reject
 }
 chain postrouting {
  type nat hook postrouting priority srcnat; policy accept;
  ip saddr $HOTSPOT_SUBNET oifname "$VPN_IFACE" masquerade
 }
}
EOF_NFT
  sudo nft -f /tmp/${NFT_TABLE}.nft
else
  echo "nft missing; refusing apply until iptables fallback is explicitly implemented"; exit 14
fi
run sudo nmcli con up "$CONNECTION"
log "post status"
nmcli -f DEVICE,TYPE,STATE dev status || true
ip -br addr || true
sysctl net.ipv4.ip_forward || true
trap - EXIT
log "up done"
REMOTE
  echo '```'
} 2>&1 | redact | tee "$REPORT_PATH"
printf 'report_path=%s\n' "$REPORT_PATH"
