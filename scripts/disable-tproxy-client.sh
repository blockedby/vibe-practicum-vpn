#!/usr/bin/env bash
set -euo pipefail

CLIENT_TS_IP="${CLIENT_TS_IP:?Set CLIENT_TS_IP, e.g. 100.64.19.94}"
CLIENT_NAME="${CLIENT_NAME:-client}"
SSH_HOST="${SSH_HOST:-vibe-practicum}"
: "${VIBE_PRACTICUM_SUDO_PASSWORD:?Set VIBE_PRACTICUM_SUDO_PASSWORD}"

COMMENT="vibe-router-${CLIENT_NAME}-tproxy-entry"

ssh "$SSH_HOST" \
  "CLIENT_TS_IP='$CLIENT_TS_IP' COMMENT='$COMMENT' VIBE_PRACTICUM_SUDO_PASSWORD='$VIBE_PRACTICUM_SUDO_PASSWORD' bash -s" <<'REMOTE'
set -euo pipefail
sudo_cmd() { printf '%s
' "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S "$@"; }

while sudo_cmd iptables -t mangle -C PREROUTING -i tailscale0 -s "$CLIENT_TS_IP" -m comment --comment "$COMMENT" -j VIBE_ROUTER_PIXEL 2>/dev/null; do
  sudo_cmd iptables -t mangle -D PREROUTING -i tailscale0 -s "$CLIENT_TS_IP" -m comment --comment "$COMMENT" -j VIBE_ROUTER_PIXEL
  echo "removed one TProxy entry for $CLIENT_TS_IP"
done

sudo_cmd iptables -t mangle -S PREROUTING | grep vibe-router || true
REMOTE
