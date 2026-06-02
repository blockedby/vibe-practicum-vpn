# Acceptance plan: Vercel DNS failover + OpenVPN endpoint flow

## Scope
Audit the completed `aad/vercel-dns-server-failover-plan` implementation for public-safety, deterministic ranking, read-only Vercel discovery, guarded DNS apply/rollback, OpenVPN endpoint rewrite, smoke/runbook coverage, and operator-input gaps.

## Acceptance criteria to verify
- AC1: Tracked files remain public-safe and contain only placeholders for endpoints/domains/tokens.
- AC2: Vercel discovery and DNS dry-run are read-only and print current/expected/proposed/rollback metadata with redaction.
- AC3: Endpoint ranking is deterministic and selects the faster healthy endpoint first; unhealthy endpoints are excluded.
- AC4: DNS apply requires `--yes`, checks expected-current, and fails closed on mismatch/missing env.
- AC5: DNS rollback uses the same guard model and verifies the failed-over current value before restoring the rollback target.
- AC6: Server deploy/rollback coordination and isolated live-host rules prevent unsafe failover when readiness is unproven.
- AC7: Post-failover smoke docs cover DNS propagation, endpoint health, OpenVPN/client smoke, and rollback smoke.
- AC8: Evidence is fresh and coherent; no live DNS/Vercel/host mutation occurred during this audit.

## Evidence sources
- `scripts/vercel-dns-failover.sh`
- `tests/vercel-dns-failover-test.sh`
- `config/private-endpoints.example.env`
- `docs/VERCEL_DNS_FAILOVER.md`
- `README.md`
- fresh local checks: `tests/vercel-dns-failover-test.sh`, `bash -n scripts/*.sh`, `git diff --check`, `git status --short`

## Audit decision rule
Accept if all ACs are supported by fresh evidence or an explicit boundary/limitation, with no public-safety leak or live-mutation evidence.
