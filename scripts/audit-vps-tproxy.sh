#!/usr/bin/env bash
set -euo pipefail

SSH_HOST="${SSH_HOST:-${VPNKIT_VPS_SSH_HOST:-example-vps-host}}"
CLIENT_NAME="${CLIENT_NAME:-kcnc-pc}"

ssh "$SSH_HOST" "CLIENT_NAME='$CLIENT_NAME' bash -s" <<'REMOTE'
set -euo pipefail

echo "=== host ==="
hostname; date

echo "=== services ==="
for svc in tailscaled xray sing-box-vibe-router; do
  printf '%-24s ' "$svc"
  systemctl is-active "$svc" 2>&1 || true
done

echo "=== tailscale self/ip ==="
tailscale ip -4 2>&1 || true

echo "=== tailscale status matching client ==="
tailscale status | grep -E "(^|[[:space:]])${CLIENT_NAME}([[:space:].]|$)" || true

echo "=== resolve client from tailscale json ==="
python3 -c '
import json, subprocess, sys
name=sys.argv[1]
raw=subprocess.check_output(["tailscale", "status", "--json"], text=True)
data=json.loads(raw)
for kind,node in [("self", data.get("Self") or {})] + [("peer", p) for p in (data.get("Peer") or {}).values()]:
    host=node.get("HostName") or ""
    dns=(node.get("DNSName") or "").rstrip(".")
    ips=node.get("TailscaleIPs") or []
    online=node.get("Online")
    if host == name or dns == name or dns.startswith(name + "."):
        print(kind, host, dns, "online=" + str(online), " ".join(ips))
' "$CLIENT_NAME"

echo "=== listeners ==="
ss -lntup 2>/dev/null | grep -E ':10808|:2080|:2081|:2082|xray|sing' || true

echo "=== tproxy rules if sudo allowed ==="
sudo -n iptables -t mangle -S PREROUTING 2>/dev/null | grep vibe-router || true
sudo -n iptables -t mangle -S VIBE_ROUTER_PIXEL 2>/dev/null || true
sudo -n ip rule show 2>/dev/null | grep fwmark || true
sudo -n ip route show table 100 2>/dev/null || true
REMOTE
