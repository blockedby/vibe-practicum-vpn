#!/usr/bin/env bash
# Bounded, read-only same-host smoke for the local NetworkManager VPN.
set -Eeuo pipefail
umask 077

ROUTE_IP=${VPNKIT_LOCAL_SMOKE_ROUTE_IP:-1.1.1.1}
PING_IPS=${VPNKIT_LOCAL_SMOKE_PING_IPS:-1.1.1.1,8.8.8.8}
HOSTNAME=${VPNKIT_LOCAL_SMOKE_HOSTNAME:-example.com}
IPV6_ADDRESS=${VPNKIT_LOCAL_SMOKE_IPV6_ADDRESS:-2606:4700:4700::1111}
TIMEOUT=${VPNKIT_LOCAL_SMOKE_TIMEOUT_SECONDS:-8}
DEVICE=${VPNKIT_LOCAL_SMOKE_DEVICE:-}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

valid_ipv4() {
  local value=$1 old_ifs=$IFS
  local -a octets
  IFS=.
  read -r -a octets <<<"$value"
  IFS=$old_ifs
  [[ ${#octets[@]} -eq 4 ]] || return 1
  local octet
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
    (( 10#$octet <= 255 )) || return 1
  done
}

valid_ipv6() {
  [[ "$1" == *:* && "$1" != *[[:space:]/]* ]] || return 1
  python3 - "$1" <<'PY' >/dev/null 2>&1
import ipaddress
import sys
ipaddress.IPv6Address(sys.argv[1])
PY
}

valid_device() {
  local device=$1
  [[ "$device" =~ ^tun[A-Za-z0-9_.-]{0,14}$ ]] || return 1
  (( ${#device} <= 15 )) || return 1
  [[ "$device" != ppp0 && "$device" != vpn0 ]]
}

[[ "$TIMEOUT" =~ ^[0-9]+$ ]] && (( TIMEOUT >= 1 && TIMEOUT <= 30 )) || fail 'VPNKIT_LOCAL_SMOKE_TIMEOUT_SECONDS must be in 1..30'
valid_device "$DEVICE" || fail 'local smoke VPN device is missing or unsafe'
valid_ipv4 "$ROUTE_IP" || fail 'local smoke route address is invalid'
valid_ipv6 "$IPV6_ADDRESS" || fail 'local smoke IPv6 address is invalid'
[[ "$HOSTNAME" =~ ^[A-Za-z0-9.-]+$ && "$HOSTNAME" != .* && "$HOSTNAME" != *..* ]] || fail 'local smoke hostname is invalid'

command -v ip >/dev/null 2>&1 || fail 'ip is unavailable for local smoke'
command -v getent >/dev/null 2>&1 || fail 'getent is unavailable for local smoke'
command -v curl >/dev/null 2>&1 || fail 'curl is unavailable for local smoke'
command -v ping >/dev/null 2>&1 || fail 'ping is unavailable for local smoke'
command -v timeout >/dev/null 2>&1 || fail 'timeout is unavailable for local smoke'

# A route to an internet literal must use the OpenVPN tunnel device, not a
# physical uplink or an unrelated local interface.
route4=$(ip -4 route get "$ROUTE_IP" 2>/dev/null) || fail 'IPv4 route smoke failed'
# The expected device comes only from the validated active owned NM UUID.  An
# arbitrary tun/tap/ppp/vpn interface is not equivalent proof: require the
# route lookup to select that exact device.
route_device=$(awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }' <<<"$route4")
[[ "$route_device" == "$DEVICE" ]] || fail 'IPv4 route did not use the exact local VPN device'
case "$route_device" in
  ppp0|vpn0) fail 'IPv4 route used a forbidden VPN-like device' ;;
  tun*) ;;
  *) fail 'IPv4 route did not use a safe VPN tunnel device' ;;
esac

timeout "$TIMEOUT" getent ahostsv4 "$HOSTNAME" 2>/dev/null | awk '$1 ~ /^[0-9]+(\.[0-9]+){3}$/ { found=1 } END { exit(found ? 0 : 1) }' \
  >/dev/null || fail 'DNS hostname smoke failed'

curl -4 -fsS --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" -o /dev/null "https://$HOSTNAME/" \
  >/dev/null 2>&1 || fail 'hostname HTTPS smoke failed'
curl -4 -kfsS --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" -o /dev/null "https://$ROUTE_IP/" \
  >/dev/null 2>&1 || fail 'literal-IP HTTPS smoke failed'

old_ifs=$IFS
IFS=, read -r -a ping_addresses <<<"$PING_IPS"
IFS=$old_ifs
[[ ${#ping_addresses[@]} -gt 0 ]] || fail 'ping smoke has no addresses'
for address in "${ping_addresses[@]}"; do
  valid_ipv4 "$address" || fail 'local smoke ping address is invalid'
  ping -4 -c 1 -W "$TIMEOUT" "$address" >/dev/null 2>&1 || fail 'IPv4 ping smoke failed'
done

# The local profile is intentionally IPv4-only. Both route lookup and an
# actual IPv6 echo must fail; accepting either would permit an IPv6 leak.
route6=$(ip -6 route get "$IPV6_ADDRESS" 2>/dev/null || true)
if [[ -n "$route6" ]] && ! grep -Eiq '(^|[[:space:]])(unreachable|prohibit|blackhole)([[:space:]]|$)' <<<"$route6"; then
  fail 'IPv6 route is unexpectedly available'
fi
if ping -6 -c 1 -W "$TIMEOUT" "$IPV6_ADDRESS" >/dev/null 2>&1; then
  fail 'IPv6 ping unexpectedly succeeded'
fi

printf 'host_smoke=pass\n'
printf 'route=pass\n'
printf 'dns=pass\n'
printf 'hostname_https=pass\n'
printf 'literal_ip_https=pass\n'
printf 'ipv4_ping=pass\n'
printf 'ipv6_block=pass\n'
