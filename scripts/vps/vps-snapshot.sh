#!/usr/bin/env bash
set -euo pipefail
out_dir="${1:-snapshots/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$out_dir"
: "${VIBE_PRACTICUM_SUDO_PASSWORD:?Set VIBE_PRACTICUM_SUDO_PASSWORD in the environment}"
remote_script="$(mktemp)"
trap 'rm -f "$remote_script"' EXIT
cat >"$remote_script" <<'REMOTE'
set -euo pipefail
echo '=== date ==='; date -u
echo '=== hostname ==='; hostname
echo '=== ip addr ==='; ip -br addr
echo '=== ip route main ==='; ip route show table main
echo '=== ip rule ==='; ip rule show
echo '=== tailscale status ==='; tailscale status || true
echo '=== tailscale prefs ==='; tailscale debug prefs || true
echo '=== services ==='; systemctl --no-pager --type=service --state=running | egrep -i 'tailscale|xray|sing|caddy|nginx|docker|wg|wireguard' || true
echo '=== listening ports ==='; ss -lntup || true
echo '=== iptables filter ==='; iptables-save -t filter || true
echo '=== iptables nat ==='; iptables-save -t nat || true
echo '=== nft ruleset ==='; nft list ruleset || true
echo '=== xray config sanitized ==='; python3 - <<'PY'
import json
p='/usr/local/etc/xray/config.json'
try:
 j=json.load(open(p))
 for ob in j.get('outbounds',[]):
  for vn in ob.get('settings',{}).get('vnext',[]):
   for u in vn.get('users',[]):
    if 'id' in u: u['id']='<uuid>'
 print(json.dumps(j,indent=2,ensure_ascii=False))
except Exception as e:
 print(e)
PY
REMOTE
scp "$remote_script" ${VPNKIT_VPS_SSH_HOST:-example-vps-host}:/tmp/vps-snapshot.sh >/dev/null
ssh ${VPNKIT_VPS_SSH_HOST:-example-vps-host} "printf '%s\\n' \"$VIBE_PRACTICUM_SUDO_PASSWORD\" | sudo -S bash /tmp/vps-snapshot.sh" >"$out_dir/vps-snapshot.txt"
ssh ${VPNKIT_VPS_SSH_HOST:-example-vps-host} "rm -f /tmp/vps-snapshot.sh" >/dev/null 2>&1 || true
echo "$out_dir"
