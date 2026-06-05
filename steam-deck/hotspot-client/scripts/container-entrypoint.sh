#!/usr/bin/env bash
set -Eeuo pipefail

PROFILE=${OPENVPN_PROFILE:-/etc/openvpn/client.ovpn}
LOG=${OPENVPN_LOG:-/var/log/vpnkit-host-client/openvpn.log}
mkdir -p "$(dirname "$LOG")"

if [[ ! -r "$PROFILE" ]]; then
  echo "missing_openvpn_profile=$PROFILE" >&2
  exit 2
fi
if [[ ! -e /dev/net/tun ]]; then
  echo "missing_tun_device=/dev/net/tun" >&2
  exit 3
fi

{
  echo "[$(date -u +%FT%TZ)] vpnkit host OpenVPN client starting"
  echo "profile_path=/etc/openvpn/client.ovpn"
  echo "log_path=$LOG"
} >>"$LOG"

# Keep durable OpenVPN logs in the mounted log directory. The process remains in
# the foreground so Podman/Compose can manage lifecycle and signals.
exec openvpn --config "$PROFILE" --log-append "$LOG"
