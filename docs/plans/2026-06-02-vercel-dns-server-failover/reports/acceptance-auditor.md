## Task package
- Task name: Vercel DNS failover + OpenVPN endpoint flow
- Task package: `docs/plans/2026-06-02-vercel-dns-server-failover/`
- Report path: `docs/plans/2026-06-02-vercel-dns-server-failover/reports/acceptance-auditor.md`
- Acceptance plan path: `docs/plans/2026-06-02-vercel-dns-server-failover/verification/acceptance-plan.md`

## Acceptance verdict
- Status: accepted with limitations
- Summary: The branch has fresh, public-safe dry-run/mock evidence for ranking, discovery, guarded apply/rollback, OpenVPN rewrite, and smoke/runbook coverage; live Vercel mutation remains intentionally disabled and still needs operator-local inputs/approval.

## Acceptance coverage
- AC1: Public safety / no private endpoint leakage
  - Evidence present: `config/private-endpoints.example.env`, `docs/VERCEL_DNS_FAILOVER.md`, and fresh grep checks over the task package / changed files.
  - Result: passed
  - Gap: none in tracked files; placeholders are used for public-safe docs.
- AC2: Endpoint inventory from gitignored env
  - Evidence present: `scripts/vercel-dns-failover.sh inventory` / `load_env` guard plus missing-env test case in `tests/vercel-dns-failover-test.sh`.
  - Result: passed
  - Gap: live inventory still needs `config/private-endpoints.local.env` populated by the operator.
- AC3: Deterministic health/speed ranking
  - Evidence present: `tests/vercel-dns-failover-test.sh` covers primary faster, secondary faster, tie, one unhealthy, both unhealthy; script sorts by latency then inventory order.
  - Result: passed
  - Gap: none.
- AC4: OpenVPN endpoint rewrite/generation to untracked paths
  - Evidence present: `ovpn-endpoint` in `scripts/vercel-dns-failover.sh`, temp-dir rewrite test, and runbook examples in `docs/VERCEL_DNS_FAILOVER.md`.
  - Result: passed
  - Gap: live client smoke remains operator-run and must stay in temp/gitignored output paths.
- AC5: Vercel DNS read-only discovery and dry-run expected-current checks
  - Evidence present: `dns-discover` / `dns-plan` output in script, dry-run case in `tests/vercel-dns-failover-test.sh`, and documented `MOCK_VERCEL_CURRENT` / `VERCEL_DNS_CURRENT_CMD` inputs.
  - Result: passed
  - Gap: exact live current-record source is still operator-local.
- AC6: Guarded apply/rollback with explicit `--yes` but no live apply
  - Evidence present: `dns-apply` / `dns-rollback` guards in script, no-`--yes` and mismatch tests, plus intentional live-mutation fail-closed paths.
  - Result: passed with limitation
  - Gap: live Vercel mutation is intentionally unwired in this branch and requires future operator approval/wiring.
- AC7: Post-failover smoke commands/docs including isolated live-host test rule
  - Evidence present: `smoke-plan` output and `docs/VERCEL_DNS_FAILOVER.md` smoke checklist / isolated throwaway-container rule.
  - Result: passed
  - Gap: none for docs/dry-run scope.
- AC8: Tests/docs evidence and remaining operator inputs
  - Evidence present: `tests/vercel-dns-failover-test.sh`, `bash -n scripts/*.sh`, `git diff --check`, `go test ./...`, and `verification/implementation-local.md`.
  - Result: passed
  - Gap: no live DNS/Vercel/host mutation was performed, by design.

## System readiness coverage
- Routes / registration: not relevant
- Services / APIs: not relevant
- Config / env / secrets: covered for public-safe contract; operator-local env still required for live use
- Permissions / access: partially covered; live Vercel access/current-record source remains operator input
- Database / migrations: not relevant
- Frontend-backend integration: not relevant
- Runtime / deployment wiring: covered for dry-run/mock planning and documented stop conditions; live mutation remains disabled

## Check freshness
- Targeted checks: fresh
  - `tests/vercel-dns-failover-test.sh` — passed
  - `bash -n scripts/*.sh` — passed
  - `git diff --check` — passed
  - `git status --short` — clean
- Full local checks: fresh
  - `go test ./...` — passed (per implementation-local evidence)
- Remote checks / CI: not available before push

## Required before done
- No repo changes required for the scoped acceptance.
- For any future live Vercel DNS execution, the operator must provide a populated `config/private-endpoints.local.env`, a read-only current-record source (`VERCEL_DNS_CURRENT_CMD` or equivalent), and explicit approval to wire/run live mutation.

## Files written
- `docs/plans/2026-06-02-vercel-dns-server-failover/verification/acceptance-plan.md`: created
- `docs/plans/2026-06-02-vercel-dns-server-failover/reports/acceptance-auditor.md`: created
