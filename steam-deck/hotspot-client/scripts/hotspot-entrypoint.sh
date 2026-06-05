#!/usr/bin/env bash
set -Eeuo pipefail
HOSTAPD_CONF=${HOSTAPD_CONF:-/etc/vpnkit-hotspot/hostapd.conf}
DNSMASQ_CONF=${DNSMASQ_CONF:-/etc/vpnkit-hotspot/dnsmasq.conf}
LOG_DIR=${VPNKIT_HOTSPOT_LOG_DIR:-/var/log/vpnkit-hotspot}
HOSTAPD_READY_TIMEOUT=${HOSTAPD_READY_TIMEOUT:-10}
mkdir -p "$LOG_DIR"
if [[ ! -r "$HOSTAPD_CONF" || ! -r "$DNSMASQ_CONF" ]]; then
  echo "missing hostapd or dnsmasq config" >&2
  exit 2
fi
hostapd "$HOSTAPD_CONF" >"$LOG_DIR/hostapd.log" 2>&1 &
HOSTAPD_PID=$!
cleanup(){ kill "$HOSTAPD_PID" 2>/dev/null || true; wait "$HOSTAPD_PID" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
for ((attempt=1; attempt<=HOSTAPD_READY_TIMEOUT; attempt++)); do
  if ! kill -0 "$HOSTAPD_PID" 2>/dev/null; then
    echo "hostapd exited before dnsmasq start" >&2
    cat "$LOG_DIR/hostapd.log" >&2 || true
    exit 3
  fi
  if grep -q 'AP-ENABLED' "$LOG_DIR/hostapd.log" 2>/dev/null; then
    break
  fi
  sleep 1
done
if ! grep -q 'AP-ENABLED' "$LOG_DIR/hostapd.log" 2>/dev/null; then
  echo "hostapd did not report AP-ENABLED before dnsmasq start" >&2
  cat "$LOG_DIR/hostapd.log" >&2 || true
  exit 4
fi
exec dnsmasq --no-daemon --conf-file="$DNSMASQ_CONF"
