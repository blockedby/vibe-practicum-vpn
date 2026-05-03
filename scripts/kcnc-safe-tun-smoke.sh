#!/usr/bin/env bash
set -euo pipefail

VPS_TS_IP="100.121.107.112"
SERVICE="sing-box-vibe-kcnc-safe-tun.service"

echo "=== service ==="
systemctl is-active "$SERVICE" || true

echo "=== tailscale ==="
tailscale status 2>&1 | sed -n '1,25p' || true

echo "=== routes ==="
echo "default:"; ip route get 1.1.1.1 || true
echo "vps tailnet:"; ip route get "$VPS_TS_IP" || true
echo "dota sample:"; ip route get 155.133.238.194 || true

echo "=== dns ==="
dig +time=2 +tries=1 google.com A | grep -E 'status:|SERVER:|Query time' || true
dig +time=2 +tries=1 ya.ru A | grep -E 'status:|SERVER:|Query time' || true

echo "=== public ip ==="
python3 - <<'PY'
import urllib.request
for url in ['https://ifconfig.me', 'https://api.ipify.org']:
    try:
        print(url, urllib.request.urlopen(url, timeout=8).read().decode()[:200])
    except Exception as e:
        print(url, 'ERR', e)
PY

echo "=== logs recent ==="
journalctl -u "$SERVICE" --since '2 minutes ago' --no-pager | tail -80 || true
