#!/usr/bin/env bash
set -euo pipefail

SERVICE="sing-box-vibe-kcnc-safe-tun.service"

echo "[1/4] Stop safe local sing-box"
sudo systemctl disable --now "$SERVICE" 2>/dev/null || true
sudo systemctl reset-failed "$SERVICE" 2>/dev/null || true

echo "[2/4] Remove TUN interface if left behind"
sudo ip link delete vibe-tun0 2>/dev/null || true

echo "[3/4] Keep Tailscale mesh only, no exit-node"
if systemctl is-active --quiet tailscaled; then
  sudo tailscale up --accept-routes=false --exit-node= --exit-node-allow-lan-access=false --accept-dns=false --operator=kcnc || true
fi

echo "[4/4] Status"
ip -4 route show table main | sed -n '1,20p'
ip route show table 52 2>/dev/null || true
systemctl is-active v2raya 2>/dev/null || true
ps -eo pid,comm,args | grep -Ei 'v2ray|v2raya' | grep -v grep || true

echo "Disabled. V2RayA was not touched."
