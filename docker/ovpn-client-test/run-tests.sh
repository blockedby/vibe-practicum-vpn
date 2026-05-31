#!/usr/bin/env bash
set -euo pipefail
LOG=${VPNKIT_TEST_LOG:-/var/log/vpnkit/ovpn-client-test.log}
mkdir -p "$(dirname "$LOG")"
{
  date -u +%FT%TZ
  ip addr show tun0
  ip route
  getent hosts example.com || true
  dig +time=10 +tries=1 example.com || true
  curl -4 --max-time 20 https://ifconfig.me || true
  curl -4 --max-time 20 --resolve example.com:443:1.1.1.1 https://example.com/ -o /dev/null -w 'literal-ip-test http_code=%{http_code} remote_ip=%{remote_ip}\n' || true
} 2>&1 | tee "$LOG"
