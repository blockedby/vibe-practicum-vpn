#!/usr/bin/env bash
set -euo pipefail

CLIENT_NAME="${CLIENT_NAME:?Set CLIENT_NAME, e.g. kcnc-pc or kcnc-pc-1}"
TPROXY_PORT="${TPROXY_PORT:-2082}"
MARK="${MARK:-0x1}"
TABLE="${TABLE:-100}"
SSH_HOST="${SSH_HOST:-${VPNKIT_VPS_SSH_HOST:-example-vps-host}}"
: "${VIBE_PRACTICUM_SUDO_PASSWORD:?Set VIBE_PRACTICUM_SUDO_PASSWORD}"

COMMENT="vibe-router-${CLIENT_NAME}-tproxy-entry"

ssh "$SSH_HOST" \
  "CLIENT_NAME='$CLIENT_NAME' COMMENT='$COMMENT' TPROXY_PORT='$TPROXY_PORT' MARK='$MARK' TABLE='$TABLE' VIBE_PRACTICUM_SUDO_PASSWORD='$VIBE_PRACTICUM_SUDO_PASSWORD' bash -s" <<'REMOTE'
set -euo pipefail
sudo_cmd() { printf '%s\n' "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S "$@"; }

resolve_client_ip() {
  python3 -c '
import json, subprocess, sys
name = sys.argv[1]
raw = subprocess.check_output(["tailscale", "status", "--json"], text=True)
data = json.loads(raw)
matches = []
for peer in data.get("Peer", {}).values():
    host = peer.get("HostName") or ""
    dns = (peer.get("DNSName") or "").rstrip(".")
    addrs = peer.get("TailscaleIPs") or []
    online = peer.get("Online")
    if host == name or dns == name or dns.startswith(name + "."):
        ipv4 = next((a for a in addrs if "." in a), None)
        if ipv4:
            matches.append((host, dns, ipv4, online))
if len(matches) != 1:
    print(f"expected exactly one peer match for {name}, got {len(matches)}", file=sys.stderr)
    for m in matches:
        print("match:", *m, file=sys.stderr)
    sys.exit(2)
if matches[0][3] is not True:
    print(f"refusing offline peer {matches[0][0]} {matches[0][2]}", file=sys.stderr)
    sys.exit(3)
print(matches[0][2])
' "$CLIENT_NAME"
}

CLIENT_TS_IP="$(resolve_client_ip)"
echo "resolved $CLIENT_NAME -> $CLIENT_TS_IP"

sudo_cmd systemctl is-active --quiet tailscaled
sudo_cmd systemctl is-active --quiet sing-box-vibe-router
sudo_cmd systemctl is-active --quiet xray

# Policy route for TPROXY-marked packets to local socket.
if ! ip rule show | grep -Eq "fwmark ${MARK}( |/)"; then
  sudo_cmd ip rule add fwmark "$MARK" table "$TABLE"
fi
if ! ip route show table "$TABLE" | grep -Eq '^local (default|0\.0\.0\.0/0)'; then
  sudo_cmd ip route add local 0.0.0.0/0 dev lo table "$TABLE"
fi

sudo_cmd iptables -t mangle -N VIBE_ROUTER_PIXEL 2>/dev/null || true

if ! sudo_cmd iptables -t mangle -S VIBE_ROUTER_PIXEL | grep -q 'vibe-router-pixel-tproxy'; then
  sudo_cmd iptables -t mangle -F VIBE_ROUTER_PIXEL
  for cidr in \
    0.0.0.0/8 \
    10.0.0.0/8 \
    100.64.0.0/10 \
    127.0.0.0/8 \
    169.254.0.0/16 \
    172.16.0.0/12 \
    192.168.0.0/16 \
    224.0.0.0/4 \
    240.0.0.0/4; do
    sudo_cmd iptables -t mangle -A VIBE_ROUTER_PIXEL -d "$cidr" -m comment --comment vibe-router-pixel-tproxy-bypass -j RETURN
  done
  sudo_cmd iptables -t mangle -A VIBE_ROUTER_PIXEL -p tcp -m comment --comment vibe-router-pixel-tproxy -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK/$MARK"
  sudo_cmd iptables -t mangle -A VIBE_ROUTER_PIXEL -p udp -m comment --comment vibe-router-pixel-tproxy -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK/$MARK"
fi

# Remove stale entries for the same logical client/comment, regardless of old IP.
while sudo_cmd iptables -t mangle -S PREROUTING | grep -F -- "--comment $COMMENT" >/dev/null; do
  spec="$(sudo_cmd iptables -t mangle -S PREROUTING | grep -F -- "--comment $COMMENT" | head -1 | sed 's/^-A /-D /')"
  sudo_cmd iptables -t mangle $spec
  echo "removed stale rule: $spec"
done

sudo_cmd iptables -t mangle -A PREROUTING -i tailscale0 -s "$CLIENT_TS_IP" -m comment --comment "$COMMENT" -j VIBE_ROUTER_PIXEL

echo "synced TCP+UDP TProxy for $CLIENT_NAME ($CLIENT_TS_IP) -> :$TPROXY_PORT"
echo "--- matching PREROUTING rules ---"
sudo_cmd iptables -t mangle -S PREROUTING | grep -E "vibe-router|$CLIENT_TS_IP" || true
echo "--- policy route ---"
ip rule show | grep "fwmark $MARK" || true
ip route show table "$TABLE" || true
REMOTE
