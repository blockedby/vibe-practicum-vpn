#!/usr/bin/env bash
set -euo pipefail

SSH_HOST="${SSH_HOST:-vibe-practicum}"
PHONE_TS_IP="${PHONE_TS_IP:-100.109.247.47}"
MARK="${MARK:-0x1}"
TABLE="${TABLE:-100}"

ssh "$SSH_HOST" "PHONE_TS_IP='$PHONE_TS_IP' MARK='$MARK' TABLE='$TABLE' bash -s" <<'REMOTE'
set -euo pipefail

section() { printf '\n=== %s ===\n' "$1"; }

section host
hostname
uptime

section services
for svc in tailscaled xray sing-box-vibe-router; do
  printf '%-24s %s\n' "$svc" "$(systemctl is-active "$svc" 2>/dev/null || true)"
done

section tailscale
tailscale status | sed -n '1,12p' || true

section listeners
ss -lntup | grep -E '(:10808|:2080|:2082|:41641|:22 )' || true

section tproxy-rules
if sudo -n true 2>/dev/null; then
  sudo iptables -t mangle -S PREROUTING | grep vibe-router || true
  sudo iptables -t mangle -S VIBE_ROUTER_PIXEL 2>/dev/null || true
else
  echo 'sudo without password unavailable; skipping iptables details'
fi

section policy-routing
ip rule show | grep -E "fwmark $MARK|lookup $TABLE" || true
ip route show table "$TABLE" 2>/dev/null || true

section canary-summary
if sudo -n iptables -t mangle -C PREROUTING -i tailscale0 -s "$PHONE_TS_IP" -m comment --comment vibe-router-pixel-tproxy-entry -j VIBE_ROUTER_PIXEL 2>/dev/null; then
  echo "pixel canary: ENABLED for $PHONE_TS_IP"
else
  echo "pixel canary: disabled/not found for $PHONE_TS_IP"
fi
REMOTE
