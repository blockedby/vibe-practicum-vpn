#!/usr/bin/env bash
set -euo pipefail

PHONE_TS_IP="${PHONE_TS_IP:-100.109.247.47}"
REDIRECT_PORT="${REDIRECT_PORT:-2081}"
SSH_HOST="${SSH_HOST:-vibe-practicum}"
: "${VIBE_PRACTICUM_SUDO_PASSWORD:?Set VIBE_PRACTICUM_SUDO_PASSWORD}"

ssh "$SSH_HOST" "PHONE_TS_IP='$PHONE_TS_IP' REDIRECT_PORT='$REDIRECT_PORT' VIBE_PRACTICUM_SUDO_PASSWORD='$VIBE_PRACTICUM_SUDO_PASSWORD' bash -s" <<'REMOTE'
set -euo pipefail
sudo_cmd() { printf '%s
' "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S "$@"; }

# Ensure router is running before interception.
sudo_cmd systemctl is-active --quiet sing-box-vibe-router

# Avoid duplicates.
if sudo_cmd iptables -t nat -C PREROUTING -i tailscale0 -s "$PHONE_TS_IP" -p tcp -m addrtype ! --dst-type LOCAL -m comment --comment vibe-router-pixel-canary -j REDIRECT --to-ports "$REDIRECT_PORT" 2>/dev/null; then
  echo "canary rule already present for $PHONE_TS_IP"
else
  sudo_cmd iptables -t nat -A PREROUTING -i tailscale0 -s "$PHONE_TS_IP" -p tcp -m addrtype ! --dst-type LOCAL -m comment --comment vibe-router-pixel-canary -j REDIRECT --to-ports "$REDIRECT_PORT"
  echo "enabled TCP canary redirect for $PHONE_TS_IP -> local :$REDIRECT_PORT"
fi

sudo_cmd iptables -t nat -S PREROUTING | grep vibe-router || true
REMOTE
