#!/usr/bin/env bash
set -u -o pipefail

REPO_DIR="/home/kcnc/code/tools/${VPNKIT_VPS_SSH_HOST:-example-vps-host}-vpn"
CONFIG_SRC="$REPO_DIR/configs/sing-box/local/kcnc-pc-safe-tun.json"
CONFIG_DST="/etc/sing-box-vibe/kcnc-pc-safe-tun.json"
SERVICE="sing-box-vibe-kcnc-oneshot.service"
SNAP_DIR="$REPO_DIR/snapshots/kcnc-oneshot"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="$SNAP_DIR/start-$TS.log"
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

STOP_V2RAYA="${KCNC_STOP_V2RAYA:-0}"

mkdir -p "$SNAP_DIR"
exec > >(tee -a "$LOG") 2>&1

STEP_FAILED=0

run() {
  echo
  echo "### $*"
  "$@"
  local rc=$?
  echo "### rc=$rc: $*"
  return "$rc"
}

try() {
  run "$@" || STEP_FAILED=1
}

snapshot() {
  local name="$1"
  local file="$SNAP_DIR/$name-$TS.txt"
  {
    echo "=== snapshot $name $TS ==="
    echo "=== services ==="
    systemctl is-active tailscaled 2>&1 || true
    systemctl is-active "$SERVICE" 2>&1 || true
    systemctl is-active sing-box-vibe-local.service 2>&1 || true
    systemctl is-active v2raya 2>&1 || true
    echo "=== processes ==="
    ps -eo pid,comm,args | grep -Ei 'v2ray|v2raya|sing-box|tailscale' | grep -v grep || true
    echo "=== tailscale status ==="
    tailscale status 2>&1 || true
    echo "=== tailscale prefs ==="
    tailscale debug prefs 2>&1 || true
    echo "=== routes main ==="
    ip -4 route show table main 2>&1 || true
    echo "=== routes 52 ==="
    ip -4 route show table 52 2>&1 || true
    echo "=== routes 2022 ==="
    ip -4 route show table 2022 2>&1 || true
    echo "=== rules ==="
    ip rule show 2>&1 || true
    echo "=== interfaces ==="
    ip -br addr 2>&1 || true
    echo "=== dns/resolved ==="
    readlink -f /etc/resolv.conf 2>&1 || true
    resolvectl status 2>&1 | sed -n '1,160p' || true
    echo "=== listeners ==="
    ss -lntup 2>/dev/null | grep -Ei 'v2ray|v2raya|sing|10808|2080|2081|2082|2017|20170|789|1080' || true
    echo "=== journal oneshot ==="
    journalctl -u "$SERVICE" --since '30 minutes ago' --no-pager 2>&1 || true
  } > "$file"
  echo "snapshot saved: $file"
}

on_exit() {
  local rc=$?
  echo
  echo "### final snapshot"
  snapshot "final"
  echo "log saved: $LOG"
  echo "rollback: sudo /home/kcnc/code/tools/${VPNKIT_VPS_SSH_HOST:-example-vps-host}-vpn/scripts/kcnc-oneshot-stop.sh"
  if [[ "$STEP_FAILED" != 0 || "$rc" != 0 ]]; then
    echo "RESULT: FAIL rc=$rc STEP_FAILED=$STEP_FAILED"
  else
    echo "RESULT: STARTED_AND_TESTED"
  fi
}
trap on_exit EXIT

probe() {
  local label="$1"; shift
  echo
  echo "--- PROBE: $label"
  timeout 20 "$@"
  local rc=$?
  echo "--- PROBE rc=$rc: $label"
  return "$rc"
}

http_probe() {
  local label="$1" url="$2"
  probe "$label" python3 - "$url" <<'PY'
import sys, urllib.request
url=sys.argv[1]
try:
    req=urllib.request.Request(url, headers={"User-Agent":"kcnc-oneshot/1"})
    with urllib.request.urlopen(req, timeout=12) as r:
        body=r.read(300).decode('utf-8','replace').replace('\n',' ')[:300]
        print('status', r.status, 'url', r.geturl(), 'body', body)
except Exception as e:
    print('ERR', repr(e))
    sys.exit(1)
PY
}

curl_socks_probe() {
  local label="$1" url="$2"
  echo
  echo "--- PROBE: $label"
  timeout 20 curl -4 -sS --max-time 15 --socks5-hostname "$VPS_TS_IP:$VPS_SOCKS_PORT" "$url" | head -c 500
  local rc=${PIPESTATUS[0]}
  echo
  echo "--- PROBE rc=$rc: $label"
  return "$rc"
}

echo "START log: $LOG"
snapshot "before"

if [[ ! -f "$CONFIG_SRC" ]]; then
  echo "missing config: $CONFIG_SRC" >&2
  exit 10
fi
if ! command -v sing-box >/dev/null 2>&1; then
  echo "sing-box missing" >&2
  exit 11
fi

if [[ "$STOP_V2RAYA" == "1" ]]; then
  echo
  echo "### stopping V2RayA workaround for clean test (explicitly requested)"
  sudo systemctl stop v2raya 2>/dev/null || true
  sudo pkill -f '^v2raya$' 2>/dev/null || true
  sudo pkill -f '/usr/bin/v2ray run --config=/etc/v2raya/config.json' 2>/dev/null || true
else
  echo "### leaving V2RayA untouched (default safety behavior)"
fi

run sudo systemctl disable --now sing-box-vibe-local.service || true
run sudo systemctl disable --now "$SERVICE" || true
run sudo ip link delete vibe-tun0 || true

echo
 echo "### Tailscale mesh only"
try sudo tailscale up --accept-routes=false --exit-node= --exit-node-allow-lan-access=false --accept-dns=false --operator=kcnc

try ip route get "$VPS_TS_IP"
try timeout 5 bash -lc "</dev/tcp/$VPS_TS_IP/$VPS_SOCKS_PORT"
try curl_socks_probe "VPS SOCKS real egress" "https://ifconfig.me"
try curl_socks_probe "VPS SOCKS Telegram API" "https://api.telegram.org"

if [[ "$STEP_FAILED" != 0 ]]; then
  echo "Preflight failed; not starting TUN. See log: $LOG" >&2
  exit 20
fi

echo
 echo "### install/check/start sing-box TUN"
sudo install -d -m 755 "$(dirname "$CONFIG_DST")"
sudo install -m 644 "$CONFIG_SRC" "$CONFIG_DST"
try sudo sing-box check -c "$CONFIG_DST"

sudo tee "/etc/systemd/system/$SERVICE" >/dev/null <<EOF_SERVICE
[Unit]
Description=sing-box kcnc-pc oneshot local TUN router
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

try sudo systemctl daemon-reload
try sudo systemctl enable --now "$SERVICE"
sleep 3
try systemctl is-active "$SERVICE"
snapshot "after-start"

echo
 echo "### post-start probes"
try ip route get 1.1.1.1
try ip route get "$VPS_TS_IP"
try ip route get 155.133.238.194
try dig +time=3 +tries=1 google.com A
try dig +time=3 +tries=1 ya.ru A
try http_probe "public ip ifconfig" "https://ifconfig.me"
try http_probe "public ip ipify" "https://api.ipify.org"
try http_probe "Telegram API" "https://api.telegram.org"
try http_probe "YouTube headers" "https://www.youtube.com/generate_204"
try http_probe "Yandex" "https://ya.ru"
try http_probe "2ip.ru" "https://2ip.ru"

exit "$STEP_FAILED"
