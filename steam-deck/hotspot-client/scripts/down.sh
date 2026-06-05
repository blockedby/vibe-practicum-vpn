#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

REPORT=$(new_report_path down)
{
  write_header "Steam Deck host OpenVPN client down"
  preflight_common
  log "removing only this tool's container: $CONTAINER"
  run podman_cmd rm -f "$CONTAINER" || true
  sleep 2
  if ip link show "$VPN_IFACE" >/dev/null 2>&1; then
    log "warning: $VPN_IFACE still exists after container removal; inspect before hotspot apply"
    ip -br addr show "$VPN_IFACE" || true
  else
    log "vpn_iface_present=no"
  fi
  log "down done"
} 2>&1 | redact | tee "$REPORT"
echo "report_path=$REPORT"
