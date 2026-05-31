#!/usr/bin/env bash
set -euo pipefail

SINGBOX_CONFIG=${SINGBOX_CONFIG:-/etc/sing-box/config.json}
OPENVPN_CONFIG=${OPENVPN_CONFIG:-/etc/openvpn/server.conf}

if [[ ! -r "$SINGBOX_CONFIG" ]]; then
  echo "missing sing-box config: $SINGBOX_CONFIG" >&2
  exit 1
fi
if [[ ! -r "$OPENVPN_CONFIG" ]]; then
  echo "missing OpenVPN server config: $OPENVPN_CONFIG" >&2
  exit 1
fi

sing-box check -c "$SINGBOX_CONFIG"
sing-box run -c "$SINGBOX_CONFIG" &
SINGBOX_PID=$!

openvpn --config "$OPENVPN_CONFIG" &
OVPN_PID=$!

cleanup() {
  kill "$SINGBOX_PID" "$OVPN_PID" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

until ip link show tun0 >/dev/null 2>&1; do
  if ! kill -0 "$OVPN_PID" 2>/dev/null; then
    echo "openvpn exited before tun0 appeared" >&2
    wait "$OVPN_PID"
  fi
  sleep 0.5
done

/usr/local/bin/setup-routing.sh

wait -n "$SINGBOX_PID" "$OVPN_PID"
