## Task package
- Task name: Production Docker deploy/rollback tooling
- Task package: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling`
- Report path: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/reports/acceptance-auditor-final.md`
- Acceptance plan path: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/verification/acceptance-plan.md`

## Acceptance verdict
- Status: accepted with limitations
- Summary: The repo-safe deploy/rollback helper now closes the prior AC3 and AC8 gaps with explicit rollback-bundle artifacts and mocked SSH/Docker/Compose coverage; all AC1-AC9 pass for tooling-only acceptance, with live production mutation intentionally out of scope.

## Acceptance coverage
- AC1: safe `plan`/`dry-run`/`deploy`/`rollback`/`verify`; mutating commands refuse without `--yes`
  - Evidence present: `scripts/vpnkit/vpnkit-prod-deploy.sh`; `test/prod-deploy-helper-test.sh`
  - Result: passed
  - Gap: none
- AC2: deploy sequence is backup -> fetch/checkout -> config refresh/check -> rebuild/recreate vpnkit -> smoke -> auto-rollback on failed smoke -> post-rollback smoke
  - Evidence present: `scripts/vpnkit/vpnkit-prod-deploy.sh` (`make_bundle`, `render_and_check`, `deploy`, `rollback_to`, `smoke`)
  - Result: passed
  - Gap: no live production mutation run, by scope
- AC3: rollback bundles under `.rollback/vpnkit/<timestamp>/` include git ref, image metadata/tag/id where available, compose/env references, runtime sing-box config, container inspect metadata, and an executable rollback payload
  - Evidence present: `scripts/vpnkit/vpnkit-prod-deploy.sh` now writes `git-ref.txt`, `image-ref.txt`, `image-id.txt`, `compose-files.txt`, `compose-file.txt`, `env-references.txt`, `container-inspect.json`, `sing-box-config.json`, and executable `rollback.sh`; `test/prod-deploy-helper-test.sh` asserts those artifacts
  - Result: passed
  - Gap: none for tooling-only acceptance
- AC4: remote repo/Compose discovery uses labels and/or approved env overrides; no hard-coded production workdir/endpoint values
  - Evidence present: `discover()` in `scripts/vpnkit/vpnkit-prod-deploy.sh`; placeholders/override docs in `README.md` and `config/private-endpoints.example.env`
  - Result: passed
  - Gap: none
- AC5: smoke checks cover container running, UDP 1194, OpenVPN/tun0, sing-box/sb-tun0 for tun mode, policy rule/table, and `sing-box check` when available
  - Evidence present: `smoke()` in `scripts/vpnkit/vpnkit-prod-deploy.sh`
  - Result: passed
  - Gap: runtime availability is assumed on the target host; no live host probe was run
- AC6: multi-host deploy is sequential and stops on first host failure after rollback; no partial silent success
  - Evidence present: host loop in `scripts/vpnkit/vpnkit-prod-deploy.sh`; remote `deploy()` auto-rolls back on smoke failure and exits nonzero
  - Result: passed
  - Gap: earlier successful hosts are not transactionally reverted if a later host fails; failure is still surfaced
- AC7: tracked docs explain setup, plan/dry-run, deploy, rollback, verify, env placeholders, approval boundary, and public-safety rules
  - Evidence present: `README.md`; `config/private-endpoints.example.env`
  - Result: passed
  - Gap: none
- AC8: tests/checks cover shell syntax and safe argument/refusal/redaction behavior; mocked SSH/Docker/Compose tests are added where feasible
  - Evidence present: fresh `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`, `test/prod-deploy-helper-test.sh`, and `git diff --check` all passed; the test script now mocks `timeout`, `ssh`, and remote `docker`/Compose/`git`/`date` paths for verify/rollback/two-host deploy sequencing and redaction
  - Result: passed
  - Gap: none for tooling-only acceptance
- AC9: changes are committed and pushed to `feat/issue-24-smart-routing-manifest` if verification passes
  - Evidence present: `git log -1 --oneline --decorate` shows `1bdc85c (HEAD -> feat/issue-24-smart-routing-manifest, origin/feat/issue-24-smart-routing-manifest)`
  - Result: passed
  - Gap: none

## System readiness coverage
- Routes / registration: not relevant
- Services / APIs: not relevant
- Config / env / secrets: covered; helper uses placeholder-only tracked env docs and keeps real values in the gitignored local env file
- Docker / containers: covered; helper discovers Compose workdir/service/container from labels or approved overrides
- Permissions / access: not relevant
- Database / migrations: not relevant
- Frontend-backend integration: not relevant
- Runtime / deployment wiring: covered for helper wiring only; live runtime exercise was intentionally out of scope

## Check freshness
- Targeted checks: fresh
- Full local checks: not needed
- Remote checks / CI: not checked; no CI status was reviewed for this re-audit

## Required before done
- None for repo-safe tooling acceptance.
- If live production readiness is desired later, source `config/private-endpoints.local.env` privately and run `plan`, `deploy --yes`, `rollback --yes`, and `verify` on all production hosts under explicit operator approval.

## Files written
- `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/verification/acceptance-plan.md`: updated
- `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/reports/acceptance-auditor-final.md`: created
