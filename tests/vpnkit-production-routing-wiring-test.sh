#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
entrypoint="$repo_root/docker/vpnkit/entrypoint.sh"
compose="$repo_root/docker-compose.yml"
docs="$repo_root/docs/DOCKER_SETUP.md"

require_literal() {
  local file=$1
  local literal=$2
  local description=$3
  if ! grep -Fq -- "$literal" "$file"; then
    echo "missing $description in ${file#$repo_root/}: $literal" >&2
    return 1
  fi
}

require_regex() {
  local file=$1
  local regex=$2
  local description=$3
  if ! grep -Eq -- "$regex" "$file"; then
    echo "missing $description in ${file#$repo_root/}: $regex" >&2
    return 1
  fi
}

require_literal "$entrypoint" 'mode=${VPNKIT_ROUTING_MODE:-redirect}' 'routing-mode default in readiness function'
require_literal "$entrypoint" 'tun) singbox_tun_ready ;;' 'tun readiness branch'
require_literal "$entrypoint" 'tproxy) singbox_tcp_ready 2082 ;;' 'tproxy readiness branch'
require_literal "$entrypoint" 'redirect|*) singbox_tcp_ready 2082 && singbox_udp_ready 5353 ;;' 'redirect readiness branch'
require_literal "$entrypoint" 'ip link show "$iface" >/dev/null 2>&1' 'tun link visibility check'
require_literal "$entrypoint" '/usr/local/bin/setup-routing.sh' 'routing setup call after readiness'

restart_block=$(awk '/^restart_singbox\(\) \{/{flag=1} flag{print} flag && /^\}/{exit}' "$entrypoint")
if ! grep -Fq 'start_singbox' <<<"$restart_block" \
  || ! grep -Fq 'wait_for_singbox_inbounds' <<<"$restart_block" \
  || ! grep -Fq '/usr/local/bin/setup-routing.sh' <<<"$restart_block"; then
  echo 'restart_singbox must start sing-box, wait for mode-aware readiness, then setup routing' >&2
  exit 1
fi

require_literal "$compose" 'OVPN_CIDR: "${OVPN_CIDR:-10.89.0.0/24}"' 'compose OVPN_CIDR public-safe default with override'
require_literal "$docs" 'VPNKIT_ROUTING_MODE=redirect' 'redirect-mode consistency docs mode'
require_literal "$docs" 'redirect inbound on TCP `2082` and DNS' 'redirect-mode consistency docs inbounds'
require_literal "$docs" 'OVPN_CIDR' 'OVPN_CIDR compose override docs'
require_literal "$repo_root/scripts/vpnkit-render-local-configs.sh" 'tun) singbox_template=config/sing-box/config.tun.json.template ;;' 'tun render template selection'
require_literal "$repo_root/config/sing-box/config.tun.json.template" '"type": "tun"' 'tun inbound template'
require_literal "$repo_root/config/sing-box/config.tun.json.template" '"interface_name": "sb-tun0"' 'tun interface matches routing default'
require_literal "$repo_root/config/sing-box/config.tun.json.template" '"address": ["172.19.0.1/30"]' 'tun address matches routing peer default'
require_literal "$repo_root/config/sing-box/config.tun.json.template" '"auto_route": false' 'tun template leaves route policy to setup-routing'
require_literal "$repo_root/docker/vpnkit/setup-routing.sh" 'ensure_iptables_rule filter FORWARD -i tun0 -o "$TUN_IFACE" -s "$OVPN_CIDR" -j ACCEPT' 'tun forward allow from OpenVPN to sing-box TUN'
require_literal "$repo_root/docker/vpnkit/setup-routing.sh" 'ensure_iptables_rule filter FORWARD -i "$TUN_IFACE" -o tun0 -d "$OVPN_CIDR" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT' 'tun forward return allow to OpenVPN'

require_literal "$repo_root/config/sing-box/config.json.template" '"type": "tls"' 'redirect template new DNS server schema'
require_literal "$repo_root/config/sing-box/config.tun.json.template" '"type": "tls"' 'tun template new DNS server schema'
require_literal "$repo_root/config/sing-box/config.json.template" '"default_domain_resolver": "remote-dns"' 'redirect template explicit domain resolver'
require_literal "$repo_root/config/sing-box/config.tun.json.template" '"default_domain_resolver": "remote-dns"' 'tun template explicit domain resolver'
if grep -R -n 'ENABLE_DEPRECATED_LEGACY_DNS_SERVERS\|ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER' "$compose" "$repo_root/scripts/vpnkit-steamdeck-podman.sh" "$repo_root/config/sing-box" >/tmp/vpnkit-deprecated-dns-env.out; then
  cat /tmp/vpnkit-deprecated-dns-env.out >&2
  echo 'deprecated sing-box DNS compatibility env must not be required by tracked vpnkit runtime wiring' >&2
  exit 1
fi

echo 'vpnkit production routing wiring tests passed'
