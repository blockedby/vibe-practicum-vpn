#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="/home/kcnc/code/tools/${VPNKIT_VPS_SSH_HOST:-example-vps-host}-vpn"
if [[ "${KCNC_ALLOW_UNSAFE_TUN:-}" != "1" ]]; then
  echo "Refusing to run: this TUN attempt is currently marked unsafe after postmortem." >&2
  echo "Use /home/kcnc/code/tools/${VPNKIT_VPS_SSH_HOST:-example-vps-host}-vpn/scripts/kcnc-safe-tun-disable.sh to rollback/cleanup." >&2
  echo "Set KCNC_ALLOW_UNSAFE_TUN=1 only for deliberate debugging." >&2
  exit 2
fi
CONFIG_SRC="$REPO_DIR/configs/sing-box/local/kcnc-pc-safe-tun.json"
CONFIG_DST="/etc/sing-box-vibe/kcnc-pc-safe-tun.json"
SERVICE="sing-box-vibe-kcnc-safe-tun.service"
VPS_SOCKS_PORT="2080"
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
  echo "sing-box is not installed" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_SRC" ]]; then
  echo "missing config: $CONFIG_SRC" >&2
  exit 1
fi

echo "[1/7] Stop old local sing-box service if present"
sudo systemctl disable --now sing-box-vibe-local.service 2>/dev/null || true
sudo ip link delete vibe-tun0 2>/dev/null || true

echo "[2/7] Start Tailscale as mesh only, explicitly without exit-node"
sudo tailscale up --accept-routes=false --exit-node= --exit-node-allow-lan-access=false --accept-dns=false --operator=kcnc

echo "[3/7] Verify route to VPS tailnet IP"
ip route get "$VPS_TS_IP"

echo "[4/7] Verify VPS SOCKS reachability over Tailscale"
timeout 5 bash -lc "</dev/tcp/$VPS_TS_IP/$VPS_SOCKS_PORT" || {
  echo "Cannot connect to $VPS_TS_IP:$VPS_SOCKS_PORT" >&2
  echo "Rollback: /home/kcnc/code/tools/${VPNKIT_VPS_SSH_HOST:-example-vps-host}-vpn/scripts/kcnc-safe-tun-disable.sh" >&2
  exit 1
}

echo "[5/7] Install and check sing-box config"
sudo install -d -m 755 "$(dirname "$CONFIG_DST")"
sudo install -m 644 "$CONFIG_SRC" "$CONFIG_DST"
sudo sing-box check -c "$CONFIG_DST"

echo "[6/7] Install systemd service"
sudo tee "/etc/systemd/system/$SERVICE" >/dev/null <<EOF_SERVICE
[Unit]
Description=sing-box kcnc-pc safe local TUN router
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

echo "[7/7] Quick status"
ip -4 route show table main | sed -n '1,20p'
ip rule show | sed -n '1,30p'
echo "Enabled. Disable with: /home/kcnc/code/tools/${VPNKIT_VPS_SSH_HOST:-example-vps-host}-vpn/scripts/kcnc-safe-tun-disable.sh"
