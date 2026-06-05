#!/usr/bin/env bash
set -euo pipefail

LOG=${VPNKIT_PROFILE_CHECK_LOG:-/var/log/vpnkit/ovpn-profile-check.log}
CURL_TIMEOUT=${VPNKIT_PROFILE_CHECK_TIMEOUT:-25}
DNS_SERVER=${VPNKIT_PROFILE_CHECK_DNS_SERVER:-8.8.8.8}
mkdir -p "$(dirname "$LOG")"

hash8() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -c1-8
  else
    printf 'unavailable'
  fi
}

redact_ips() {
  sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g'
}

curl_probe() {
  local name="$1" url="$2" extra_args=()
  shift 2
  extra_args=("$@")
  local out rc
  out=$(curl -4fsS --max-time "$CURL_TIMEOUT" "${extra_args[@]}" "$url" -o /dev/null -w 'http_code=%{http_code} remote_ip_hash=%{remote_ip}\n' 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    local code remote raw_remote
    code=$(printf '%s' "$out" | sed -n 's/.*http_code=\([0-9][0-9][0-9]\).*/\1/p' | tail -1)
    raw_remote=$(printf '%s' "$out" | sed -n 's/.*remote_ip_hash=\([^[:space:]]*\).*/\1/p' | tail -1)
    remote="unavailable"
    [[ -n "$raw_remote" ]] && remote=$(hash8 "$raw_remote")
    printf '%s=ok http_code=%s remote_ip_hash=%s\n' "$name" "${code:-unknown}" "$remote"
  else
    printf '%s=fail rc=%s detail=' "$name" "$rc"
    printf '%s' "$out" | tail -1 | redact_ips
    printf '\n'
  fi
}

ip_probe() {
  local name="$1" url="$2"
  local body rc ips first
  body=$(curl -4fsS --max-time "$CURL_TIMEOUT" "$url" 2>/tmp/${name}.err) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    printf '%s=fail rc=%s detail=' "$name" "$rc"
    tail -1 /tmp/${name}.err 2>/dev/null | redact_ips || true
    printf '\n'
    return 0
  fi
  ips=$(printf '%s\n' "$body" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -5 || true)
  first=$(printf '%s\n' "$ips" | head -1)
  if [[ -n "$first" ]]; then
    printf '%s=ok ip_hash=%s ip_count=%s\n' "$name" "$(hash8 "$first")" "$(printf '%s\n' "$ips" | sed '/^$/d' | wc -l | tr -d ' ')"
  else
    printf '%s=ok ip_hash=unavailable ip_count=0 body_hash=%s\n' "$name" "$(hash8 "$body")"
  fi
}

route_probe() {
  local name="$1" target="$2"
  local route dev
  route=$(ip -4 route get "$target" 2>/tmp/${name}.err | head -1) || {
    printf '%s=fail detail=' "$name"
    tail -1 /tmp/${name}.err 2>/dev/null | redact_ips || true
    printf '\n'
    return 0
  }
  dev=$(printf '%s\n' "$route" | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')
  printf '%s=ok dev=%s route=' "$name" "${dev:-unknown}"
  printf '%s\n' "$route" | redact_ips
}

ping_probe() {
  local name="$1" target="$2"
  local out rc loss avg
  out=$(ping -4 -c 3 -W 3 "$target" 2>&1) && rc=0 || rc=$?
  loss=$(printf '%s\n' "$out" | sed -n 's/.* \([0-9.]*%\) packet loss.*/\1/p' | tail -1)
  avg=$(printf '%s\n' "$out" | awk -F'/' '/rtt|round-trip/ {print $5; exit}')
  if [[ "$rc" -eq 0 ]]; then
    printf '%s=ok loss=%s avg_ms=%s\n' "$name" "${loss:-unknown}" "${avg:-unknown}"
  else
    printf '%s=fail rc=%s loss=%s detail=' "$name" "$rc" "${loss:-unknown}"
    printf '%s\n' "$out" | tail -1 | redact_ips
  fi
}

{
  echo "timestamp=$(date -u +%FT%TZ)"
  if ip -4 addr show tun0 >/dev/null 2>&1; then
    tun_cidr=$(ip -4 addr show tun0 | sed -n 's/.*inet \([^ ]*\).*/\1/p' | head -1)
    echo "tun0=present cidr_hash=$(hash8 "$tun_cidr")"
  else
    echo "tun0=missing"
  fi
  split_routes=$(ip route | grep -E '^(0\.0\.0\.0/1|128\.0\.0\.0/1)' | wc -l | tr -d ' ')
  echo "split_default_routes=$split_routes"
  echo "route_checks_start"
  route_probe "route_to_1_1_1_1" "1.1.1.1"
  route_probe "route_to_8_8_8_8" "8.8.8.8"

  echo "icmp_checks_start"
  ping_probe "ping_1_1_1_1" "1.1.1.1"
  ping_probe "ping_8_8_8_8" "8.8.8.8"

  echo "dns_checks_start"
  if dig +time=10 +tries=1 @"$DNS_SERVER" example.com A >/tmp/dig-example.out 2>&1; then
    echo "dns_example_via_${DNS_SERVER}=ok"
  else
    echo "dns_example_via_${DNS_SERVER}=fail"
    tail -8 /tmp/dig-example.out | redact_ips
  fi
  if dig +time=10 +tries=1 @"$DNS_SERVER" x.com A >/tmp/dig-x.out 2>&1; then
    echo "dns_x_via_${DNS_SERVER}=ok"
  else
    echo "dns_x_via_${DNS_SERVER}=fail"
    tail -8 /tmp/dig-x.out | redact_ips
  fi
  if dig +time=10 +tries=1 @"$DNS_SERVER" ya.ru A >/tmp/dig-ya.out 2>&1; then
    echo "dns_ya_via_${DNS_SERVER}=ok"
  else
    echo "dns_ya_via_${DNS_SERVER}=fail"
    tail -8 /tmp/dig-ya.out | redact_ips
  fi
  if dig +time=10 +tries=1 @"$DNS_SERVER" www.linkedin.com A >/tmp/dig-linkedin.out 2>&1; then
    echo "dns_linkedin_via_${DNS_SERVER}=ok"
  else
    echo "dns_linkedin_via_${DNS_SERVER}=fail"
    tail -8 /tmp/dig-linkedin.out | redact_ips
  fi

  echo "http_access_checks_start"
  curl_probe "access_x_com" "https://x.com/"
  curl_probe "access_ya_ru" "https://ya.ru/"
  curl_probe "access_linkedin_com" "https://www.linkedin.com/"

  echo "ip_identity_checks_start"
  ip_probe "ip_ifconfig_me" "https://ifconfig.me"
  ip_probe "ip_api_ipify" "https://api.ipify.org"
  # Yandex Internetometer is intentionally public test evidence. The HTML shape
  # changes, so report the first IPv4-looking value hash when present.
  ip_probe "ip_yandex_internetometer" "https://yandex.ru/internet/"

  echo "ipv6_leak_check_start"
  ipv6_body=$(curl -6fsS --max-time 8 https://ifconfig.me 2>/tmp/ipv6.err || true)
  if [[ -n "$ipv6_body" ]]; then
    echo "ipv6_public=present body_hash=$(hash8 "$ipv6_body")"
  else
    echo "ipv6_public=none_or_unreachable"
  fi

  echo "literal_ip_https_check_start"
  curl_probe "access_one_one_one_one_literal" "https://one.one.one.one/cdn-cgi/trace" --resolve one.one.one.one:443:1.1.1.1
} 2>&1 | tee "$LOG"
