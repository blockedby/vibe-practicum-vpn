#!/usr/bin/env bash
set -euo pipefail

# Route this PC's NetworkManager hotspot clients through the existing sing-box/VPN TUN.
# Defaults match the current host setup:
#   - hotspot/AP interface: wlan0, SSID managed separately by NetworkManager as "kcnc-hotspot"
#   - VPN/TUN interface: proxyvpn0
#   - sing-box route table: 2022
#
# Usage:
#   sudo scripts/local/kcnc-hotspot-vpn.sh up
#   sudo scripts/local/kcnc-hotspot-vpn.sh status
#   sudo scripts/local/kcnc-hotspot-vpn.sh down

HOTSPOT_IF=${HOTSPOT_IF:-wlan0}
VPN_IF=${VPN_IF:-proxyvpn0}
ROUTE_TABLE=${ROUTE_TABLE:-2022}
RULE_PRIO=${RULE_PRIO:-10022}
NFT_TABLE=${NFT_TABLE:-kcnc_hotspot_vpn}
FIREWALLD_DIRECT_COMMENT=${FIREWALLD_DIRECT_COMMENT:-kcnc-hotspot-vpn}
ACTION=${1:-up}

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "error: run as root, e.g. sudo $0 $ACTION" >&2
    exit 1
  fi
}

hotspot_subnet() {
  ip -4 -o addr show dev "$HOTSPOT_IF" | awk '{print $4; exit}'
}

check_inputs() {
  ip link show "$HOTSPOT_IF" >/dev/null
  ip link show "$VPN_IF" >/dev/null
  local subnet
  subnet=$(hotspot_subnet)
  if [[ -z "$subnet" ]]; then
    echo "error: no IPv4 address found on $HOTSPOT_IF" >&2
    exit 1
  fi
}

iptables_enable_rules() {
  local subnet=$1
  iptables -C FORWARD -i "$HOTSPOT_IF" -o "$VPN_IF" -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i "$HOTSPOT_IF" -o "$VPN_IF" -j ACCEPT
  iptables -C FORWARD -i "$VPN_IF" -o "$HOTSPOT_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i "$VPN_IF" -o "$HOTSPOT_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -t nat -C POSTROUTING -s "$subnet" -o "$VPN_IF" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s "$subnet" -o "$VPN_IF" -j MASQUERADE
}

iptables_disable_rules() {
  local subnet=$1
  iptables -D FORWARD -i "$HOTSPOT_IF" -o "$VPN_IF" -j ACCEPT 2>/dev/null || true
  iptables -D FORWARD -i "$VPN_IF" -o "$HOTSPOT_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
  if [[ -n "$subnet" ]]; then
    iptables -t nat -D POSTROUTING -s "$subnet" -o "$VPN_IF" -j MASQUERADE 2>/dev/null || true
  fi
}

up() {
  need_root
  check_inputs
  local subnet
  subnet=$(hotspot_subnet)

  sysctl -w \
    net.ipv4.ip_forward=1 \
    net.ipv4.conf.all.rp_filter=0 \
    "net.ipv4.conf.${HOTSPOT_IF}.rp_filter=0" \
    "net.ipv4.conf.${VPN_IF}.rp_filter=0" >/dev/null

  ip rule del from "$subnet" table "$ROUTE_TABLE" priority "$RULE_PRIO" 2>/dev/null || true
  ip rule add from "$subnet" table "$ROUTE_TABLE" priority "$RULE_PRIO"

  iptables_enable_rules "$subnet"

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --direct --remove-rule ipv4 filter FORWARD 0 -i "$HOTSPOT_IF" -o "$VPN_IF" -j ACCEPT 2>/dev/null || true
    firewall-cmd --direct --remove-rule ipv4 filter FORWARD 0 -i "$VPN_IF" -o "$HOTSPOT_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    firewall-cmd --direct --remove-rule ipv4 nat POSTROUTING 0 -s "$subnet" -o "$VPN_IF" -j MASQUERADE 2>/dev/null || true
    firewall-cmd --direct --add-rule ipv4 filter FORWARD 0 -i "$HOTSPOT_IF" -o "$VPN_IF" -j ACCEPT
    firewall-cmd --direct --add-rule ipv4 filter FORWARD 0 -i "$VPN_IF" -o "$HOTSPOT_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s "$subnet" -o "$VPN_IF" -j MASQUERADE
  fi

  nft delete table inet "$NFT_TABLE" 2>/dev/null || true
  nft -f - <<EOF_NFT
table inet $NFT_TABLE {
  chain forward_chain {
    type filter hook forward priority -5; policy accept;
    iifname "$HOTSPOT_IF" oifname "$VPN_IF" tcp flags syn tcp option maxseg size set rt mtu counter accept
    iifname "$HOTSPOT_IF" oifname "$VPN_IF" counter accept
    iifname "$VPN_IF" oifname "$HOTSPOT_IF" ct state established,related counter accept
  }

  chain postrouting_chain {
    type nat hook postrouting priority srcnat; policy accept;
    ip saddr $subnet oifname "$VPN_IF" counter masquerade
  }
}
EOF_NFT

  echo "hotspot_vpn=up"
  status
}

