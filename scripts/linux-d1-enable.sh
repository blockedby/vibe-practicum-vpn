#!/usr/bin/env bash
set -euo pipefail

CONFIG_SRC="${CONFIG_SRC:-configs/sing-box/local/kcnc-pc-tun.json}"
CONFIG_DST="${CONFIG_DST:-/etc/sing-box-vibe/kcnc-pc-tun.json}"
SERVICE="${SERVICE:-sing-box-vibe-local.service}"
LOCAL_ENDPOINTS_FILE="${LOCAL_ENDPOINTS_FILE:-config/private-endpoints.local.env}"
if [[ -r "$LOCAL_ENDPOINTS_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$LOCAL_ENDPOINTS_FILE"
  set +a
fi
VPS_TS_IP="${VPNKIT_VPS_TAILNET_IP:-${VPS_TS_IP:-}}"
if [[ -z "$VPS_TS_IP" ]]; then
  echo "Set VPNKIT_VPS_TAILNET_IP in config/private-endpoints.local.env or export VPS_TS_IP." >&2
  exit 2
fi

if ! command -v sing-box >/dev/null 2>&1; then
  echo "sing-box is not installed locally. Install it first, then rerun." >&2
  echo "See docs/LOCAL_SING_BOX_D1.md" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_SRC" ]]; then
  echo "missing config: $CONFIG_SRC" >&2
  exit 1
fi

# Keep the operator-approved Tailscale mode: global exit-node stays enabled.
# Local Steam/Dota direct is handled by sing-box local-direct bound to the LAN
# interface in configs/sing-box/local/kcnc-pc-tun.json.
sudo tailscale up --exit-node="$VPS_TS_IP" --exit-node-allow-lan-access=true --accept-routes

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
