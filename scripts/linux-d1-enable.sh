#!/usr/bin/env bash
set -euo pipefail

CONFIG_SRC="${CONFIG_SRC:-configs/sing-box/local/kcnc-pc-tun.json}"
CONFIG_DST="${CONFIG_DST:-/etc/sing-box-vibe/kcnc-pc-tun.json}"
SERVICE="${SERVICE:-sing-box-vibe-local.service}"
VPS_TS_IP="${VPS_TS_IP:-100.121.107.112}"

if ! command -v sing-box >/dev/null 2>&1; then
  echo "sing-box is not installed locally. Install it first, then rerun." >&2
  echo "See docs/LOCAL_SING_BOX_D1.md" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_SRC" ]]; then
  echo "missing config: $CONFIG_SRC" >&2
  exit 1
fi

# D1 requires Tailscale connected, but NOT as a global exit-node.
# Otherwise Steam local-direct can still be pulled through tailscale0.
sudo tailscale up --accept-routes

echo "Checking VPS SOCKS reachability on $VPS_TS_IP:2080..."
timeout 5 bash -lc "</dev/tcp/$VPS_TS_IP/2080" || {
  echo "Cannot connect to VPS SOCKS $VPS_TS_IP:2080" >&2
  echo "Make sure VPS sing-box tailnet-socks-in is applied." >&2
  exit 1
}

sudo install -d -m 755 "$(dirname "$CONFIG_DST")"
sudo install -m 644 "$CONFIG_SRC" "$CONFIG_DST"
sudo sing-box check -c "$CONFIG_DST"

sudo tee "/etc/systemd/system/$SERVICE" >/dev/null <<EOF_SERVICE
[Unit]
Description=sing-box local TUN router for kcnc-pc D1
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
ExecStart=$(command -v sing-box) run -c $CONFIG_DST
Restart=on-failure
RestartSec=3
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW

[Install]
WantedBy=multi-user.target
EOF_SERVICE

sudo systemctl daemon-reload
sudo systemctl enable --now "$SERVICE"
sleep 2
sudo systemctl is-active "$SERVICE"

echo
curl -4 -sS --max-time 15 https://ifconfig.me || true
echo
