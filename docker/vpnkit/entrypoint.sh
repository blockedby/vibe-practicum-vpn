#!/usr/bin/env bash
set -euo pipefail

VPNKIT_ROUTING_MODE=${VPNKIT_ROUTING_MODE:-redirect}
SINGBOX_CONFIG=${SINGBOX_CONFIG:-/var/lib/vpnkit/sing-box/config.json}
SINGBOX_RESTART_FILE=${SINGBOX_RESTART_FILE:-/run/vpnkit/restart-sing-box}
OPENVPN_CONFIG=${OPENVPN_CONFIG:-/etc/openvpn/server.conf}
VIBE_VPN_CONFIG=${VIBE_VPN_CONFIG:-/etc/vibe-vpn/config.yaml}
VPNKIT_ENABLE_VIBE_VPN_DAEMON=${VPNKIT_ENABLE_VIBE_VPN_DAEMON:-false}

case "$VPNKIT_ROUTING_MODE" in
  tproxy)
    SINGBOX_SOURCE_CONFIG=${SINGBOX_SOURCE_CONFIG:-/etc/sing-box/config.tproxy.json}
    ;;
  tun)
    SINGBOX_SOURCE_CONFIG=${SINGBOX_SOURCE_CONFIG:-/etc/sing-box/config.tun.json}
    ;;
  redirect)
    SINGBOX_SOURCE_CONFIG=${SINGBOX_SOURCE_CONFIG:-/etc/sing-box/config.json}
    ;;
  *)
    echo "unsupported VPNKIT_ROUTING_MODE=$VPNKIT_ROUTING_MODE (expected redirect, tun, or tproxy)" >&2
    exit 2
    ;;
esac

if [[ ! -r "$SINGBOX_SOURCE_CONFIG" ]]; then
  echo "missing sing-box source config: $SINGBOX_SOURCE_CONFIG" >&2
  exit 1
fi
if [[ ! -r "$OPENVPN_CONFIG" ]]; then
  echo "missing OpenVPN server config: $OPENVPN_CONFIG" >&2
  exit 1
fi

mkdir -p "$(dirname "$SINGBOX_CONFIG")" "$(dirname "$SINGBOX_RESTART_FILE")"
cp "$SINGBOX_SOURCE_CONFIG" "$SINGBOX_CONFIG"

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

singbox_is_running() {
  if ! kill -0 "$SINGBOX_PID" 2>/dev/null; then
    echo "sing-box exited before readiness signal became ready" >&2
    wait "$SINGBOX_PID"
  fi
}

wait_for_singbox_inbounds() {
  local deadline=$((SECONDS + ${SINGBOX_STARTUP_TIMEOUT_SECONDS:-30}))
  until ss -ltn sport = :2082 | grep -q ':2082' \
    && ss -lun sport = :5353 | grep -q ':5353'; do
    singbox_is_running
    if (( SECONDS >= deadline )); then
      echo "timed out waiting for sing-box redirect inbounds on tcp/2082 and udp/5353" >&2
      return 1
    fi
    sleep 0.2
  done
  echo "sing-box inbounds ready for redirect mode"
}

wait_for_singbox_tproxy_inbounds() {
  local deadline=$((SECONDS + ${SINGBOX_STARTUP_TIMEOUT_SECONDS:-30}))
  until ss -ltn sport = :2082 | grep -q ':2082' \
    && ss -lun sport = :2082 | grep -q ':2082' \
    && ss -ltn sport = :2083 | grep -q ':2083' \
    && ss -lun sport = :5353 | grep -q ':5353'; do
    singbox_is_running
    if (( SECONDS >= deadline )); then
      echo "timed out waiting for sing-box tproxy inbounds on tcp/2082, udp/2082, tcp/2083, and udp/5353" >&2
      return 1
    fi
    sleep 0.2
  done
  echo "sing-box inbounds ready for tproxy mode"
}

wait_for_singbox_tun() {
  local deadline=$((SECONDS + ${SINGBOX_STARTUP_TIMEOUT_SECONDS:-30}))
  until ip link show sb-tun0 >/dev/null 2>&1 \
    && ip -4 addr show dev sb-tun0 2>/dev/null | grep -q '172[.]19[.]0[.]1/30' \
    && ss -lun sport = :5353 | grep -q ':5353'; do
    singbox_is_running
    if (( SECONDS >= deadline )); then
      echo "timed out waiting for sing-box tun interface sb-tun0 with 172.19.0.1/30 and udp/5353" >&2
      return 1
    fi
    sleep 0.2
  done
  echo "sing-box tun interface ready for tun mode"
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
  kill "${WATCH_PID:-}" "${SINGBOX_PID:-}" "${OVPN_PID:-}" "${VIBE_VPN_PID:-}" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

start_singbox
case "$VPNKIT_ROUTING_MODE" in
  tproxy) wait_for_singbox_tproxy_inbounds ;;
  tun) wait_for_singbox_tun ;;
  redirect) wait_for_singbox_inbounds ;;
esac

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
