#!/usr/bin/env bash
set -euo pipefail

PHONE_TS_IP="${PHONE_TS_IP:?Set PHONE_TS_IP, for example from config/private-endpoints.local.env}"
SSH_HOST="${SSH_HOST:-${VPNKIT_VPS_SSH_HOST:-example-vps-host}}"
CONFIG="${CONFIG:-/etc/sing-box-vibe/tproxy-canary.json}"
BACKUP="${BACKUP:-/etc/sing-box-vibe/tproxy-canary.json.pre-dns-leak-canary}"
COMMENT_UDP="vibe-router-pixel-dns-canary-udp"
COMMENT_TCP="vibe-router-pixel-dns-canary-tcp"
: "${VIBE_PRACTICUM_SUDO_PASSWORD:?Set VIBE_PRACTICUM_SUDO_PASSWORD}"

ssh "$SSH_HOST" \
  "PHONE_TS_IP='$PHONE_TS_IP' CONFIG='$CONFIG' BACKUP='$BACKUP' COMMENT_UDP='$COMMENT_UDP' COMMENT_TCP='$COMMENT_TCP' VIBE_PRACTICUM_SUDO_PASSWORD='$VIBE_PRACTICUM_SUDO_PASSWORD' bash -s" <<'REMOTE'
set -euo pipefail
sudo_cmd() { printf '%s\n' "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S "$@"; }

# Remove only DNS-canary PREROUTING rules. Keep the normal pixel TProxy canary intact.
for proto_comment in "udp:$COMMENT_UDP" "tcp:$COMMENT_TCP"; do
  proto="${proto_comment%%:*}"
  comment="${proto_comment#*:}"
  while sudo_cmd iptables -t mangle -C PREROUTING -i tailscale0 -s "$PHONE_TS_IP" -p "$proto" --dport 53 -m comment --comment "$comment" -j TPROXY --on-port 2082 --tproxy-mark 0x1/0x1 2>/dev/null; do
    sudo_cmd iptables -t mangle -D PREROUTING -i tailscale0 -s "$PHONE_TS_IP" -p "$proto" --dport 53 -m comment --comment "$comment" -j TPROXY --on-port 2082 --tproxy-mark 0x1/0x1
  done
done

# Restore original sing-box config if the canary backup exists.
if [[ -f "$BACKUP" ]]; then
  sudo_cmd cp -a "$BACKUP" "$CONFIG"
  sudo_cmd sing-box check -c "$CONFIG"
  sudo_cmd systemctl restart sing-box-vibe-router
  sudo_cmd systemctl is-active --quiet sing-box-vibe-router
fi

echo "disabled pixel DNS leak canary for $PHONE_TS_IP"
sudo_cmd iptables -t mangle -S PREROUTING | grep -E 'vibe-router-pixel-dns-canary|vibe-router-pixel-tproxy-entry|vibe-router-kcnc-pc-tproxy-entry' || true
REMOTE
