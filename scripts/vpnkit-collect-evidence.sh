#!/usr/bin/env bash
set -euo pipefail
OUT=${1:-logs/vpnkit-evidence-$(date -u +%Y%m%dT%H%M%SZ).txt}
mkdir -p "$(dirname "$OUT")"
redact() {
  sed -E \
    -e 's#vless://[^[:space:]]+#vless://[redacted]#g' \
    -e 's#(https?://)[^[:space:]]*(token|sub|subscription|api_key|apikey|key)[^[:space:]]*#\1[redacted-url]#ig' \
    -e 's/([0-9a-f]{8}-[0-9a-f-]{27,})/[redacted-uuid]/ig' \
    -e 's/(private[_-]?key[":= ]+)[^", ]+/\1[redacted]/ig' \
    -e 's/(password[":= ]+)[^", ]+/\1[redacted]/ig'
}
{
  date -u +%FT%TZ
  docker compose ps
  echo '--- vpnkit tun0 ---'
  docker compose exec -T vpnkit ip addr show tun0 || true
  echo '--- vpnkit routing ---'
  docker compose exec -T vpnkit ip rule show || true
  docker compose exec -T vpnkit ip route show table 100 || true
  docker compose exec -T vpnkit ip route show table 101 || true
  echo '--- vpnkit redirect counters ---'
  docker compose exec -T vpnkit iptables -t nat -L OVPN_REDIRECT_TO_SINGBOX -v -n -x || true
  echo '--- vpnkit tproxy counters (if mode=tproxy) ---'
  docker compose exec -T vpnkit iptables -t mangle -L OVPN_TO_SINGBOX -v -n -x || true
  echo '--- vpnkit listeners ---'
  docker compose exec -T vpnkit ss -lntup || true
  echo '--- vpnkit vibe-vpn binary ---'
  docker compose exec -T vpnkit /usr/local/bin/vibe-vpn --help 2>&1 | head -40 || true
  echo '--- vpnkit vibe-vpn doctor ---'
  docker compose exec -T vpnkit /usr/local/bin/vibe-vpn doctor --config /etc/vibe-vpn/config.yaml 2>&1 | redact || true
  echo '--- vpnkit logs ---'
  docker compose logs --no-color --tail=240 vpnkit | redact
  echo '--- ovpn-client-test logs ---'
  docker compose logs --no-color --tail=240 ovpn-client-test 2>/dev/null | redact || true
} > "$OUT"
echo "$OUT"
