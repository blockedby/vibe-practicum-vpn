# Vercel DNS failover + OpenVPN endpoint flow

Public-safe automation lives in `scripts/vercel-dns-failover.sh`. It is designed for dry-run/read-only planning first. Real endpoints, domains, Vercel tokens, and expected-current values belong only in `config/private-endpoints.local.env`, copied from `config/private-endpoints.example.env`.

## Operator inputs

Required local env values:

- `VPN_FAILOVER_ENDPOINTS` — ordered endpoint names, for example placeholders `vibe-practicum moscow-tiger`.
- `<NAME>_PUBLIC_ENDPOINT`, `<NAME>_HEALTH`, `<NAME>_LATENCY_MS` — endpoint inventory and fixture/probe result fields. Names are uppercased and `-` becomes `_`.
- `VPN_FAILOVER_DOMAIN`, `VPN_DNS_RECORD_NAME`, `VPN_DNS_TTL`.
- `VPN_DNS_EXPECTED_CURRENT` for apply and `VPN_DNS_FAILED_OVER_EXPECTED_CURRENT` / `VPN_DNS_ROLLBACK_TARGET` for rollback.
- `VERCEL_TOKEN` and a read-only current-record source such as `MOCK_VERCEL_CURRENT` for tests or an operator-provided `VERCEL_DNS_CURRENT_CMD`.

If the local env file is missing or a required value is empty, commands fail closed before live mutation.

## Health and speed ranking

```bash
LOCAL_ENV=config/private-endpoints.local.env scripts/vercel-dns-failover.sh rank
```

Only endpoints marked `healthy`/`ok` are eligible. Lower latency sorts first; ties keep the inventory order. If both endpoints are unhealthy, the command refuses to select a failover target.

## Read-only Vercel DNS discovery and dry-run

```bash
LOCAL_ENV=config/private-endpoints.local.env \
  MOCK_VERCEL_CURRENT="$VPN_DNS_EXPECTED_CURRENT" \
  scripts/vercel-dns-failover.sh dns-plan
```

The summary redacts current/proposed/rollback values and includes expected-current and TTL metadata. It does not mutate DNS.

## Guarded apply and rollback contract

Mutating commands are guarded and must not be run live without a future explicit operator approval. They require `--yes`, required local env, a current DNS value equal to expected-current, and credentials. The current implementation supports dry-run/mock evidence and otherwise fails closed instead of performing live Vercel mutation.

```bash
# Mocked/dry-run apply evidence only.
LOCAL_ENV=config/private-endpoints.local.env MOCK_VERCEL_CURRENT="$VPN_DNS_EXPECTED_CURRENT" \
  scripts/vercel-dns-failover.sh dns-apply --yes --dry-run

# Mocked/dry-run rollback evidence only.
LOCAL_ENV=config/private-endpoints.local.env MOCK_VERCEL_CURRENT="$VPN_DNS_FAILED_OVER_EXPECTED_CURRENT" \
  scripts/vercel-dns-failover.sh dns-rollback --yes --dry-run
```

Rollback symmetry: rollback requires the live/current DNS value to equal `VPN_DNS_FAILED_OVER_EXPECTED_CURRENT` before restoring `VPN_DNS_ROLLBACK_TARGET`.

## OpenVPN endpoint profile flow

Use the stable failover domain when available, or the currently selected endpoint for a temporary profile. Generated profiles must be written to a temp or gitignored output directory; tracked `*.ovpn` files are ignored by policy.

```bash
# Print a remote line.
LOCAL_ENV=config/private-endpoints.local.env scripts/vercel-dns-failover.sh ovpn-endpoint --endpoint "$VPN_FAILOVER_DOMAIN"

# Rewrite a template/profile to an untracked path.
LOCAL_ENV=config/private-endpoints.local.env \
  scripts/vercel-dns-failover.sh ovpn-endpoint \
  --endpoint "$VPN_FAILOVER_DOMAIN" \
  --input /path/to/client-template.ovpn \
  --output /tmp/vpnkit-client.ovpn
```

## Post-failover smoke checklist

```bash
scripts/vercel-dns-failover.sh smoke-plan
```

Smoke evidence should include sanitized pass/fail summaries for:

1. DNS propagation and TTL behavior.
2. Selected endpoint health and rollback target health.
3. OpenVPN/client connectivity using generated material only in temp or gitignored paths.
4. Routing health through public allowed health URLs.
5. Rollback dry-run and future approved rollback apply evidence.

Live-host tests or experiments must use isolated throwaway containers with distinct names, Compose projects, ports, networks, volumes, and state directories. Never restart, recreate, adopt, or otherwise mutate the production `vpnkit` container except for an explicit approved deploy/rollback/maintenance action with rollback and post-change smoke tests.
