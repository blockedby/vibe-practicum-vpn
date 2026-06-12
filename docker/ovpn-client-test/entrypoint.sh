#!/usr/bin/env bash
set -euo pipefail
PROFILE=${1:-${OPENVPN_PROFILE:-/etc/openvpn/client/test-client.ovpn}}
if [[ ! -r "$PROFILE" ]]; then
  echo "missing OpenVPN client profile: $PROFILE" >&2
  exit 1
fi
openvpn --config "$PROFILE" --dev tun0 &
OVPN_PID=$!
NESTED_PID=""
trap 'kill "${NESTED_PID:-}" "$OVPN_PID" 2>/dev/null || true' INT TERM EXIT
until ip -4 addr show tun0 | grep -q '10\.89\.0\.'; do
  if ! kill -0 "$OVPN_PID" 2>/dev/null; then wait "$OVPN_PID"; fi
  sleep 0.5
done

if [[ "${VPNKIT_NESTED_VPN_ENABLED:-1}" != "0" ]]; then
  NESTED_PROFILE=${VPNKIT_NESTED_OPENVPN_PROFILE:-/etc/openvpn/nested/test-client.ovpn}
  NESTED_TARGET=${VPNKIT_NESTED_TARGET:-10.89.0.1}
  NESTED_PEER=${VPNKIT_NESTED_PEER:-10.90.0.1}
  NESTED_TIMEOUT=${VPNKIT_NESTED_TIMEOUT:-60}
  if [[ ! -r "$NESTED_PROFILE" ]]; then
    echo "nested_openvpn_profile=missing path=$NESTED_PROFILE" >&2
    exit 1
  fi
  route=$(ip -4 route get "$NESTED_TARGET" 2>/dev/null | head -1 || true)
  dev=$(printf '%s\n' "$route" | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')
  if [[ "$dev" != "tun0" ]]; then
    echo "nested_route_via_tun0=fail dev=${dev:-unknown}"
    printf '%s\n' "$route" | sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g'
    exit 1
  fi
  echo "nested_route_via_tun0=ok target=$NESTED_TARGET"
  openvpn --config "$NESTED_PROFILE" --dev tun1 &
  NESTED_PID=$!
  deadline=$((SECONDS + NESTED_TIMEOUT))
  until ip -4 addr show tun1 | grep -q '10\.90\.0\.'; do
    if ! kill -0 "$NESTED_PID" 2>/dev/null; then wait "$NESTED_PID"; fi
    if (( SECONDS >= deadline )); then
      echo "nested_openvpn_handshake=fail timeout=${NESTED_TIMEOUT}s" >&2
      exit 1
    fi
    sleep 0.5
  done
  echo "nested_openvpn_handshake=ok"
  echo "nested_tun1=ok"
  if ping -4 -c 2 -W 3 "$NESTED_PEER" >/tmp/nested-ping.out 2>&1; then
    echo "nested_ping_peer=ok peer=$NESTED_PEER"
  else
    echo "nested_ping_peer=fail peer=$NESTED_PEER" >&2
    tail -3 /tmp/nested-ping.out | sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' >&2 || true
    exit 1
  fi
else
  echo "nested_vpn=disabled not_deploy_ready=true"
fi
exec /usr/local/bin/run-tests.sh
