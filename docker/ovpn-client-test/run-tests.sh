#!/usr/bin/env bash
set -Eeuo pipefail

LOG=${VPNKIT_TEST_LOG:-/var/log/vpnkit/ovpn-client-test.log}
mkdir -p "$(dirname "$LOG")"
exec > >(tee "$LOG") 2>&1

PASS=0
FAIL=0
SKIP=0

row() {
  local status=$1 name=$2 reason=${3:-}
  case "$status" in
    PASS) PASS=$((PASS + 1)) ;;
    FAIL) FAIL=$((FAIL + 1)) ;;
    SKIP) SKIP=$((SKIP + 1)) ;;
    *) printf 'FAIL internal:invalid-status %s\n' "$status"; FAIL=$((FAIL + 1)); return ;;
  esac
  printf '%s %s%s\n' "$status" "$name" "${reason:+ - $reason}"
}

printf 'openvpn_client_test_start=%s\n' "$(date -u +%FT%TZ)"

if command -v ip >/dev/null 2>&1 && ip -4 addr show dev tun0 >/dev/null 2>&1; then
  row PASS openvpn:tun0 'client tunnel interface exists'
else
  row FAIL openvpn:tun0 'client tunnel interface is unavailable'
fi

route_dev=''
route_google_dev=''
if command -v ip >/dev/null 2>&1; then
  route_dev=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i + 1); exit}}' || true)
  route_google_dev=$(ip -4 route get 8.8.8.8 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i + 1); exit}}' || true)
fi
if [[ "$route_dev" == tun0 && "$route_google_dev" == tun0 ]]; then
  row PASS route:via-tun0 'public IPv4 routes select the OpenVPN tunnel'
else
  row FAIL route:via-tun0 'public IPv4 routes did not select tun0'
fi

# dig defaults to UDP; +notcp makes that contract explicit. This is practical
# UDP coverage through the full tunnel, while the arbitrary-UDP row below stays
# an honest bounded skip because no deterministic public UDP echo service exists.
if command -v dig >/dev/null 2>&1; then
  if timeout -k 2s 12s dig +notcp +time=5 +tries=1 @8.8.8.8 example.com A >/dev/null 2>&1; then
    row PASS udp:google-dns 'UDP DNS query to 8.8.8.8 succeeded'
  else
    row FAIL udp:google-dns 'UDP DNS query to 8.8.8.8 failed'
  fi
else
  row SKIP udp:google-dns 'dig is unavailable; no UDP DNS probe was possible'
fi
row SKIP udp:arbitrary 'no deterministic public UDP echo target; UDP DNS coverage is exercised'

if command -v curl >/dev/null 2>&1; then
  if curl -4 --fail --silent --show-error --max-time 20 https://example.com/ -o /dev/null; then
    row PASS https:hostname 'HTTPS by hostname succeeded'
  else
    row FAIL https:hostname 'HTTPS by hostname failed'
  fi
  if curl -4 --fail --silent --show-error --max-time 20 \
      --resolve one.one.one.one:443:1.1.1.1 \
      https://one.one.one.one/cdn-cgi/trace -o /dev/null; then
    row PASS https:literal-ip 'literal-IP HTTPS probe succeeded'
  else
    row FAIL https:literal-ip 'literal-IP HTTPS probe failed'
  fi
else
  row SKIP https:hostname 'curl is unavailable'
  row SKIP https:literal-ip 'curl is unavailable'
fi

icmp_probe() {
  local address=$1
  if command -v ping >/dev/null 2>&1 && timeout -k 2s 10s ping -4 -c 2 -W 3 "$address" >/dev/null 2>&1; then
    row PASS "icmp:$address" 'IPv4 ICMP probe succeeded'
  else
    row FAIL "icmp:$address" 'IPv4 ICMP probe failed'
  fi
}
icmp_probe 1.1.1.1
icmp_probe 8.8.8.8

# Full-tunnel IPv6 is intentionally fail-closed by the server policy. A default
# route or successful IPv6 connection is a failure, not a skipped capability.
if command -v ip >/dev/null 2>&1; then
  if ip -6 route show default 2>/dev/null | grep -q '^default'; then
    row FAIL ipv6:no-default-route 'an IPv6 default route is present'
  else
    row PASS ipv6:no-default-route 'no IPv6 default route is exposed'
  fi
else
  row SKIP ipv6:no-default-route 'ip is unavailable'
fi

if command -v curl >/dev/null 2>&1; then
  if timeout -k 2s 8s curl -6 --fail --silent --show-error --connect-timeout 3 \
      'https://[2606:4700:4700::1111]/' -o /dev/null; then
    row FAIL ipv6:connectivity-fail-closed 'IPv6 HTTPS unexpectedly succeeded'
  else
    row PASS ipv6:connectivity-fail-closed 'IPv6 HTTPS is blocked as required'
  fi
else
  row SKIP ipv6:connectivity-fail-closed 'curl is unavailable'
fi

if command -v ping >/dev/null 2>&1; then
  if timeout -k 2s 10s ping -6 -c 2 -W 3 2606:4700:4700::1111 >/dev/null 2>&1; then
    row FAIL ipv6:icmp-fail-closed 'IPv6 ICMP unexpectedly succeeded'
  else
    row PASS ipv6:icmp-fail-closed 'IPv6 ICMP is blocked as required'
  fi
else
  row SKIP ipv6:icmp-fail-closed 'ping is unavailable'
fi

printf 'openvpn_client_test_summary PASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"
if (( FAIL > 0 )); then
  exit 1
fi
