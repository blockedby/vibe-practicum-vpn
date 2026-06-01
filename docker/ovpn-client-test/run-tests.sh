#!/usr/bin/env bash
set -euo pipefail
LOG=${VPNKIT_TEST_LOG:-/var/log/vpnkit/ovpn-client-test.log}
mkdir -p "$(dirname "$LOG")"
{
  date -u +%FT%TZ
  ip addr show tun0
  ip route
  # Query an explicit public resolver so DNS traffic traverses the OpenVPN tunnel
  # and can be hijacked by sing-box. Docker's 127.0.0.11 resolver is local to
  # this client container and does not exercise the VPN path.
  dig +time=10 +tries=1 @8.8.8.8 example.com
  curl -4 --fail --max-time 20 https://ifconfig.me -o /dev/null -w 'https-test http_code=%{http_code} remote_ip=%{remote_ip}\n'
  curl -4 --fail --max-time 20 --resolve example.com:443:1.1.1.1 https://example.com/ -o /dev/null -w 'literal-ip-test http_code=%{http_code} remote_ip=%{remote_ip}\n'
} 2>&1 | tee "$LOG"
