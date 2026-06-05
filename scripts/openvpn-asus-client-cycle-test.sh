#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Sequentially test ASUS OpenVPN client slots over SSH, then stop tested clients.

WARNING: this mutates router VPN client state and can temporarily break Internet
for devices behind the router, including this computer. Run only with explicit
operator approval and a known recovery path.

Usage:
  scripts/openvpn-asus-client-cycle-test.sh --host <ssh-target> [--port 707] [--key ~/.ssh/asus-key] --slots 1,2,3,4

Environment alternatives:
  ASUS_SSH_HOST / VPNKIT_ASUS_SSH_HOST   SSH target (required unless --host)
  ASUS_SSH_PORT / VPNKIT_ASUS_SSH_PORT   SSH port (default: 22)
  ASUS_SSH_KEY  / VPNKIT_ASUS_SSH_KEY    SSH private key path
  ASUS_VPN_SLOTS / VPNKIT_ASUS_VPN_SLOTS comma/space separated slots
  ASUS_WAIT_SECONDS                      wait per slot for connected state (default: 45)
  ASUS_REPORT_PATH                       report path (default: reports/asus-openvpn-client-cycle-<timestamp>.md)
  ASUS_CONFIRM=YES                       required confirmation unless --yes is used

The report is public-safe: it redacts IPv4 addresses and hashes observed public
IP values. It does not print profile contents, private keys, endpoints, or nvram
secret fields.
USAGE
}

SSH_HOST="${ASUS_SSH_HOST:-${VPNKIT_ASUS_SSH_HOST:-}}"
SSH_PORT="${ASUS_SSH_PORT:-${VPNKIT_ASUS_SSH_PORT:-22}}"
SSH_KEY="${ASUS_SSH_KEY:-${VPNKIT_ASUS_SSH_KEY:-}}"
SLOTS_RAW="${ASUS_VPN_SLOTS:-${VPNKIT_ASUS_VPN_SLOTS:-}}"
WAIT_SECONDS="${ASUS_WAIT_SECONDS:-45}"
REPORT_PATH="${ASUS_REPORT_PATH:-}"
YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) SSH_HOST="${2:-}"; shift 2 ;;
    --port) SSH_PORT="${2:-}"; shift 2 ;;
    --key) SSH_KEY="${2:-}"; shift 2 ;;
    --slots) SLOTS_RAW="${2:-}"; shift 2 ;;
    --wait-seconds) WAIT_SECONDS="${2:-}"; shift 2 ;;
    --report) REPORT_PATH="${2:-}"; shift 2 ;;
    --yes) YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$SSH_HOST" || -z "$SLOTS_RAW" ]]; then
  echo "missing required --host and/or --slots" >&2
  usage >&2
  exit 2
fi
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ && "$WAIT_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "--port and --wait-seconds must be numeric" >&2
  exit 2
fi

