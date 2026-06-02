#!/usr/bin/env bash
set -euo pipefail

CLIENT_TS_IP="${CLIENT_TS_IP:?Set CLIENT_TS_IP, e.g. 100.64.19.94}"
CLIENT_NAME="${CLIENT_NAME:-client}"
TPROXY_PORT="${TPROXY_PORT:-2082}"
MARK="${MARK:-0x1}"
TABLE="${TABLE:-100}"
SSH_HOST="${SSH_HOST:-${VPNKIT_VPS_SSH_HOST:-example-vps-host}}"
: "${VIBE_PRACTICUM_SUDO_PASSWORD:?Set VIBE_PRACTICUM_SUDO_PASSWORD}"

# Keep iptables comments simple and deterministic.
COMMENT="vibe-router-${CLIENT_NAME}-tproxy-entry"

ssh "$SSH_HOST" \
  "CLIENT_TS_IP='$CLIENT_TS_IP' CLIENT_NAME='$CLIENT_NAME' COMMENT='$COMMENT' TPROXY_PORT='$TPROXY_PORT' MARK='$MARK' TABLE='$TABLE' VIBE_PRACTICUM_SUDO_PASSWORD='$VIBE_PRACTICUM_SUDO_PASSWORD' bash -s" <<'REMOTE'
set -euo pipefail
sudo_cmd() { printf '%s
' "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S "$@"; }

sudo_cmd systemctl is-active --quiet sing-box-vibe-router

# Policy route for TPROXY-marked packets to local socket.
if ! ip rule show | grep -Eq "fwmark ${MARK}( |/)"; then
  sudo_cmd ip rule add fwmark "$MARK" table "$TABLE"
fi
if ! ip route show table "$TABLE" | grep -q '^local 0.0.0.0/0'; then
  sudo_cmd ip route add local 0.0.0.0/0 dev lo table "$TABLE"
fi

# Dedicated shared mangle chain. Do not flush here: multiple clients may use it.
sudo_cmd iptables -t mangle -N VIBE_ROUTER_PIXEL 2>/dev/null || true

# Ensure bypass/TProxy body exists. If the chain is empty, populate it.
if ! sudo_cmd iptables -t mangle -S VIBE_ROUTER_PIXEL | grep -q 'vibe-router-pixel-tproxy'; then
  sudo_cmd iptables -t mangle -F VIBE_ROUTER_PIXEL
  for cidr in \
    0.0.0.0/8 \
    10.0.0.0/8 \
    100.64.0.0/10 \
    127.0.0.0/8 \
    169.254.0.0/16 \
    172.16.0.0/12 \
    192.168.0.0/16 \
    224.0.0.0/4 \
    240.0.0.0/4; do
    sudo_cmd iptables -t mangle -A VIBE_ROUTER_PIXEL -d "$cidr" -m comment --comment vibe-router-pixel-tproxy-bypass -j RETURN
  done
  sudo_cmd iptables -t mangle -A VIBE_ROUTER_PIXEL -p tcp -m comment --comment vibe-router-pixel-tproxy -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK/$MARK"
  sudo_cmd iptables -t mangle -A VIBE_ROUTER_PIXEL -p udp -m comment --comment vibe-router-pixel-tproxy -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK/$MARK"
fi

# Attach this Tailscale source to the shared chain.
if ! sudo_cmd iptables -t mangle -C PREROUTING -i tailscale0 -s "$CLIENT_TS_IP" -m comment --comment "$COMMENT" -j VIBE_ROUTER_PIXEL 2>/dev/null; then
  sudo_cmd iptables -t mangle -A PREROUTING -i tailscale0 -s "$CLIENT_TS_IP" -m comment --comment "$COMMENT" -j VIBE_ROUTER_PIXEL
fi

echo "enabled TCP+UDP TProxy for $CLIENT_NAME ($CLIENT_TS_IP) -> :$TPROXY_PORT"
sudo_cmd iptables -t mangle -S PREROUTING | grep vibe-router || true
ip rule show | grep "fwmark $MARK" || true
ip route show table "$TABLE" || true
REMOTE
