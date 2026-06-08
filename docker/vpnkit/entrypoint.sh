#!/usr/bin/env bash
set -euo pipefail

SINGBOX_SOURCE_CONFIG=${SINGBOX_SOURCE_CONFIG:-/etc/sing-box/config.json}
SINGBOX_CONFIG=${SINGBOX_CONFIG:-/var/lib/vpnkit/sing-box/config.json}
SINGBOX_RESTART_FILE=${SINGBOX_RESTART_FILE:-/run/vpnkit/restart-sing-box}
OPENVPN_CONFIG=${OPENVPN_CONFIG:-/etc/openvpn/server.conf}
VIBE_VPN_CONFIG=${VIBE_VPN_CONFIG:-/etc/vibe-vpn/config.yaml}
VPNKIT_ENABLE_VIBE_VPN_DAEMON=${VPNKIT_ENABLE_VIBE_VPN_DAEMON:-false}

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
VIBE_VPN_PID=""
WATCH_PID=""

start_singbox() {
  sing-box run -c "$SINGBOX_CONFIG" &
  SINGBOX_PID=$!
  echo "started sing-box pid=$SINGBOX_PID config=$SINGBOX_CONFIG"
}

singbox_tcp_ready() {
  local port=$1
  ss -ltn sport = :"$port" | grep -q ":$port"
}

singbox_udp_ready() {
  local port=$1
  ss -lun sport = :"$port" | grep -q ":$port"
}

singbox_tun_ready() {
  local iface=${SINGBOX_TUN_IFACE:-sb-tun0}
  ip link show "$iface" >/dev/null 2>&1
}

wait_for_singbox_inbounds() {
  local mode=${VPNKIT_ROUTING_MODE:-redirect}
  mode=${mode,,}
  local deadline=$((SECONDS + ${SINGBOX_STARTUP_TIMEOUT_SECONDS:-30}))
  local ready_message timeout_message

  case "$mode" in
    tun)
      ready_message="sing-box tun inbound ready on ${SINGBOX_TUN_IFACE:-sb-tun0}"
      timeout_message="timed out waiting for sing-box tun interface ${SINGBOX_TUN_IFACE:-sb-tun0}"
      ;;
    tproxy)
      ready_message="sing-box tproxy inbound ready on tcp/2082"
      timeout_message="timed out waiting for sing-box tproxy inbound on tcp/2082"
      ;;
    redirect|*)
      ready_message="sing-box redirect inbounds ready on tcp/2082 and udp/5353"
      timeout_message="timed out waiting for sing-box redirect inbounds on tcp/2082 and udp/5353"
      ;;
  esac

  until case "$mode" in
    tun) singbox_tun_ready ;;
    tproxy) singbox_tcp_ready 2082 ;;
    redirect|*) singbox_tcp_ready 2082 && singbox_udp_ready 5353 ;;
  esac; do
    if ! kill -0 "$SINGBOX_PID" 2>/dev/null; then
      echo "sing-box exited before inbounds became ready" >&2
      wait "$SINGBOX_PID"
    fi
    if (( SECONDS >= deadline )); then
      echo "$timeout_message" >&2
      return 1
    fi
    sleep 0.2
  done
  echo "$ready_message"
}

restart_singbox() {
  echo "restart requested for sing-box"
  sing-box check -c "$SINGBOX_CONFIG"
  if [[ -n "${SINGBOX_PID:-}" ]] && kill -0 "$SINGBOX_PID" 2>/dev/null; then
    kill "$SINGBOX_PID" 2>/dev/null || true
    wait "$SINGBOX_PID" 2>/dev/null || true
  fi
  start_singbox
  wait_for_singbox_inbounds
  /usr/local/bin/setup-routing.sh
}

cleanup() {
  kill "${WATCH_PID:-}" "${SINGBOX_PID:-}" "${OVPN_PID:-}" "${VIBE_VPN_PID:-}" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

start_singbox
wait_for_singbox_inbounds

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

case "${VPNKIT_ENABLE_VIBE_VPN_DAEMON,,}" in
  1|true|yes|on)
    if [[ ! -r "$VIBE_VPN_CONFIG" ]]; then
      echo "missing vibe-vpn config: $VIBE_VPN_CONFIG" >&2
      exit 1
    fi
    vibe-vpn daemon --config "$VIBE_VPN_CONFIG" &
    VIBE_VPN_PID=$!
    echo "started vibe-vpn daemon pid=$VIBE_VPN_PID config=$VIBE_VPN_CONFIG"
    ;;
  *)
    echo "vibe-vpn daemon disabled (set VPNKIT_ENABLE_VIBE_VPN_DAEMON=true to enable)"
    ;;
esac

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
  if [[ -n "${VIBE_VPN_PID:-}" ]] && ! kill -0 "$VIBE_VPN_PID" 2>/dev/null; then
    echo "vibe-vpn daemon exited" >&2
    wait "$VIBE_VPN_PID"
    exit 1
  fi
  sleep 1
done
