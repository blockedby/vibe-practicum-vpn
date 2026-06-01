#!/usr/bin/env bash
set -euo pipefail
PROFILE=${1:-${OPENVPN_PROFILE:-/etc/openvpn/client/test-client.ovpn}}
if [[ ! -r "$PROFILE" ]]; then
  echo "missing OpenVPN client profile: $PROFILE" >&2
  exit 1
fi
openvpn --config "$PROFILE" &
OVPN_PID=$!
trap 'kill "$OVPN_PID" 2>/dev/null || true' INT TERM EXIT
until ip -4 addr show tun0 | grep -q '10\.89\.0\.'; do
  if ! kill -0 "$OVPN_PID" 2>/dev/null; then wait "$OVPN_PID"; fi
  sleep 0.5
done
exec /usr/local/bin/run-tests.sh
