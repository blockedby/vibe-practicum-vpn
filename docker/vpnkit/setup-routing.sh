#!/usr/bin/env bash
set -euo pipefail

OVPN_CIDR=${OVPN_CIDR:-10.89.0.0/24}
VPNKIT_ROUTING_MODE=${VPNKIT_ROUTING_MODE:-redirect}
TPROXY_PORT=${TPROXY_PORT:-2082}
DNS_REDIRECT_PORT=${DNS_REDIRECT_PORT:-5353}
MARK=${TPROXY_MARK:-0x1}
TABLE=${TPROXY_TABLE:-100}
TUN_IFACE=${SINGBOX_TUN_IFACE:-sb-tun0}
TUN_PEER=${SINGBOX_TUN_PEER:-172.19.0.2}
TUN_TABLE=${SINGBOX_TUN_TABLE:-101}

sysctl -w net.ipv4.ip_forward=1 >/dev/null || true
sysctl -w net.ipv4.conf.all.src_valid_mark=1 >/dev/null || true
sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null || true
sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null || true
sysctl -w net.ipv4.conf.tun0.src_valid_mark=1 >/dev/null || true
sysctl -w net.ipv4.conf.tun0.rp_filter=0 >/dev/null || true

case "$VPNKIT_ROUTING_MODE" in
  tproxy)
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
    # Scoped local-delivery accept for marked TPROXY packets. This is not broad NAT;
    # it only prevents restrictive filter policies from dropping packets already
    # selected for local transparent proxy delivery.
    iptables -C INPUT -i tun0 -s "$OVPN_CIDR" -m mark --mark "$MARK" -m comment --comment "vpnkit:tproxy-input-accept" -j ACCEPT 2>/dev/null \
      || iptables -I INPUT 1 -i tun0 -s "$OVPN_CIDR" -m mark --mark "$MARK" -m comment --comment "vpnkit:tproxy-input-accept" -j ACCEPT

    ip rule show
    ip route show table "$TABLE"
    iptables -t mangle -L OVPN_TO_SINGBOX -v -n -x
    iptables -L INPUT -v -n -x | sed -n '1,12p'
    ;;
  tun)
    until ip link show "$TUN_IFACE" >/dev/null 2>&1; do
      sleep 0.2
    done
    ip route replace default via "$TUN_PEER" dev "$TUN_IFACE" table "$TUN_TABLE"
    if ! ip rule show | grep -q "from $OVPN_CIDR lookup $TUN_TABLE"; then
      ip rule add from "$OVPN_CIDR" table "$TUN_TABLE" priority 1000
    fi
    ip rule show
    ip route show table "$TUN_TABLE"
    ip -s link show "$TUN_IFACE"
    ;;
  redirect)
    iptables -t nat -N OVPN_REDIRECT_TO_SINGBOX 2>/dev/null || true
    iptables -t nat -F OVPN_REDIRECT_TO_SINGBOX
    iptables -t nat -C PREROUTING -i tun0 -s "$OVPN_CIDR" -j OVPN_REDIRECT_TO_SINGBOX 2>/dev/null \
      || iptables -t nat -A PREROUTING -i tun0 -s "$OVPN_CIDR" -j OVPN_REDIRECT_TO_SINGBOX
    iptables -t nat -A OVPN_REDIRECT_TO_SINGBOX -p tcp -j REDIRECT --to-ports "$TPROXY_PORT"
    iptables -t nat -A OVPN_REDIRECT_TO_SINGBOX -p udp --dport 53 -j REDIRECT --to-ports "$DNS_REDIRECT_PORT"
    iptables -t nat -L OVPN_REDIRECT_TO_SINGBOX -v -n -x
    ;;
  *)
    echo "unsupported VPNKIT_ROUTING_MODE=$VPNKIT_ROUTING_MODE (expected redirect, tun, or tproxy)" >&2
    exit 2
    ;;
esac
