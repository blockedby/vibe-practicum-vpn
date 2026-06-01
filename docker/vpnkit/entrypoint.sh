#!/usr/bin/env bash
set -euo pipefail

SINGBOX_SOURCE_CONFIG=${SINGBOX_SOURCE_CONFIG:-/etc/sing-box/config.json}
SINGBOX_CONFIG=${SINGBOX_CONFIG:-/var/lib/vpnkit/sing-box/config.json}
SINGBOX_RESTART_FILE=${SINGBOX_RESTART_FILE:-/run/vpnkit/restart-sing-box}
OPENVPN_CONFIG=${OPENVPN_CONFIG:-/etc/openvpn/server.conf}

if [[ ! -r "$SINGBOX_SOURCE_CONFIG" ]]; then
  echo "missing sing-box source config: $SINGBOX_SOURCE_CONFIG" >&2
  exit 1
fi
if [[ ! -r "$OPENVPN_CONFIG" ]]; then
  echo "missing OpenVPN server config: $OPENVPN_CONFIG" >&2
  exit 1
fi

mkdir -p "$(dirname "$SINGBOX_CONFIG")" "$(dirname "$SINGBOX_RESTART_FILE")"
if [[ ! -f "$SINGBOX_CONFIG" ]]; then
  cp "$SINGBOX_SOURCE_CONFIG" "$SINGBOX_CONFIG"
fi

sing-box check -c "$SINGBOX_CONFIG"
SINGBOX_PID=""
OVPN_PID=""
WATCH_PID=""

start_singbox() {
  sing-box run -c "$SINGBOX_CONFIG" &
  SINGBOX_PID=$!
  echo "started sing-box pid=$SINGBOX_PID config=$SINGBOX_CONFIG"
}

restart_singbox() {
  echo "restart requested for sing-box"
  sing-box check -c "$SINGBOX_CONFIG"
  if [[ -n "${SINGBOX_PID:-}" ]] && kill -0 "$SINGBOX_PID" 2>/dev/null; then
    kill "$SINGBOX_PID" 2>/dev/null || true
    wait "$SINGBOX_PID" 2>/dev/null || true
  fi
  start_singbox
}

cleanup() {
  kill "${WATCH_PID:-}" "${SINGBOX_PID:-}" "${OVPN_PID:-}" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

start_singbox

openvpn --config "$OPENVPN_CONFIG" &
OVPN_PID=$!

until ip link show tun0 >/dev/null 2>&1; do
  if ! kill -0 "$OVPN_PID" 2>/dev/null; then
    echo "openvpn exited before tun0 appeared" >&2
    wait "$OVPN_PID"
  fi
  sleep 0.5
done

/usr/local/bin/setup-routing.sh

last_restart_seen=""
while true; do
  if [[ -f "$SINGBOX_RESTART_FILE" ]]; then
    current=$(stat -c '%Y:%s' "$SINGBOX_RESTART_FILE" 2>/dev/null || true)
    if [[ -n "$current" && "$current" != "$last_restart_seen" ]]; then
      last_restart_seen="$current"
      restart_singbox || echo "sing-box restart request failed" >&2
      rm -f "$SINGBOX_RESTART_FILE" || true
    fi
  fi
  if ! kill -0 "$SINGBOX_PID" 2>/dev/null; then
    echo "sing-box exited" >&2
    wait "$SINGBOX_PID"
    exit 1
  fi
  if ! kill -0 "$OVPN_PID" 2>/dev/null; then
    echo "openvpn exited" >&2
    wait "$OVPN_PID"
    exit 1
  fi
  sleep 1
done
