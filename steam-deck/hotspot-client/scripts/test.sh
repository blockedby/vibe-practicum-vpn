#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

ping_probe(){
  local target=$1
  if ping -4 -c 1 -W 1 "$target" >/dev/null 2>&1; then
    ping -4 -c 3 -W 3 "$target" || true
  else
    ping -c 3 -W 3 "$target" || true
  fi
}

dns_probe(){
  local host=$1
  if command -v dig >/dev/null 2>&1; then
    dig +time=8 +tries=1 @8.8.8.8 "$host" A || true
  elif command -v nslookup >/dev/null 2>&1; then
    nslookup "$host" 8.8.8.8 || true
  elif command -v resolvectl >/dev/null 2>&1; then
    resolvectl query "$host" || echo "dns_${host}=fail"
  elif command -v getent >/dev/null 2>&1; then
    getent hosts "$host" || echo "dns_${host}=fail"
  else
    echo "dns_${host}=skip no_host_dns_tool"
  fi
}

curl_ip_hash(){
  local name=$1 url=$2 body rc
  body=$(curl -4fsS --max-time 20 "$url" 2>/tmp/${name}.err) && rc=0 || rc=$?
  if [[ $rc -ne 0 ]]; then
    printf '%s=fail rc=%s detail=' "$name" "$rc"
    tail -1 /tmp/${name}.err 2>/dev/null | redact || true
    printf '\n'
    return 0
  fi
  printf '%s=ok hash=%s\n' "$name" "$(hash8 "$body")"
}

REPORT=$(new_report_path test)
{
  write_header "Steam Deck host OpenVPN client test"
  preflight_common
  log "container status"
  podman_cmd ps --filter "name=^${CONTAINER}$" --format 'container={{.Names}} status={{.Status}} image={{.Image}}' || true
  if ip link show "$VPN_IFACE" >/dev/null 2>&1; then
    echo "vpn_iface=present"
    ip -br addr show "$VPN_IFACE" || true
  else
    echo "vpn_iface=missing"
  fi
  echo "route_checks_start"
  ip route get 1.1.1.1 || true
  ip route get 8.8.8.8 || true
  echo "icmp_checks_start"
  ping_probe 1.1.1.1
  ping_probe 8.8.8.8
  echo "dns_checks_start"
  dns_probe x.com
  dns_probe ya.ru
  dns_probe www.linkedin.com
  echo "ip_identity_checks_start"
  curl_ip_hash ip_ifconfig_me https://ifconfig.me
  curl_ip_hash ip_api_ipify https://api.ipify.org
  echo "https_access_checks_start"
  curl -4fsS --max-time 20 https://x.com/ -o /dev/null -w 'access_x_com=ok http_code=%{http_code}\n' || echo "access_x_com=fail"
  curl -4fsS --max-time 20 https://ya.ru/ -o /dev/null -w 'access_ya_ru=ok http_code=%{http_code}\n' || echo "access_ya_ru=fail"
  curl -4fsS --max-time 20 https://www.linkedin.com/ -o /dev/null -w 'access_linkedin_com=ok http_code=%{http_code}\n' || echo "access_linkedin_com=fail"
} 2>&1 | redact | tee "$REPORT"
echo "report_path=$REPORT"
