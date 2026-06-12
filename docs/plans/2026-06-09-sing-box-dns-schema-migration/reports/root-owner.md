## Task
- Mission: migrate vpnkit sing-box DNS config to the new schema, remove deprecated DNS compatibility env reliance, deploy to both production VPN endpoints, and smoke-test.
- Target: sing-box templates, vpnkit runtime wiring, production `vpnkit` containers, OpenVPN profile checks.
- Boundaries: no secrets/private endpoints/rendered configs/profile contents printed; mutate only production `vpnkit` after local acceptance and rollback prep.
- Done when: branch/PR ready, local checks pass, both prod endpoints pass runtime smoke, profile smoke passes, limitations recorded.

## Context
- Branch: `aad/sing-box-dns-schema-migration`
- Worktree: `.worktrees/sing-box-dns-schema-migration`
- PR: https://github.com/blockedby/vibe-practicum-vpn/pull/25 (`ready for review`, mergeable clean, no status checks configured)
- Task package: `docs/plans/2026-06-09-sing-box-dns-schema-migration`

## Spec compliance
- New DNS schema: done. `config/sing-box/config.json.template` and `config/sing-box/config.tun.json.template` use `type`/`server` for remote DNS and no legacy `address: tls://...`.
- Explicit domain resolver: done. `route.default_domain_resolver` uses `direct-dns`; `direct-dns` is `type: local` to avoid selected-outbound/bootstrap loops and direct DoT/853 dependence.
- Deprecated env removal: done. `docker-compose.yml` and `scripts/vpnkit-steamdeck-podman.sh` no longer set `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS` or `ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER`.
- Deployment helper: done. `scripts/vpnkit-prod-singbox-dns-migration.sh` discovers Compose labels, backs up rollback refs, renders/checks config without deprecated env, recreates only `vpnkit`, and runs runtime smoke.
- PR state: done. PR #25 opened and marked ready.

## Acceptance verification
- AC1/AC2 templates migrated and resolver explicit: passed via `test/sing-box-dns-schema-test.sh` and `test/vpnkit-production-routing-wiring-test.sh`.
- AC3 no deprecated DNS env reliance: passed locally and in prod (`deprecated_env=absent` on both endpoints).
- AC4 local verification: passed in `verification/local-final.md`: schema test, routing wiring test, `bash -n`, `go test ./...`, Docker build.
- AC5 production runtime: passed in `verification/production-runtime-final-verify.md`: both endpoints `singbox_check=ok`, `routing_mode=tun`, OpenVPN/tun0 up, sing-box/sb-tun0 up, policy rule/route table ok, UDP 1194 mapped/listening.
- AC6 OpenVPN profile smoke: passed in `verification/profile-smoke-final.md` for domain, endpoint1 forced, endpoint2 forced: OpenVPN ready, route via tun0, DNS OK, HTTPS OK, literal-IP HTTPS OK, pings OK with 0% loss.
- AC7 public safety: passed in `verification/public-safety-final.md`; no secret/private endpoint matches.

## System readiness
- Runtime/deployment wiring: ready. Both prod endpoints running without deprecated DNS compatibility env.
- Rollback: prepared per deploy. Latest sanitized rollback refs include `vpnkit-rollback:20260609T142256Z` for first endpoint and `vpnkit-rollback:20260609T142100Z` for second endpoint, plus `.rollback/vpnkit/singbox-dns-<timestamp>/env` and runtime-config backups.
- CI: no GitHub status checks configured for PR #25.

## Issues
### R-01: `sing-box check` missed runtime-invalid direct DNS detour
- Evidence: final redeploy initially caused restart loop because `direct-dns` had `detour: direct-out`; sing-box start rejected it.
- Resolution: changed `direct-dns` to `type: local` and added startup smoke to `test/sing-box-dns-schema-test.sh`.

### R-02: direct DoT bootstrap resolver was not portable
- Evidence: one endpoint could not reach direct TLS DNS on 853 during rule-set bootstrap.
- Resolution: switched bootstrap resolver to local/system DNS (`type: local`) while keeping client DNS final as `remote-dns`.

### U-01: nested VPN-over-VPN disposable data-path not fully proven
- Evidence: outer OpenVPN and sing-box startup/check pass; a forced temp client TUN route did not fully capture through `sb-tun0`, and DNS/hostname HTTPS failed while ping/literal-IP HTTPS passed.
- Why not blocking: production migration and user profile acceptance pass on both endpoints; acceptance auditor accepted with this limitation.
- Needed next: separate nested-client routing diagnostic/fix if VPN-over-VPN client behavior remains a goal.

## Verdict
- Status: success with limitation.
- Production readiness: ready.
- Summary: New sing-box DNS schema is deployed on both production VPN endpoints without deprecated DNS env reliance; base full-tunnel OpenVPN profile acceptance passes. Nested VPN-over-VPN remains a separate diagnostic limitation.
