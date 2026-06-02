#!/usr/bin/env bash
set -euo pipefail

PHONE_TS_IP="${PHONE_TS_IP:?Set PHONE_TS_IP, for example from config/private-endpoints.local.env}"
TPROXY_PORT="${TPROXY_PORT:-2082}"
MARK="${MARK:-0x1}"
TABLE="${TABLE:-100}"
SSH_HOST="${SSH_HOST:-${VPNKIT_VPS_SSH_HOST:-example-vps-host}}"
CONFIG="${CONFIG:-/etc/sing-box-vibe/tproxy-canary.json}"
BACKUP="${BACKUP:-/etc/sing-box-vibe/tproxy-canary.json.pre-dns-leak-canary}"
COMMENT_UDP="vibe-router-pixel-dns-canary-udp"
COMMENT_TCP="vibe-router-pixel-dns-canary-tcp"
: "${VIBE_PRACTICUM_SUDO_PASSWORD:?Set VIBE_PRACTICUM_SUDO_PASSWORD}"

ssh "$SSH_HOST" \
  "PHONE_TS_IP='$PHONE_TS_IP' TPROXY_PORT='$TPROXY_PORT' MARK='$MARK' TABLE='$TABLE' CONFIG='$CONFIG' BACKUP='$BACKUP' COMMENT_UDP='$COMMENT_UDP' COMMENT_TCP='$COMMENT_TCP' VIBE_PRACTICUM_SUDO_PASSWORD='$VIBE_PRACTICUM_SUDO_PASSWORD' bash -s" <<'REMOTE'
set -euo pipefail
sudo_cmd() { printf '%s\n' "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S "$@"; }

sudo_cmd systemctl is-active --quiet sing-box-vibe-router

# Policy route for TPROXY-marked packets to local socket.
if ! ip rule show | grep -Eq "fwmark ${MARK}([[:space:]]|/)"; then
  sudo_cmd ip rule add fwmark "$MARK" table "$TABLE"
fi
if ! ip route show table "$TABLE" | grep -Eq '^local (default|0\.0\.0\.0/0)'; then
  sudo_cmd ip route add local 0.0.0.0/0 dev lo table "$TABLE"
fi

# Backup once. Disable script restores this exact file.
if [[ ! -f "$BACKUP" ]]; then
  sudo_cmd cp -a "$CONFIG" "$BACKUP"
fi

# Force sing-box DNS queries through the existing Xray/VLESS SOCKS outbound.
# This is global for sing-box while the canary is enabled, but packet capture below
# remains pixel-only. Rollback restores BACKUP and restarts the service.
tmp="$(mktemp)"
sudo_cmd cp -a "$CONFIG" "$tmp.in"
sudo_cmd chown "$(id -u):$(id -g)" "$tmp.in"
python3 - "$tmp.in" "$tmp" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, 'r', encoding='utf-8') as f:
    data = json.load(f)
for server in data.get('dns', {}).get('servers', []):
    server['detour'] = 'xray-socks-out'
with open(dst, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
sudo_cmd install -m 644 "$tmp" "$CONFIG"
rm -f "$tmp" "$tmp.in"
sudo_cmd sing-box check -c "$CONFIG"
sudo_cmd systemctl restart sing-box-vibe-router
sudo_cmd systemctl is-active --quiet sing-box-vibe-router

# Pixel-only DNS hijack before the shared VIBE_ROUTER_PIXEL jump. This catches
# DNS to 100.100.100.100 too, before the 100.64.0.0/10 management bypass.
for proto_comment in "udp:$COMMENT_UDP" "tcp:$COMMENT_TCP"; do
  proto="${proto_comment%%:*}"
  comment="${proto_comment#*:}"
  if ! sudo_cmd iptables -t mangle -C PREROUTING -i tailscale0 -s "$PHONE_TS_IP" -p "$proto" --dport 53 -m comment --comment "$comment" -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK/$MARK" 2>/dev/null; then
    sudo_cmd iptables -t mangle -I PREROUTING 1 -i tailscale0 -s "$PHONE_TS_IP" -p "$proto" --dport 53 -m comment --comment "$comment" -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK/$MARK"
  fi
done

echo "enabled pixel DNS leak canary for $PHONE_TS_IP"
echo
sudo_cmd iptables -t mangle -S PREROUTING | grep -E 'vibe-router-pixel-dns-canary|vibe-router-pixel-tproxy-entry|vibe-router-kcnc-pc-tproxy-entry' || true
echo
printf 'sing-box DNS servers now have detour tags:\n'
sudo_cmd python3 - "$CONFIG" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
for s in data.get('dns', {}).get('servers', []):
    print(f"- {s.get('tag')}: {s.get('type')} {s.get('server')} detour={s.get('detour')}")
PY
REMOTE
