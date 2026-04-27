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

while sudo_cmd iptables -t nat -C PREROUTING -i tailscale0 -s "$PHONE_TS_IP" -p tcp -m addrtype ! --dst-type LOCAL -m comment --comment vibe-router-pixel-canary -j REDIRECT --to-ports "$REDIRECT_PORT" 2>/dev/null; do
  sudo_cmd iptables -t nat -D PREROUTING -i tailscale0 -s "$PHONE_TS_IP" -p tcp -m addrtype ! --dst-type LOCAL -m comment --comment vibe-router-pixel-canary -j REDIRECT --to-ports "$REDIRECT_PORT"
  echo "removed one canary rule"
done

sudo_cmd iptables -t nat -S PREROUTING | grep vibe-router || true
REMOTE