down() {
  need_root
  local subnet
  subnet=$(hotspot_subnet || true)
  if [[ -n "$subnet" ]]; then
    ip rule del from "$subnet" table "$ROUTE_TABLE" priority "$RULE_PRIO" 2>/dev/null || true
  fi
  iptables_disable_rules "$subnet"

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --direct --remove-rule ipv4 filter FORWARD 0 -i "$HOTSPOT_IF" -o "$VPN_IF" -j ACCEPT 2>/dev/null || true
    firewall-cmd --direct --remove-rule ipv4 filter FORWARD 0 -i "$VPN_IF" -o "$HOTSPOT_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    if [[ -n "$subnet" ]]; then
      firewall-cmd --direct --remove-rule ipv4 nat POSTROUTING 0 -s "$subnet" -o "$VPN_IF" -j MASQUERADE 2>/dev/null || true
    fi
  fi
  nft delete table inet "$NFT_TABLE" 2>/dev/null || true
  echo "hotspot_vpn=down"
}

status() {
  check_inputs
  local subnet client_ip
  subnet=$(hotspot_subnet)
  client_ip=$(ip -4 neigh show dev "$HOTSPOT_IF" | awk '/lladdr/ {print $1; exit}' || true)

  echo "hotspot_if=$HOTSPOT_IF"
  echo "vpn_if=$VPN_IF"
  echo "hotspot_subnet=$subnet"
  echo "route_table=$ROUTE_TABLE"
  echo "rule_prio=$RULE_PRIO"
  echo "nft_table=$NFT_TABLE"
  ip rule show | grep -F "lookup $ROUTE_TABLE" || true
  ip route show table "$ROUTE_TABLE" | head -20 || true
  nft -a list table inet "$NFT_TABLE" 2>/dev/null || true
  iptables -L FORWARD -v -n 2>/dev/null | sed -n '1,80p' || true
  iptables -t nat -L POSTROUTING -v -n 2>/dev/null | sed -n '1,80p' || true
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    echo "firewalld_direct_rules:"
    firewall-cmd --direct --get-all-rules | grep -E "($HOTSPOT_IF|$VPN_IF)" || true
  fi
  iw dev "$HOTSPOT_IF" info 2>/dev/null | grep -E 'ssid|type|channel' || true
  iw dev "$HOTSPOT_IF" station dump 2>/dev/null | sed -E 's/Station ([0-9a-f:]{17})/Station <MAC>/Ig' | head -80 || true
  if [[ -n "$client_ip" ]]; then
    echo "client_seen=yes"
    ip route get 1.1.1.1 from "$client_ip" iif "$HOTSPOT_IF" || true
  else
    echo "client_seen=no"
  fi
}

case "$ACTION" in
  up) up ;;
  down) down ;;
  status) status ;;
  *)
    echo "usage: $0 {up|down|status}" >&2
    exit 2
    ;;
esac
