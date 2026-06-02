#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
setup_routing="$repo_root/docker/vpnkit/setup-routing.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack=$1
  local needle=$2
  if ! grep -Fq -- "$needle" <<<"$haystack"; then
    fail "expected rendered rules to contain: $needle"
  fi
}

assert_not_contains() {
  local haystack=$1
  local needle=$2
  if grep -Fq -- "$needle" <<<"$haystack"; then
    fail "rendered rules unexpectedly contained: $needle"
  fi
}

render=$(
  VPNKIT_ROUTING_DRY_RUN=true \
  VPNKIT_ROUTING_MODE=redirect \
  VPNKIT_COMPAT_BYPASS_ENABLED=true \
  VPNKIT_COMPAT_BYPASS_ENDPOINTS="198.51.100.10:1194,203.0.113.20:443/tcp" \
  VPNKIT_COMPAT_BYPASS_ALLOW_ICMP=true \
  bash "$setup_routing"
)

assert_contains "$render" "-A OVPN_REDIRECT_TO_SINGBOX -d 198.51.100.10 -p udp --dport 1194 -j RETURN"
assert_contains "$render" "-A OVPN_REDIRECT_TO_SINGBOX -d 203.0.113.20 -p tcp --dport 443 -j RETURN"
assert_contains "$render" "-A OVPN_REDIRECT_TO_SINGBOX -p tcp -j REDIRECT --to-ports 2082"
assert_contains "$render" "-A OVPN_REDIRECT_TO_SINGBOX -p udp --dport 53 -j REDIRECT --to-ports 5353"
assert_contains "$render" "-A OVPN_COMPAT_POST -d 198.51.100.10 -p udp --dport 1194 -j MASQUERADE"
assert_contains "$render" "-A OVPN_COMPAT_POST -d 203.0.113.20 -p tcp --dport 443 -j MASQUERADE"
assert_contains "$render" "-A OVPN_REDIRECT_TO_SINGBOX -d 198.51.100.10 -p icmp -j RETURN"
assert_contains "$render" "-A OVPN_COMPAT_POST -d 198.51.100.10 -p icmp -j MASQUERADE"
assert_not_contains "$render" "-A POSTROUTING -s 10.89.0.0/24 -j MASQUERADE"

if VPNKIT_ROUTING_DRY_RUN=true \
  VPNKIT_ROUTING_MODE=redirect \
  VPNKIT_COMPAT_BYPASS_ENABLED=true \
  VPNKIT_COMPAT_BYPASS_ENDPOINTS="198.51.100.10:1194/sctp" \
  bash "$setup_routing" >/tmp/vpnkit-invalid-proto.out 2>&1; then
  fail "invalid protocol unexpectedly succeeded"
fi
assert_contains "$(cat /tmp/vpnkit-invalid-proto.out)" "invalid compatibility bypass proto"
rm -f /tmp/vpnkit-invalid-proto.out

if VPNKIT_ROUTING_DRY_RUN=true \
  VPNKIT_ROUTING_MODE=redirect \
  VPNKIT_COMPAT_BYPASS_ENABLED=true \
  VPNKIT_COMPAT_BYPASS_ENDPOINTS="udp://198.51.100.10:1194/tcp" \
  bash "$setup_routing" >/tmp/vpnkit-conflicting-proto.out 2>&1; then
  fail "conflicting protocol unexpectedly succeeded"
fi
assert_contains "$(cat /tmp/vpnkit-conflicting-proto.out)" "conflicting compatibility bypass proto"
rm -f /tmp/vpnkit-conflicting-proto.out

echo "vpnkit routing compatibility bypass render tests passed"
