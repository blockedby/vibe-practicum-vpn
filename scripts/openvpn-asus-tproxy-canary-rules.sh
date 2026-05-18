#!/usr/bin/env bash
set -euo pipefail

SSH_HOST="${SSH_HOST:-vibe-practicum}"
APPLY_LIVE=0
if [[ "${1:-}" == "--apply-live" ]]; then
  APPLY_LIVE=1
fi

cat <<'PLAN'
OpenVPN ASUS TPROXY canary rules

This applies the scoped live fix for:
  CN: asus-tproxy
  IP: 10.89.0.3
  ingress: tun-asus
  TPROXY port: 2082
  mark/table: 0x1/table100

It does not restart tailscaled, sing-box, xray, or OpenVPN.
It only adds idempotent iptables rules for the asus-tproxy canary.
PLAN

if [[ "$APPLY_LIVE" != "1" ]]; then
  echo
  echo "Dry run only. Use: $0 --apply-live"
  exit 0
fi

ssh "$SSH_HOST" 'sudo bash -s' <<'REMOTE'
set -euo pipefail
OPENVPN_DEV="${OPENVPN_DEV:-tun-asus}"
ASUS_TPROXY_IP="${ASUS_TPROXY_IP:-10.89.0.3}"
TPROXY_PORT="${TPROXY_PORT:-2082}"
MARK="${MARK:-0x1}"
TABLE="${TABLE:-100}"
CHAIN="${ASUS_TPROXY_CHAIN:-VIBE_OVPN_ASUS_TP}"
COMMENT_PREFIX="vibe-vpn-openvpn-asus:"
PREROUTING_COMMENT="${COMMENT_PREFIX}tproxy-profile:asus-tproxy"
INPUT_COMMENT="${COMMENT_PREFIX}tproxy-input-accept:asus-tproxy"

ensure_mangle_rule() {
  if ! iptables -t mangle -C "$@" 2>/dev/null; then
    iptables -t mangle -A "$@"
  fi
}

if ! ip rule show | grep -Eq "fwmark ${MARK}(/${MARK})?.*(lookup|table) ${TABLE}(\\b|$)"; then
  ip rule add fwmark "$MARK" table "$TABLE"
fi
if ! ip route show table "$TABLE" | grep -Eq '^local (default|0\.0\.0\.0/0)'; then
  ip route add local 0.0.0.0/0 dev lo table "$TABLE"
fi

iptables -t mangle -N "$CHAIN" 2>/dev/null || true

# Proofix work VPN is itself OpenVPN over UDP/1194. If it is captured into
# sing-box/xray TPROXY, the nested VPN handshake can fail. Keep this scoped
# bypass before the generic UDP TPROXY rule so it is routed/NATed directly.
PROOFIX_OPENVPN_DST="${PROOFIX_OPENVPN_DST:-185.241.192.190}"
PROOFIX_OPENVPN_PORT="${PROOFIX_OPENVPN_PORT:-1194}"
PROOFIX_OPENVPN_COMMENT="${COMMENT_PREFIX}tproxy:bypass:proofix-openvpn-udp1194:${CHAIN}"
if ! iptables -t mangle -C "$CHAIN" -p udp -d "$PROOFIX_OPENVPN_DST/32" --dport "$PROOFIX_OPENVPN_PORT" -m comment --comment "$PROOFIX_OPENVPN_COMMENT" -j RETURN 2>/dev/null; then
  iptables -t mangle -I "$CHAIN" 1 -p udp -d "$PROOFIX_OPENVPN_DST/32" --dport "$PROOFIX_OPENVPN_PORT" -m comment --comment "$PROOFIX_OPENVPN_COMMENT" -j RETURN
fi
# The dynamic-pool packet returns from VIBE_OVPN_ASUS_TP and then continues
# through PREROUTING, where the broad OpenVPN-ASUS chain can catch it again.
# If that chain exists, bypass Proofix there too.
BROAD_CHAIN="VIBE_ROUTER_OPENVPN_ASUS"
BROAD_COMMENT="${COMMENT_PREFIX}tproxy:bypass:proofix-openvpn-udp1194:${BROAD_CHAIN}"
if iptables -t mangle -L "$BROAD_CHAIN" >/dev/null 2>&1; then
  if ! iptables -t mangle -C "$BROAD_CHAIN" -p udp -d "$PROOFIX_OPENVPN_DST/32" --dport "$PROOFIX_OPENVPN_PORT" -m comment --comment "$BROAD_COMMENT" -j RETURN 2>/dev/null; then
    iptables -t mangle -I "$BROAD_CHAIN" 1 -p udp -d "$PROOFIX_OPENVPN_DST/32" --dport "$PROOFIX_OPENVPN_PORT" -m comment --comment "$BROAD_COMMENT" -j RETURN
  fi
fi

for cidr in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
  ensure_mangle_rule "$CHAIN" -d "$cidr" -m comment --comment "${COMMENT_PREFIX}tproxy:bypass:${cidr}" -j RETURN
done
ensure_mangle_rule "$CHAIN" -p tcp -m comment --comment "${COMMENT_PREFIX}tproxy:tcp:asus-tproxy" -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK/$MARK"
ensure_mangle_rule "$CHAIN" -p udp -m comment --comment "${COMMENT_PREFIX}tproxy:udp:asus-tproxy" -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK/$MARK"

if ! iptables -t mangle -C PREROUTING -i "$OPENVPN_DEV" -s "$ASUS_TPROXY_IP/32" -m comment --comment "$PREROUTING_COMMENT" -j "$CHAIN" 2>/dev/null; then
  iptables -t mangle -I PREROUTING 1 -i "$OPENVPN_DEV" -s "$ASUS_TPROXY_IP/32" -m comment --comment "$PREROUTING_COMMENT" -j "$CHAIN"
fi
if ! iptables -t filter -C INPUT -i "$OPENVPN_DEV" -s "$ASUS_TPROXY_IP/32" -m mark --mark "$MARK/$MARK" -m comment --comment "$INPUT_COMMENT" -j ACCEPT 2>/dev/null; then
  iptables -t filter -I INPUT 1 -i "$OPENVPN_DEV" -s "$ASUS_TPROXY_IP/32" -m mark --mark "$MARK/$MARK" -m comment --comment "$INPUT_COMMENT" -j ACCEPT
fi

iptables -t mangle -L PREROUTING -v -n -x --line-numbers | grep asus-tproxy || true
iptables -t mangle -L "$CHAIN" -v -n -x --line-numbers
iptables -t filter -L INPUT -v -n -x --line-numbers | grep tproxy-input-accept || true
REMOTE
