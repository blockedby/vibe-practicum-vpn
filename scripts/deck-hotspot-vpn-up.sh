#!/usr/bin/env bash
set -Eeuo pipefail

SSH_TARGET=${DECK_HOTSPOT_SSH_TARGET:-${VPNKIT_STEAMDECK_SSH_TARGET:-deck}}
REMOTE_DIR=${DECK_HOTSPOT_REMOTE_DIR:-/home/deck/code/tools/vibe-practicum-vpn/steam-deck/hotspot-client}
PODMAN_CMD=${DECK_HOTSPOT_PODMAN:-"sudo podman --root /home/deck/.local/share/vpnkit-root-podman --runroot /run/vpnkit-root-podman"}
UPLINK_IFACE=${DECK_HOTSPOT_UPLINK_IFACE:-wlan0}
HOTSPOT_IFACE=${DECK_HOTSPOT_IFACE:-ap0}
SSID=${DECK_HOTSPOT_SSID:-vpnkit-deck}
PASSWORD=${DECK_HOTSPOT_PASSWORD:-}
VPN_IFACE=${DECK_HOTSPOT_VPN_IFACE:-tun0}
NFT_TABLE=${DECK_HOTSPOT_NFT_TABLE:-vpnkit_deck_hotspot}
HOTSPOT_CONTAINER=${DECK_HOTSPOT_CONTAINER:-vpnkit-deck-hotspot-ap}
HOTSPOT_IMAGE=${DECK_HOTSPOT_IMAGE:-localhost/vpnkit-deck-hotspot-ap:latest}
HOTSPOT_CIDR=${DECK_HOTSPOT_CIDR:-10.42.0.1/24}
HOTSPOT_IP=${HOTSPOT_CIDR%%/*}
HOTSPOT_SUBNET=${DECK_HOTSPOT_SUBNET:-10.42.0.0/24}
DHCP_RANGE=${DECK_HOTSPOT_DHCP_RANGE:-10.42.0.10,10.42.0.100,255.255.255.0,12h}
REPORT_PATH=${DECK_HOTSPOT_REPORT_PATH:-}
DRY_RUN=1
YES=0
SSH_OPTS=()

usage(){ cat <<'EOF'
Usage: scripts/deck-hotspot-vpn-up.sh [options]

Prepare/bring up Steam Deck hotspot -> VPN gateway with durable report.
Default is --dry-run (no mutation). To mutate, pass --apply --yes and provide
DECK_HOTSPOT_PASSWORD or --password. This does not recreate the existing vpnkit
container; it expects a host-namespace VPN interface such as tun0 to already exist.

Options:
  --ssh-target HOST      SSH target (default deck)
  --remote-dir DIR       Repo path on Deck (default /home/deck/code/tools/vibe-practicum-vpn/steam-deck/hotspot-client)
  --podman CMD           Podman command, can include sudo/root/runroot args
  --uplink-iface IFACE   Internet uplink iface (default wlan0)
  --hotspot-iface IFACE  Virtual AP iface (default ap0)
  --ssid SSID            Hotspot SSID (default vpnkit-deck)
  --password PASS        Hotspot WPA password (not printed)
  --vpn-iface IFACE      VPN tunnel iface expected for egress (default tun0)
  --nft-table NAME       Dedicated nft inet table name
  --report PATH          Report path under reports/
  --dry-run              Plan only, no mutation (default)
  --apply --yes          Actually create AP container/nft rules/sysctl
EOF
}
while [[ $# -gt 0 ]]; do case "$1" in
  --ssh-target) SSH_TARGET=${2:?}; shift 2;; --remote-dir) REMOTE_DIR=${2:?}; shift 2;; --podman) PODMAN_CMD=${2:?}; shift 2;;
  --uplink-iface) UPLINK_IFACE=${2:?}; shift 2;; --hotspot-iface) HOTSPOT_IFACE=${2:?}; shift 2;;
  --ssid) SSID=${2:?}; shift 2;; --password) PASSWORD=${2:?}; shift 2;; --vpn-iface) VPN_IFACE=${2:?}; shift 2;;
  --nft-table) NFT_TABLE=${2:?}; shift 2;; --report) REPORT_PATH=${2:?}; shift 2;;
  --dry-run) DRY_RUN=1; shift;; --apply) DRY_RUN=0; shift;; --yes) YES=1; shift;;
  --ssh-option) read -r -a opt <<< "${2:?}"; SSH_OPTS+=("${opt[@]}"); shift 2;;
  -h|--help) usage; exit 0;; *) echo "unknown argument: $1" >&2; usage >&2; exit 2;;
esac; done
[[ "$UPLINK_IFACE$HOTSPOT_IFACE$VPN_IFACE" =~ ^[A-Za-z0-9_.:-]+$ && "$NFT_TABLE" =~ ^[A-Za-z0-9_:-]+$ ]] || { echo "unsafe interface/table name" >&2; exit 2; }
if [[ $DRY_RUN -eq 0 ]]; then
  [[ $YES -eq 1 || ${DECK_HOTSPOT_CONFIRM:-} == YES ]] || { echo "refusing mutation without --yes or DECK_HOTSPOT_CONFIRM=YES" >&2; exit 3; }
  [[ ${#PASSWORD} -ge 8 ]] || { echo "hotspot password must be at least 8 chars for --apply" >&2; exit 2; }
fi
[[ -n "$REPORT_PATH" ]] || REPORT_PATH="reports/steam-deck-hotspot-up-$(date -u +%Y%m%dT%H%M%SZ).md"
mkdir -p "$(dirname "$REPORT_PATH")"
redact(){
  sed -E \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' \
    -e 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<MAC>/Ig' \
    -e 's/[0-9a-f]{4}(:[0-9a-f]{0,4}){2,7}/<IPv6>/Ig' \
    -e 's/[0-9a-f]{8}-[0-9a-f-]{27,}/<UUID>/Ig' \
    -e "s/${PASSWORD//\//\/}/[redacted-password]/g"
}
shell_quote(){ printf '%q' "$1"; }
{
  echo "# Steam Deck hotspot VPN up report"
  echo
  echo "- Timestamp: $(date -u +%FT%TZ)"
  echo "- SSH target: <redacted>"
  echo "- Mode: $([[ $DRY_RUN -eq 1 ]] && echo dry-run || echo apply)"
  echo "- Topology: $UPLINK_IFACE uplink, $HOTSPOT_IFACE hostapd AP, $VPN_IFACE VPN egress"
  echo
  echo '```text'
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" \
    "DRY_RUN=$(shell_quote "$DRY_RUN") REMOTE_DIR=$(shell_quote "$REMOTE_DIR") PODMAN_CMD=$(shell_quote "$PODMAN_CMD") UPLINK_IFACE=$(shell_quote "$UPLINK_IFACE") HOTSPOT_IFACE=$(shell_quote "$HOTSPOT_IFACE") SSID=$(shell_quote "$SSID") PASSWORD=$(shell_quote "$PASSWORD") VPN_IFACE=$(shell_quote "$VPN_IFACE") NFT_TABLE=$(shell_quote "$NFT_TABLE") HOTSPOT_CONTAINER=$(shell_quote "$HOTSPOT_CONTAINER") HOTSPOT_IMAGE=$(shell_quote "$HOTSPOT_IMAGE") HOTSPOT_CIDR=$(shell_quote "$HOTSPOT_CIDR") HOTSPOT_IP=$(shell_quote "$HOTSPOT_IP") HOTSPOT_SUBNET=$(shell_quote "$HOTSPOT_SUBNET") DHCP_RANGE=$(shell_quote "$DHCP_RANGE") bash -s" <<'REMOTE'
set -Eeuo pipefail
read -r -a PODMAN <<<"$PODMAN_CMD"
log(){ printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
run(){ log "+ $*"; "$@"; }
podman_cmd(){ "${PODMAN[@]}" "$@"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 10; }; }
need ip; need iw; need sudo; need nft
log "preflight"
command -v nmcli >/dev/null 2>&1 && nmcli -f DEVICE,TYPE,STATE dev status || true
ip -br addr || true
ip route get 1.1.1.1 || true
[[ -d "$REMOTE_DIR" ]] || { echo "remote dir missing: $REMOTE_DIR"; exit 10; }
[[ -f "$REMOTE_DIR/Containerfile.hotspot" ]] || { echo "missing Containerfile.hotspot in $REMOTE_DIR"; exit 10; }
[[ -f "$REMOTE_DIR/scripts/hotspot-entrypoint.sh" ]] || { echo "missing hotspot entrypoint in $REMOTE_DIR"; exit 10; }
if ! ip link show "$UPLINK_IFACE" >/dev/null 2>&1; then echo "uplink iface missing: $UPLINK_IFACE"; exit 11; fi
if ! ip link show "$VPN_IFACE" >/dev/null 2>&1; then echo "vpn iface missing: $VPN_IFACE (start host-namespace VPN first)"; exit 13; fi
if [[ "$DRY_RUN" = 1 ]]; then
  log "dry-run plan: would create virtual AP iface $HOTSPOT_IFACE from $UPLINK_IFACE"
  log "dry-run plan: would assign $HOTSPOT_CIDR to $HOTSPOT_IFACE"
  log "dry-run plan: would build/run hostapd+dnsmasq container $HOTSPOT_CONTAINER ($HOTSPOT_IMAGE)"
  log "dry-run plan: would put $HOTSPOT_IFACE into firewalld trusted zone when firewalld is active"
  log "dry-run plan: would enable net.ipv4.ip_forward=1 and nft NAT $HOTSPOT_SUBNET -> $VPN_IFACE"
  exit 0
fi
cleanup_on_fail(){ rc=$?; if [[ $rc -ne 0 ]]; then log "failure rc=$rc; cleanup"; podman_cmd rm -f "$HOTSPOT_CONTAINER" || true; sudo nft delete table inet "$NFT_TABLE" || true; if command -v firewall-cmd >/dev/null 2>&1 && sudo firewall-cmd --state >/dev/null 2>&1; then sudo firewall-cmd --zone=trusted --remove-interface="$HOTSPOT_IFACE" || true; fi; sudo iw dev "$HOTSPOT_IFACE" del || true; fi; exit $rc; }
trap cleanup_on_fail EXIT
podman_cmd rm -f "$HOTSPOT_CONTAINER" >/dev/null 2>&1 || true
sudo nft delete table inet "$NFT_TABLE" >/dev/null 2>&1 || true
sudo iw dev "$HOTSPOT_IFACE" del >/dev/null 2>&1 || true
run sudo iw dev "$UPLINK_IFACE" interface add "$HOTSPOT_IFACE" type __ap
run sudo ip addr flush dev "$HOTSPOT_IFACE"
run sudo ip addr add "$HOTSPOT_CIDR" dev "$HOTSPOT_IFACE"
run sudo ip link set "$HOTSPOT_IFACE" up
if command -v firewall-cmd >/dev/null 2>&1 && sudo firewall-cmd --state >/dev/null 2>&1; then
  run sudo firewall-cmd --zone=trusted --add-interface="$HOTSPOT_IFACE"
fi
RUNTIME_DIR="$REMOTE_DIR/runtime/hotspot"
LOG_DIR="$REMOTE_DIR/logs/hotspot"
run mkdir -p "$RUNTIME_DIR" "$LOG_DIR"
cat >"$RUNTIME_DIR/hostapd.conf" <<EOF_HOSTAPD
interface=$HOTSPOT_IFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=6
wmm_enabled=1
auth_algs=1
wpa=2
wpa_passphrase=$PASSWORD
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF_HOSTAPD
cat >"$RUNTIME_DIR/dnsmasq.conf" <<EOF_DNSMASQ
interface=$HOTSPOT_IFACE
bind-dynamic
listen-address=$HOTSPOT_IP
dhcp-authoritative
dhcp-range=$DHCP_RANGE
dhcp-option=3,$HOTSPOT_IP
dhcp-option=6,$HOTSPOT_IP
server=1.1.1.1
server=8.8.8.8
log-dhcp
log-queries
log-facility=/var/log/vpnkit-hotspot/dnsmasq.log
EOF_DNSMASQ
run podman_cmd build -t "$HOTSPOT_IMAGE" -f "$REMOTE_DIR/Containerfile.hotspot" "$REMOTE_DIR"
run sudo sysctl -w net.ipv4.ip_forward=1
cat >"$RUNTIME_DIR/${NFT_TABLE}.nft" <<EOF_NFT
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
run sudo nft -f "$RUNTIME_DIR/${NFT_TABLE}.nft"
run podman_cmd run -d --name "$HOTSPOT_CONTAINER" --replace --network host --privileged \
  -e VPNKIT_HOTSPOT_LOG_DIR=/var/log/vpnkit-hotspot \
  -v "$RUNTIME_DIR:/etc/vpnkit-hotspot:ro" \
  -v "$LOG_DIR:/var/log/vpnkit-hotspot" \
  "$HOTSPOT_IMAGE"
sleep 1
log "checking hostapd/dnsmasq readiness"
ready=0
for attempt in {1..10}; do
  if podman_cmd exec "$HOTSPOT_CONTAINER" pgrep -x hostapd >/dev/null 2>&1 \
    && podman_cmd exec "$HOTSPOT_CONTAINER" pgrep -x dnsmasq >/dev/null 2>&1 \
    && sudo ss -H -lunp 2>/dev/null | grep -E "[.:]67\\b" | grep -q 'dnsmasq' \
    && sudo grep -q 'AP-ENABLED' "$LOG_DIR/hostapd.log" \
    && sudo grep -Eq 'DHCP, sockets bound|DHCP, IP range|started' "$LOG_DIR/dnsmasq.log"; then
    ready=1
    break
  fi
  sleep 1
done
if [[ $ready -ne 1 ]]; then
  log "dnsmasq readiness failed"
  podman_cmd ps -a --filter "name=^${HOTSPOT_CONTAINER}$" --format 'container={{.Names}} status={{.Status}} image={{.Image}}' || true
  podman_cmd logs --tail 80 "$HOTSPOT_CONTAINER" 2>&1 | grep -E 'dnsmasq|hostapd|DHCP|failed|error|warning|started|AP-ENABLED|listening|bound' || true
  sudo ss -lunp | grep -E ':(53|67)\\b|dnsmasq|hostapd' || true
  exit 14
fi
podman_cmd ps --filter "name=^${HOTSPOT_CONTAINER}$" --format 'container={{.Names}} status={{.Status}} image={{.Image}}'
iw dev | sed -n "/Interface $HOTSPOT_IFACE/,+10p" || true
sudo ss -lunp | grep -E ':(53|67)\\b|dnsmasq' || true
sudo grep -E 'AP-ENABLED|DHCP, sockets bound|DHCP, IP range|started' "$LOG_DIR/hostapd.log" "$LOG_DIR/dnsmasq.log" || true
trap - EXIT
log "up done"
REMOTE
  echo '```'
} 2>&1 | redact | tee "$REPORT_PATH"
printf 'report_path=%s\n' "$REPORT_PATH"
