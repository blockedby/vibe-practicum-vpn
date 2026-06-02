#!/usr/bin/env bash
set -euo pipefail

PHONE_TS_IP="${PHONE_TS_IP:?Set PHONE_TS_IP, for example from config/private-endpoints.local.env}"
TPROXY_PORT="${TPROXY_PORT:-2082}"
MARK="${MARK:-0x1}"
TABLE="${TABLE:-100}"
SSH_HOST="${SSH_HOST:-${VPNKIT_VPS_SSH_HOST:-example-vps-host}}"
: "${VIBE_PRACTICUM_SUDO_PASSWORD:?Set VIBE_PRACTICUM_SUDO_PASSWORD}"

ssh "$SSH_HOST" "PHONE_TS_IP='$PHONE_TS_IP' TPROXY_PORT='$TPROXY_PORT' MARK='$MARK' TABLE='$TABLE' VIBE_PRACTICUM_SUDO_PASSWORD='$VIBE_PRACTICUM_SUDO_PASSWORD' bash -s" <<'REMOTE'
set -euo pipefail
sudo_cmd() { printf '%s
' "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S "$@"; }

sudo_cmd systemctl is-active --quiet sing-box-vibe-router

# Policy route for TPROXY-marked packets to local socket.
if ! ip rule show | grep -q "fwmark $MARK .* lookup $TABLE"; then
  sudo_cmd ip rule add fwmark "$MARK" table "$TABLE"
fi
if ! ip route show table "$TABLE" | grep -q '^local 0.0.0.0/0'; then
  sudo_cmd ip route add local 0.0.0.0/0 dev lo table "$TABLE"
fi

# Dedicated mangle chain. Flush to make script idempotent.
sudo_cmd iptables -t mangle -N VIBE_ROUTER_PIXEL 2>/dev/null || true
sudo_cmd iptables -t mangle -F VIBE_ROUTER_PIXEL

# Bypass management/private ranges before proxying.
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

# DNS, TCP and UDP all go to sing-box TProxy.
sudo_cmd iptables -t mangle -A VIBE_ROUTER_PIXEL -p tcp -m comment --comment vibe-router-pixel-tproxy -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK/$MARK"
sudo_cmd iptables -t mangle -A VIBE_ROUTER_PIXEL -p udp -m comment --comment vibe-router-pixel-tproxy -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK/$MARK"

# Attach only one phone source on tailscale0.
if ! sudo_cmd iptables -t mangle -C PREROUTING -i tailscale0 -s "$PHONE_TS_IP" -m comment --comment vibe-router-pixel-tproxy-entry -j VIBE_ROUTER_PIXEL 2>/dev/null; then
  sudo_cmd iptables -t mangle -A PREROUTING -i tailscale0 -s "$PHONE_TS_IP" -m comment --comment vibe-router-pixel-tproxy-entry -j VIBE_ROUTER_PIXEL
fi

echo "enabled full TCP+UDP TProxy canary for $PHONE_TS_IP -> :$TPROXY_PORT"
sudo_cmd iptables -t mangle -S PREROUTING | grep vibe-router || true
sudo_cmd iptables -t mangle -S VIBE_ROUTER_PIXEL | sed -n '1,80p'
ip rule show | grep "fwmark $MARK" || true
ip route show table "$TABLE" || true
REMOTE
