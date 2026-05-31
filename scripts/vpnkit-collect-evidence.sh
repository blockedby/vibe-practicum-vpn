#!/usr/bin/env bash
set -euo pipefail
OUT=${1:-logs/vpnkit-evidence-$(date -u +%Y%m%dT%H%M%SZ).txt}
mkdir -p "$(dirname "$OUT")"
{
  date -u +%FT%TZ
  docker compose ps
  docker compose exec -T vpnkit ip addr show tun0 || true
  docker compose exec -T vpnkit ip rule show || true
  docker compose exec -T vpnkit ip route show table 100 || true
  docker compose exec -T vpnkit iptables -t mangle -L OVPN_TO_SINGBOX -v -n -x || true
  docker compose logs --no-color --tail=200 vpnkit | sed -E 's/([0-9a-f]{8}-[0-9a-f-]{27,})/[redacted-uuid]/ig'
  docker compose logs --no-color --tail=200 ovpn-client-test || true
} > "$OUT"
echo "$OUT"
