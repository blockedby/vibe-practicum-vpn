#!/usr/bin/env bash
set -euo pipefail

PHONE_TS_IP="${PHONE_TS_IP:?Set PHONE_TS_IP, for example from config/private-endpoints.local.env}"
MARK="${MARK:-0x1}"
TABLE="${TABLE:-100}"
SSH_HOST="${SSH_HOST:-${VPNKIT_VPS_SSH_HOST:-example-vps-host}}"
: "${VIBE_PRACTICUM_SUDO_PASSWORD:?Set VIBE_PRACTICUM_SUDO_PASSWORD}"

ssh "$SSH_HOST" "PHONE_TS_IP='$PHONE_TS_IP' MARK='$MARK' TABLE='$TABLE' VIBE_PRACTICUM_SUDO_PASSWORD='$VIBE_PRACTICUM_SUDO_PASSWORD' bash -s" <<'REMOTE'
set -euo pipefail
sudo_cmd() { printf '%s
' "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S "$@"; }

while sudo_cmd iptables -t mangle -C PREROUTING -i tailscale0 -s "$PHONE_TS_IP" -m comment --comment vibe-router-pixel-tproxy-entry -j VIBE_ROUTER_PIXEL 2>/dev/null; do
  sudo_cmd iptables -t mangle -D PREROUTING -i tailscale0 -s "$PHONE_TS_IP" -m comment --comment vibe-router-pixel-tproxy-entry -j VIBE_ROUTER_PIXEL
  echo "removed one tproxy entry rule"
done
sudo_cmd iptables -t mangle -F VIBE_ROUTER_PIXEL 2>/dev/null || true
sudo_cmd iptables -t mangle -X VIBE_ROUTER_PIXEL 2>/dev/null || true

while ip rule show | grep -q "fwmark $MARK .* lookup $TABLE"; do
  sudo_cmd ip rule del fwmark "$MARK" table "$TABLE" || break
  echo "removed ip rule fwmark $MARK table $TABLE"
done
sudo_cmd ip route flush table "$TABLE" 2>/dev/null || true

sudo_cmd iptables -t mangle -S PREROUTING | grep vibe-router || true
ip rule show | grep "fwmark $MARK" || true
ip route show table "$TABLE" || true
REMOTE
