## Task package
- Task name: Production deploy helper redesign audit
- Task package: docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/
- Report path: docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/reports/acceptance-auditor-prod-deploy-redesign.md
- Acceptance plan path: docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/verification/acceptance-plan.md

## Acceptance verdict
- Status: accepted with explicit limitations
- Summary: Current HEAD closes the rollback release-pointer restoration and explicit TUN-mode enforcement gaps in fresh local/mock evidence; tooling-only acceptance passes, while live production mutation remains intentionally out of scope.

## Acceptance coverage
- AC1: safe subcommands; mutating commands refuse without `--yes`
  - Evidence present: `scripts/vpnkit/vpnkit-prod-deploy.sh`, `test/prod-deploy-helper-test.sh`
  - Result: passed
  - Gap: none
- AC2: deploy sequence performs git-only release creation, image tagging, no-build activation, smoke, and auto-rollback path
  - Evidence present: helper `create_release()`, `activate_image()`, `deploy()`, and mocked deploy assertions
  - Result: passed
  - Gap: none for tooling-only acceptance
- AC3: rollback bundles include git ref, image metadata/tag/id where available, compose/env references, sing-box config, container inspect metadata, and rollback payload
  - Evidence present: `write_metadata()` plus rollback bundle assertions in `test/prod-deploy-helper-test.sh`
  - Result: passed
  - Gap: none
- AC4: remote discovery uses Docker/Compose labels or approved overrides; no hard-coded prod workdir/endpoint values
  - Evidence present: `discover()` and mocked SSH/Compose path tests
  - Result: passed
  - Gap: none
- AC5: rollback release-pointer restoration is correct
  - Evidence present: `write_metadata()` records `previous-release-target.txt`; `rollback_to()` restores `current` to prior release and `previous` to the failed release; tests assert both `readlink -f` results after deploy and rollback
  - Result: passed
  - Gap: none; this prior partial is now closed
- AC6: explicit TUN mode restore/enforcement is correct
  - Evidence present: generated deploy and rollback Compose overrides include `VPNKIT_ROUTING_MODE: tun`; `require_tun_pair()` and `smoke()` require tun mode; tests inspect both override files and fail on mocked redirect mode
  - Result: passed
  - Gap: none; this prior partial is now closed
- AC7: smoke checks cover container running, UDP 1194, OpenVPN/tun0, sing-box/sb-tun0, policy rule/table, and `sing-box check`
  - Evidence present: `smoke()` and `test/prod-deploy-helper-test.sh`
  - Result: passed
  - Gap: none
- AC8: tracked docs explain setup, plan/dry-run, deploy, rollback, verify, env placeholders, approval boundary, and public-safety rules
  - Evidence present: `README.md`, `config/private-endpoints.example.env`
  - Result: passed
  - Gap: none
- AC9: shell syntax, refusal/redaction, and mocked remote routing coverage are present
  - Evidence present: `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`, `test/prod-deploy-helper-test.sh`, `git diff --check`
  - Result: passed
  - Gap: none

## System readiness coverage
- Routes / registration: not relevant
- Services / APIs: not relevant
- Config / env / secrets: covered; placeholder-only env example and no private env reads in audit
- Docker / containers: covered; helper and mock Compose activation/rollback paths are exercised
- Permissions / access: blocked for live production only, not needed for tooling acceptance
- Database / migrations: not relevant
- Frontend-backend integration: not relevant
- Runtime / deployment wiring: covered for local tooling readiness; live production runtime remains untested by scope

## Check freshness
- Targeted checks: fresh
- Full local checks: fresh enough / not needed beyond targeted helper coverage
- Remote checks / CI: not checked; branch is already tracked on origin, but no CI status was queried for this audit

## Required before done
- None for tooling-only acceptance.
- If live production readiness is later required, run operator-approved deploy/rollback/verify on real hosts with private endpoint env loaded separately.

## Files written
- `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/verification/acceptance-plan.md`: updated
- `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/reports/acceptance-auditor-prod-deploy-redesign.md`: updated
