# Plan: sing-box DNS schema migration

## Goal
Migrate tracked sing-box templates and production vpnkit runtime away from deprecated DNS compatibility flags, validate locally, deploy to both production failover endpoints, and smoke-test runtime/profile behavior without printing secrets or private endpoint values.

## Scope
In scope:
- `config/sing-box/config.json.template`
- `config/sing-box/config.tun.json.template`
- Compose/runtime env wiring for deprecated sing-box DNS flags
- repo tests proving rendered configs validate without deprecated DNS compatibility flags
- production vpnkit-only deploy/recreate on known failover endpoints after local evidence
- runtime and OpenVPN profile smoke checks

Out of scope:
- subscription/node changes
- private endpoint/profile disclosure
- unrelated container/service changes

## Acceptance criteria
1. Both tracked sing-box templates use new DNS server schema (`type`/`server`) instead of legacy DNS `address: tls://...`.
2. Route config includes an explicit default domain resolver so `ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER` is not required.
3. Tracked Docker/Compose runtime no longer relies on `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS` or `ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER`.
4. Local tests prove both templates render/check without deprecated DNS compatibility flags.
5. Production endpoints are backed up, updated, recreated/restarted for `vpnkit` only, and pass runtime smoke.
6. User-intended OpenVPN failover profile checks pass for domain and forced endpoint variants, or any blocker is explicit.
7. Final report is public-safe and contains no secrets/private endpoints/rendered configs/raw logs.

## Execution ledger
- Worktree created: `.worktrees/sing-box-dns-schema-migration` on branch `aad/sing-box-dns-schema-migration` from `main`.
- Initial package created.
- Implementation: templates migrated to new DNS `type`/`server`, `route.default_domain_resolver` added, deprecated DNS compat env removed from Compose and Steam Deck podman runtime wiring.
- Local verification: `verification/local.md` passes targeted sing-box schema tests, routing wiring test, shell syntax, `go test ./...`, and temp rendered-config checks with gitignored selected outbound without deprecated DNS env.
- Public-safety check: `verification/public-safety.md`; only match is a redaction regex literal.
- Deployment helper added: `scripts/vpnkit-prod-singbox-dns-migration.sh` with verify/deploy modes, Docker-label workdir discovery, rollback backups, render/check without deprecated DNS env, vpnkit-only recreate, and runtime smoke.
- Local verification refreshed after deployment helper: targeted tests, shell syntax, `go test ./...`, Docker image build, and public-safety grep passed; see `verification/local.md` and `verification/public-safety.md`.
- Design correction: `route.default_domain_resolver` uses `direct-dns` (direct-out TLS resolver) instead of `remote-dns` to avoid cold-start rule-set/bootstrap DNS dependence on the selected outbound. Client DNS still uses `dns.final=remote-dns`.
