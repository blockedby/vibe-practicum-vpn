## Task package
- Task name: Production Docker deploy/rollback tooling
- Task package: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling`
- Report path: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/reports/acceptance-auditor.md`
- Acceptance plan path: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/verification/acceptance-plan.md`

## Acceptance verdict
- Status: accepted with limitations
- Summary: Repo-safe deploy/rollback tooling is evidenced by the tracked helper, docs, and local checks; AC3 and AC8 remain only partially evidenced, and no live production mutation was exercised.

## Acceptance coverage
- AC1: tracked helper with safe plan/dry-run/deploy/rollback/verify; mutating commands refuse without `--yes`
  - Evidence present: code + local tests/checks
  - Result: passed
  - Gap: none for tooling-only acceptance
- AC2: deploy sequence is backup -> fetch/checkout -> config refresh/check -> rebuild/recreate vpnkit -> smoke -> auto-rollback on smoke failure -> post-rollback smoke
  - Evidence present: code path in `scripts/vpnkit/vpnkit-prod-deploy.sh` (`make_bundle`, `deploy`, `rollback_to`, `smoke`)
  - Result: passed
  - Gap: no live deploy execution, by scope
- AC3: rollback bundles under `.rollback/vpnkit/<timestamp>/` include git ref, image metadata/tag/id where available, compose/env references, runtime sing-box config, container inspect metadata, and executable rollback payload
  - Evidence present: code in `make_bundle()` plus existing `container-inspect.json` capture
  - Result: partial
  - Gap: no explicit env-reference artifact is written; image tag/id are only indirectly available via `container-inspect.json`, not separately surfaced
- AC4: discovery uses Docker/Compose labels and/or approved env overrides; no hard-coded production workdir/endpoint values
  - Evidence present: code in `discover()` and documented overrides in README/example env
  - Result: passed
  - Gap: none
- AC5: smoke checks cover container running, UDP 1194 published/listening, OpenVPN/tun0, sing-box/sb-tun0 for tun mode, policy rule/table, and `sing-box check` when available
  - Evidence present: `smoke()` in `scripts/vpnkit/vpnkit-prod-deploy.sh`
  - Result: passed
  - Gap: runtime availability of `sing-box`/`ss` is assumed on the target host; no live host probe was run
- AC6: multi-host deploy is sequential and stops on first host failure after rollback; no partial silent success
  - Evidence present: host loop exits on first failed `run_remote` result; remote `deploy()` rolls back on failed smoke
  - Result: passed
  - Gap: earlier successful hosts are not transactionally reverted if a later host fails before mutation on that later host; failure is still surfaced, so it is not silent
- AC7: tracked docs explain setup, plan/dry-run, deploy, rollback, verify, env placeholders, approval boundary, and public-safety rules
  - Evidence present: `README.md` and `config/private-endpoints.example.env`
  - Result: passed
  - Gap: none
- AC8: tests/checks cover shell syntax and safe argument/refusal/redaction behavior; mocked SSH/Docker/Compose tests are added where feasible
  - Evidence present: `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`, `test/prod-deploy-helper-test.sh`, `git diff --check`
  - Result: partial
  - Gap: no mocked SSH/Docker/Compose path coverage; the current test file exercises refusal/redaction/env-host-list only
- AC9: changes are committed and pushed to `feat/issue-24-smart-routing-manifest` if verification passes
  - Evidence present: `git log -1 --oneline --decorate` shows `HEAD -> feat/issue-24-smart-routing-manifest, origin/feat/issue-24-smart-routing-manifest` at `7007611`; PR #26 exists
  - Result: passed
  - Gap: none

## System readiness coverage
- Routes / registration: not relevant
- Services / APIs: not relevant
- Config / env / secrets: covered; placeholders only in `config/private-endpoints.example.env`, real local env remains gitignored, and the local/public-safe scan found no secret material in the new tooling changes
- Docker / containers: covered; helper discovers Compose workdir/service/container from labels or approved overrides and documents the rebuild/recreate path
- Permissions / access: not relevant
- Database / migrations: not relevant
- Frontend-backend integration: not relevant
- Runtime / deployment wiring: covered for tooling readiness only; live deployment wiring was not exercised

## Check freshness
- Targeted checks: fresh
- Full local checks: not needed
- Remote checks / CI: PR #26 status check rollup is empty (no CI status checks reported); otherwise not checked

## Required before done
- For full AC3 green: add an explicit env-reference artifact or equivalent bundle proof if the team wants that criterion fully closed instead of partially evidenced.
- For full AC8 green: add mocked SSH/Docker/Compose tests around the helper's remote payload and command routing.
- For live production readiness (out of scope here): source `config/private-endpoints.local.env`, run `plan`, then explicit-approval `deploy --yes`, `rollback --yes`, and `verify` on all production hosts.

## Files written
- `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/verification/acceptance-plan.md`: created
- `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/reports/acceptance-auditor.md`: created
