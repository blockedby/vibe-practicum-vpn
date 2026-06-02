#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/vercel-dns-failover.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

write_env() {
  cat > "$TMP/private.env" <<'ENV'
VPN_FAILOVER_ENDPOINTS="vibe-practicum moscow-tiger"
VPN_FAILOVER_DOMAIN=vpn.example.invalid
VPN_DNS_RECORD_NAME=vpn
VPN_DNS_EXPECTED_CURRENT=203.0.113.10
VPN_DNS_FAILED_OVER_EXPECTED_CURRENT=203.0.113.20
VPN_DNS_ROLLBACK_TARGET=203.0.113.10
VPN_DNS_TTL=60
VIBE_PRACTICUM_PUBLIC_ENDPOINT=203.0.113.10
VIBE_PRACTICUM_HEALTH=healthy
VIBE_PRACTICUM_LATENCY_MS=100
MOSCOW_TIGER_PUBLIC_ENDPOINT=203.0.113.20
MOSCOW_TIGER_HEALTH=healthy
MOSCOW_TIGER_LATENCY_MS=200
VERCEL_TOKEN=test-token
OPENVPN_PORT=1194
ENV
}
run_script() { LOCAL_ENV="$TMP/private.env" "$SCRIPT" "$@"; }
assert_first() { local want="$1"; shift; local got; got="$(run_script rank | awk 'NR==1{print $1}')"; [[ "$got" == "$want" ]] || { echo "want first $want got $got" >&2; exit 1; }; }

write_env; assert_first vibe-practicum
sed -i 's/VIBE_PRACTICUM_LATENCY_MS=100/VIBE_PRACTICUM_LATENCY_MS=300/; s/MOSCOW_TIGER_LATENCY_MS=200/MOSCOW_TIGER_LATENCY_MS=50/' "$TMP/private.env"; assert_first moscow-tiger
write_env; sed -i 's/MOSCOW_TIGER_LATENCY_MS=200/MOSCOW_TIGER_LATENCY_MS=100/' "$TMP/private.env"; assert_first vibe-practicum
write_env; sed -i 's/VIBE_PRACTICUM_HEALTH=healthy/VIBE_PRACTICUM_HEALTH=down/' "$TMP/private.env"; assert_first moscow-tiger
write_env; sed -i 's/VIBE_PRACTICUM_HEALTH=healthy/VIBE_PRACTICUM_HEALTH=down/; s/MOSCOW_TIGER_HEALTH=healthy/MOSCOW_TIGER_HEALTH=down/' "$TMP/private.env"; if run_script rank >/tmp/rank.out 2>/tmp/rank.err; then echo "both unhealthy should fail" >&2; exit 1; fi
write_env; MOCK_VERCEL_CURRENT=203.0.113.10 run_script dns-plan | grep -q 'mode=read-only/dry-run'
write_env; if MOCK_VERCEL_CURRENT=203.0.113.10 run_script dns-apply --dry-run >/tmp/apply.out 2>/tmp/apply.err; then echo "apply without --yes should fail" >&2; exit 1; fi
MOCK_VERCEL_CURRENT=203.0.113.99 run_script dns-apply --yes --dry-run >/tmp/apply_bad.out 2>/tmp/apply_bad.err && { echo "mismatch should fail" >&2; exit 1; }
MOCK_VERCEL_CURRENT=203.0.113.10 run_script dns-apply --yes --dry-run | grep -q 'DRY-RUN apply'
MOCK_VERCEL_CURRENT=203.0.113.20 run_script dns-rollback --yes --dry-run | grep -q 'DRY-RUN rollback'
cat > "$TMP/client.ovpn" <<'OVPN'
client
remote old.example.invalid 1194 udp
OVPN
run_script ovpn-endpoint --endpoint vpn.example.invalid --input "$TMP/client.ovpn" --output "$TMP/out/client.ovpn" | grep -q 'wrote OpenVPN profile'
grep -q 'remote vpn.example.invalid 1194 udp' "$TMP/out/client.ovpn"
rm "$TMP/private.env"
if LOCAL_ENV="$TMP/private.env" "$SCRIPT" inventory >/tmp/inv.out 2>/tmp/inv.err; then echo "missing local env should fail" >&2; exit 1; fi
printf 'vercel-dns-failover tests passed\n'
