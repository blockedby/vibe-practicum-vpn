#!/usr/bin/env bash
set -euo pipefail

OVPN_CIDR=${OVPN_CIDR:-10.89.0.0/24}
TPROXY_PORT=${TPROXY_PORT:-2082}
MARK=${TPROXY_MARK:-0x1}
TABLE=${TPROXY_TABLE:-100}

sysctl -w net.ipv4.ip_forward=1 >/dev/null || true
sysctl -w net.ipv4.conf.all.src_valid_mark=1 >/dev/null || true
sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null || true
sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null || true

if ! ip rule show | grep -q "fwmark $MARK lookup $TABLE"; then
  ip rule add fwmark "$MARK" table "$TABLE"
fi
ip route replace local default dev lo table "$TABLE"

iptables -t mangle -N OVPN_TO_SINGBOX 2>/dev/null || true
iptables -t mangle -F OVPN_TO_SINGBOX
iptables -t mangle -C PREROUTING -i tun0 -s "$OVPN_CIDR" -j OVPN_TO_SINGBOX 2>/dev/null \
  || iptables -t mangle -A PREROUTING -i tun0 -s "$OVPN_CIDR" -j OVPN_TO_SINGBOX
iptables -t mangle -A OVPN_TO_SINGBOX -p tcp -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK"/"$MARK"
iptables -t mangle -A OVPN_TO_SINGBOX -p udp -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK"/"$MARK"

ip rule show
ip route show table "$TABLE"
iptables -t mangle -L OVPN_TO_SINGBOX -v -n -x