SLOTS_RAW=${SLOTS_RAW//,/ }
read -r -a SLOTS <<<"$SLOTS_RAW"
if [[ "${#SLOTS[@]}" -eq 0 ]]; then
  echo "no slots provided" >&2
  exit 2
fi
for slot in "${SLOTS[@]}"; do
  if ! [[ "$slot" =~ ^[1-5]$ ]]; then
    echo "invalid ASUS OpenVPN client slot '$slot' (expected 1..5)" >&2
    exit 2
  fi
done

if [[ -z "$REPORT_PATH" ]]; then
  mkdir -p reports
  REPORT_PATH="reports/asus-openvpn-client-cycle-$(date -u +%Y%m%dT%H%M%SZ).md"
else
  mkdir -p "$(dirname "$REPORT_PATH")"
fi

if [[ "$YES" != 1 && "${ASUS_CONFIRM:-}" != "YES" ]]; then
  cat >&2 <<'WARN'
Refusing to run without confirmation.
This script will SSH to the router, start/stop VPN client slots, and can
interrupt Internet connectivity for this computer. Re-run with --yes or
ASUS_CONFIRM=YES only when ready.
WARN
  exit 3
fi

SSH_OPTS=(-p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=10)
if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY")
fi

redact() {
  sed -E \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' \
    -e 's/(remote|server|addr|gateway|route)[=: ][^[:space:]]+/\1=<redacted>/Ig'
}

shell_quote() { printf '%q' "$1"; }

REMOTE_SLOTS="${SLOTS[*]}"
TMP_OUT=$(mktemp)
cleanup_tmp() { rm -f "$TMP_OUT"; }
trap cleanup_tmp EXIT

set +e
ssh "${SSH_OPTS[@]}" "$SSH_HOST" \
  "ASUS_TEST_SLOTS=$(shell_quote "$REMOTE_SLOTS") ASUS_WAIT_SECONDS=$(shell_quote "$WAIT_SECONDS") /bin/sh -s" >"$TMP_OUT" 2>&1 <<'REMOTE'
set -u

SLOTS="$ASUS_TEST_SLOTS"
WAIT_SECONDS="${ASUS_WAIT_SECONDS:-45}"
STARTED_SLOTS=""

have_cmd() { type "$1" >/dev/null 2>&1; }

hash8() {
  if have_cmd sha256sum; then
    printf '%s' "$1" | sha256sum | cut -c1-8
  elif have_cmd md5sum; then
    printf '%s' "$1" | md5sum | cut -c1-8
  else
    printf 'unavailable'
  fi
}

redact_ips() { sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g'; }

get_nvram() { nvram get "$1" 2>/dev/null || true; }
set_nvram() { nvram set "$1=$2" 2>/dev/null || true; }
service_call() { service "$1" 2>&1 || true; }

stop_slot() {
  slot="$1"
  echo "cleanup_slot_${slot}=start"
  service_call "stop_vpnclient${slot}" | redact_ips
  set_nvram "vpn_client${slot}_state" "0"
  echo "cleanup_slot_${slot}=done"
}

cleanup_all() {
  echo "cleanup_all_tested_slots=start"
  for slot in $SLOTS; do
    stop_slot "$slot"
  done
  echo "cleanup_all_tested_slots=done"
}
trap cleanup_all EXIT INT TERM HUP

router_fetch() {
  name="$1"; url="$2"
  if have_cmd curl; then
    body=$(curl -4fsS --max-time 15 "$url" 2>/tmp/${name}.err) && rc=0 || rc=$?
  elif have_cmd wget; then
    body=$(wget -4 -q -T 15 -O - "$url" 2>/tmp/${name}.err) && rc=0 || rc=$?
  else
    echo "${name}=skip no_curl_or_wget"
    return 0
  fi
  if [ "$rc" -ne 0 ]; then
    printf '%s=fail rc=%s detail=' "$name" "$rc"
    tail -1 /tmp/${name}.err 2>/dev/null | redact_ips || true
    printf '\n'
    return 0
  fi
  first_ip=$(printf '%s\n' "$body" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
  if [ -n "$first_ip" ]; then
    echo "${name}=ok ip_hash=$(hash8 "$first_ip")"
  else
    echo "${name}=ok body_hash=$(hash8 "$body")"
  fi
}

router_ping() {
  name="$1"; target="$2"
  out=$(ping -4 -c 3 -W 3 "$target" 2>&1) && rc=0 || rc=$?
  loss=$(printf '%s\n' "$out" | sed -n 's/.* \([0-9.]*%\) packet loss.*/\1/p' | tail -1)
  if [ "$rc" -eq 0 ]; then
    echo "${name}=ok loss=${loss:-unknown}"
  else
    printf '%s=fail rc=%s loss=%s detail=' "$name" "$rc" "${loss:-unknown}"
    printf '%s\n' "$out" | tail -1 | redact_ips
  fi
}

router_dns() {
  name="$1"; host="$2"
  if have_cmd nslookup; then
    out=$(nslookup "$host" 8.8.8.8 2>&1) && rc=0 || rc=$?
  elif have_cmd dig; then
    out=$(dig +time=8 +tries=1 @8.8.8.8 "$host" A 2>&1) && rc=0 || rc=$?
  else
    echo "${name}=skip no_nslookup_or_dig"
    return 0
  fi
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -Eq 'Address|ANSWER'; then
    echo "${name}=ok"
  else
    printf '%s=fail rc=%s detail=' "$name" "$rc"
    printf '%s\n' "$out" | tail -1 | redact_ips
  fi
}

slot_state() {
  slot="$1"
  state=$(get_nvram "vpn_client${slot}_state")
  iface="tun1${slot}"
  echo "slot_${slot}_state=${state:-unknown}"
  if ifconfig "$iface" >/dev/null 2>&1 || ip addr show "$iface" >/dev/null 2>&1; then
    echo "slot_${slot}_iface=${iface} present"
  else
    echo "slot_${slot}_iface=${iface} missing"
  fi
}

run_slot() {
  slot="$1"
  echo "## slot ${slot}"
  desc=$(get_nvram "vpn_client${slot}_desc")
  proto=$(get_nvram "vpn_client${slot}_proto")
  rgw=$(get_nvram "vpn_client${slot}_rgw")
  adns=$(get_nvram "vpn_client${slot}_adns")
  echo "slot_${slot}_desc_hash=$(hash8 "$desc") proto=${proto:-unknown} rgw=${rgw:-unknown} adns=${adns:-unknown}"

  echo "slot_${slot}_pre_stop_all=start"
  for other in $SLOTS; do stop_slot "$other"; done
  sleep 3

  echo "slot_${slot}_start=start"
  service_call "start_vpnclient${slot}" | redact_ips
  STARTED_SLOTS="$STARTED_SLOTS $slot"

  ready=0
  i=0
  while [ "$i" -lt "$WAIT_SECONDS" ]; do
    state=$(get_nvram "vpn_client${slot}_state")
    if [ "$state" = "2" ]; then ready=1; break; fi
    sleep 1
    i=$((i + 1))
  done
  if [ "$ready" = "1" ]; then
    echo "slot_${slot}_openvpn_status=ready seconds=$i"
  else
    echo "slot_${slot}_openvpn_status=not_ready state=$(get_nvram "vpn_client${slot}_state") waited=${WAIT_SECONDS}"
  fi
  slot_state "$slot"

  echo "slot_${slot}_routes_start"
  ip route get 1.1.1.1 2>&1 | head -1 | redact_ips || true
  ip route get 8.8.8.8 2>&1 | head -1 | redact_ips || true

  echo "slot_${slot}_icmp_start"
  router_ping "slot_${slot}_ping_1_1_1_1" "1.1.1.1"
  router_ping "slot_${slot}_ping_8_8_8_8" "8.8.8.8"

  echo "slot_${slot}_dns_start"
  router_dns "slot_${slot}_dns_x" "x.com"
  router_dns "slot_${slot}_dns_ya" "ya.ru"
  router_dns "slot_${slot}_dns_linkedin" "www.linkedin.com"

  echo "slot_${slot}_ip_identity_start"
  router_fetch "slot_${slot}_ip_ifconfig_me" "https://ifconfig.me"
  router_fetch "slot_${slot}_ip_ipify" "https://api.ipify.org"
  router_fetch "slot_${slot}_ip_yandex_internetometer" "https://yandex.ru/internet/"

  echo "slot_${slot}_https_start"
  router_fetch "slot_${slot}_https_x" "https://x.com/"
  router_fetch "slot_${slot}_https_ya" "https://ya.ru/"
  router_fetch "slot_${slot}_https_linkedin" "https://www.linkedin.com/"

  stop_slot "$slot"
  sleep 3
  echo "slot_${slot}_done"
}

echo "timestamp=$(date -u +%FT%TZ 2>/dev/null || date)"
echo "router_model=$(nvram get productid 2>/dev/null || true)"
echo "tested_slots=$SLOTS"
for slot in $SLOTS; do
  run_slot "$slot"
done
REMOTE
rc=$?
set -e

{
  echo "# ASUS OpenVPN client cycle report"
  echo
  echo "- Timestamp: $(date -u +%FT%TZ)"
  echo "- SSH target: <redacted>"
  echo "- SSH port: $SSH_PORT"
  echo "- Slots: ${SLOTS[*]}"
  echo "- Router mutation: started each slot sequentially; cleanup trap stopped all tested slots at exit"
  echo "- Script exit code: $rc"
  echo
  echo '```text'
  redact <"$TMP_OUT"
  echo '```'
} >"$REPORT_PATH"

cat <<OUT
report_path=$REPORT_PATH
script_exit_code=$rc
note=report_redacts_ipv4_addresses_and_endpoint_like_values
OUT

exit "$rc"
