#!/usr/bin/env bash
set -euo pipefail

SSH_HOST="${SSH_HOST:-${VPNKIT_VPS_SSH_HOST:-example-vps-host}}"
: "${VIBE_PRACTICUM_SUDO_PASSWORD:?Set VIBE_PRACTICUM_SUDO_PASSWORD}"

ssh "$SSH_HOST" "VIBE_PRACTICUM_SUDO_PASSWORD='$VIBE_PRACTICUM_SUDO_PASSWORD' bash -s" <<'REMOTE'
set -euo pipefail
sudo_cmd() { printf '%s
' "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S "$@"; }

pass() { printf 'PASS %-28s %s\n' "$1" "${2:-}"; }
fail() { printf 'FAIL %-28s %s\n' "$1" "${2:-}"; exit_code=1; }
check_service() {
  local svc="$1"
  if systemctl is-active --quiet "$svc"; then pass "service:$svc" active; else fail "service:$svc" inactive; fi
}

exit_code=0

check_service tailscaled
check_service xray
check_service sing-box-vibe-router

if ss -lntup | grep -q ':10808'; then pass 'listener:xray-socks' ':10808'; else fail 'listener:xray-socks' missing; fi
if ss -lntup | grep -q ':2082'; then pass 'listener:sing-tproxy' ':2082'; else fail 'listener:sing-tproxy' missing; fi

# Direct VPS egress.
direct_ip="$(timeout 10 curl -4 -sS https://ifconfig.me 2>/dev/null || true)"
if [ -n "$direct_ip" ]; then pass 'direct-egress-ip' "$direct_ip"; else fail 'direct-egress-ip' empty; fi

# Xray SOCKS egress.
xray_ip="$(timeout 15 curl -4 -sS --socks5-hostname 127.0.0.1:10808 https://ifconfig.me 2>/dev/null || true)"
if [ -n "$xray_ip" ]; then pass 'xray-socks-egress-ip' "$xray_ip"; else fail 'xray-socks-egress-ip' empty; fi

# sing-box test SOCKS egress.
sing_ip="$(timeout 15 curl -4 -sS --socks5-hostname 127.0.0.1:2080 https://ifconfig.me 2>/dev/null || true)"
if [ -n "$sing_ip" ]; then pass 'sing-test-egress-ip' "$sing_ip"; else fail 'sing-test-egress-ip' empty; fi

# Telegram via proxy path.
if timeout 15 curl -sS -I --socks5-hostname 127.0.0.1:2080 https://api.telegram.org/ 2>/dev/null | grep -qE 'HTTP/[0-9.]+ 30[12]'; then
  pass 'telegram-via-sing-socks' 'HTTP redirect OK'
else
  fail 'telegram-via-sing-socks' 'no HTTP 30x'
fi

# Canary rule present?
: "${PHONE_TS_IP:?Set PHONE_TS_IP, for example from config/private-endpoints.local.env}"
if sudo_cmd iptables -t mangle -C PREROUTING -i tailscale0 -s "$PHONE_TS_IP" -m comment --comment vibe-router-pixel-tproxy-entry -j VIBE_ROUTER_PIXEL 2>/dev/null; then
  pass 'pixel-tproxy-canary' enabled
else
  fail 'pixel-tproxy-canary' missing
fi

exit "$exit_code"
REMOTE
