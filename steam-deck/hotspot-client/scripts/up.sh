#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

WAIT_SECONDS=${VPNKIT_DECK_CLIENT_WAIT_SECONDS:-60}
REPORT=$(new_report_path up)
{
  write_header "Steam Deck host OpenVPN client up"
  preflight_common
  preflight_profile
  if podman_cmd ps --format '{{.Names}}' | grep -Fxq vpnkit; then
    log "existing vpnkit container detected; not touching it"
  fi
  log "ensuring image exists"
  if ! podman_cmd image exists "$IMAGE" >/dev/null 2>&1; then
    run podman_cmd build -t "$IMAGE" -f "$STEAM_DECK_CLIENT_DIR/Containerfile" "$STEAM_DECK_CLIENT_DIR"
  fi
  log "starting separate host-network OpenVPN client container"
  run podman_cmd rm -f "$CONTAINER" || true
  run podman_cmd run -d \
    --name "$CONTAINER" \
    --replace \
    --network host \
    --cap-add NET_ADMIN \
    --cap-add NET_RAW \
    --device /dev/net/tun:/dev/net/tun \
    --restart unless-stopped \
    -e OPENVPN_PROFILE=/etc/openvpn/client.ovpn \
    -e OPENVPN_LOG=/var/log/vpnkit-host-client/openvpn.log \
    -v "$PROFILE:/etc/openvpn/client.ovpn:ro" \
    -v "$LOG_DIR:/var/log/vpnkit-host-client" \
    "$IMAGE"
  log "waiting up to ${WAIT_SECONDS}s for host interface $VPN_IFACE"
  ready=0
  for _ in $(seq 1 "$WAIT_SECONDS"); do
    if ip link show "$VPN_IFACE" >/dev/null 2>&1; then ready=1; break; fi
    sleep 1
  done
  if [[ $ready -eq 1 ]]; then
    log "vpn_iface_ready=yes"
    ip -br addr show "$VPN_IFACE" || true
    ip route get 1.1.1.1 || true
  else
    log "vpn_iface_ready=no"
    podman_cmd logs --tail 80 "$CONTAINER" || true
    [[ -r "$LOG_DIR/openvpn.log" ]] && tail -80 "$LOG_DIR/openvpn.log" || true
    exit 20
  fi
  log "up done"
} 2>&1 | redact | tee "$REPORT"
echo "report_path=$REPORT"
