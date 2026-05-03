#!/usr/bin/env bash
set -u -o pipefail

REPO_DIR="/home/kcnc/code/tools/vibe-practicum-vpn"
SNAP_DIR="$REPO_DIR/snapshots/kcnc-oneshot"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="$SNAP_DIR/stop-$TS.log"
SERVICE="sing-box-vibe-kcnc-oneshot.service"

mkdir -p "$SNAP_DIR"
exec > >(tee -a "$LOG") 2>&1

snapshot() {
  local name="$1"
  local file="$SNAP_DIR/$name-$TS.txt"
  {
    echo "=== snapshot $name $TS ==="
    echo "=== services ==="
    systemctl is-active tailscaled 2>&1 || true
    systemctl is-active "$SERVICE" 2>&1 || true
    systemctl is-active sing-box-vibe-kcnc-safe-tun.service 2>&1 || true
    systemctl is-active sing-box-vibe-local.service 2>&1 || true
    systemctl is-active v2raya 2>&1 || true
    echo "=== processes ==="
    ps -eo pid,comm,args | grep -Ei 'v2ray|v2raya|sing-box|tailscale' | grep -v grep || true
    echo "=== routes main ==="
    ip -4 route show table main 2>&1 || true
    echo "=== routes 52 ==="
    ip -4 route show table 52 2>&1 || true
    echo "=== routes 2022 ==="
    ip -4 route show table 2022 2>&1 || true
    echo "=== rules ==="
    ip rule show 2>&1 || true
    echo "=== interfaces ==="
    ip -br addr 2>&1 || true
    echo "=== journal oneshot ==="
    journalctl -u "$SERVICE" --since '1 hour ago' --no-pager 2>&1 || true
  } > "$file"
  echo "snapshot saved: $file"
}

run() {
  echo
  echo "### $*"
  "$@"
  local rc=$?
  echo "### rc=$rc: $*"
  return "$rc"
}

echo "STOP log: $LOG"
snapshot "before-stop"

run sudo systemctl disable --now "$SERVICE" || true
run sudo systemctl disable --now sing-box-vibe-kcnc-safe-tun.service || true
run sudo systemctl disable --now sing-box-vibe-local.service || true
run sudo ip link delete vibe-tun0 || true

# Remove stale sing-box route table/rules by restarting tailscaled mesh-only and flushing table 2022.
run sudo ip route flush table 2022 || true
# Delete common sing-box rules if left behind. Repeat because priorities can duplicate.
for prio in 9000 9001 9002 9003 9010; do
  while ip rule show | grep -q "^$prio:"; do
    run sudo ip rule del priority "$prio" || break
  done
done

if systemctl is-active --quiet tailscaled; then
  run sudo tailscale down || true
fi

echo
 echo "### post-stop quick checks"
ip -4 route show table main || true
ip route show table 52 2>/dev/null || true
ip rule show || true
ps -eo pid,comm,args | grep -Ei 'v2ray|v2raya|sing-box|tailscale' | grep -v grep || true

snapshot "after-stop"
echo "log saved: $LOG"
echo "Stopped oneshot TUN. V2RayA is not restarted automatically; start it manually if needed."
