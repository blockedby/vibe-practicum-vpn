# Final report: Production Docker deploy/rollback tooling

## Task
- Mission: Implement repo-safe repeatable Docker/Compose deploy/rollback tooling for `vpnkit` before any real production deployment.
- Target: deployment helper, public-safe env placeholders, README runbook, and local/mock verification.
- Boundaries: no production endpoint mutation; no private endpoint values, secrets, rendered configs, profiles, logs, or image exports committed.
- Done when: AC1-AC9 in `plan.md` pass for tooling-only acceptance and branch is pushed.

## Context
- Task package: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
- Branch/PR: `feat/issue-24-smart-routing-manifest`, PR #26
- Slice structure: single deployment-tooling slice, plus one audit-gap fix pass. This was kept as one slice because tooling/docs/tests share one ownership boundary and one verification story.

## Spec compliance
- AC1 safe subcommands/refusal: done. `scripts/vpnkit/vpnkit-prod-deploy.sh` supports `plan`, `dry-run`, `deploy`, `rollback`, and `verify`; deploy/rollback require `--yes`.
- AC2 deploy sequence: done in helper: rollback bundle, fetch/checkout target ref, render/persisted sing-box check, Compose recreate of `vpnkit`, smoke, auto-rollback, post-rollback smoke.
- AC3 rollback bundle contents: done. Bundle writes git ref, image ref/id, compose/env references without values, runtime sing-box config, container inspect metadata, and executable rollback payload.
- AC4 discovery: done. Uses Compose labels and approved overrides; no production workdir/endpoint hard-coding.
- AC5 smoke: done. Checks container running, UDP 1194 mapping/listener, OpenVPN/`tun0`, sing-box, `sing-box check`, and `sb-tun0` policy routing for tun mode.
- AC6 multi-host behavior: done. Sequential host loop stops on first failed host after remote rollback handling; no silent partial success.
- AC7 docs/env placeholders: done in `README.md` and `config/private-endpoints.example.env`.
- AC8 tests/checks: done. Syntax, refusal/redaction, env host-list, and mocked SSH/Docker/Compose routing/bundle tests pass.
- AC9 commit/push: done. Head pushed to origin.

## Acceptance verification
- Local/root verification run:
  - `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`: passed.
  - `test/prod-deploy-helper-test.sh`: passed.
  - `git diff --check`: passed.
  - Secret-pattern diff scan over root task commits: passed/no matches.
- Slice evidence:
  - `reports/slice-owner-deploy-tooling.md`
  - `reports/slice-owner-audit-gap-fix.md`
  - `verification/local.md`
  - `verification/audit-gap-fix-local.md`
- Independent audit:
  - `reports/acceptance-auditor-final.md`: all AC1-AC9 pass for tooling-only acceptance; live production mutation intentionally out of scope.

## System readiness
- Config/env/secrets: tracked example contains placeholders only; real values remain in gitignored `config/private-endpoints.local.env`.
- Runtime/deployment wiring: helper is ready for operator-reviewed plan/deploy/rollback flow; live production health is not claimed.
- CI/remote checks: no live production checks or mutations were run by design; no separate CI status was required for local shell/doc change acceptance.

## Commits
- `9f7dc0a docs: plan prod deploy rollback tooling`
- `7007611 feat(deploy): add safe vpnkit production deploy helper`
- `c2aea27 test(deploy): cover production helper mock routing`
- `1bdc85c docs(deploy): report audit gap fix`
- Final report/audit artifact commit follows this report.

## Issues
### Issue R-01: Acceptance audit found rollback metadata/test gaps
- Resolution: Added explicit rollback metadata/env-reference artifacts and mocked SSH/Docker/Compose tests.
- Evidence: `scripts/vpnkit/vpnkit-prod-deploy.sh`, `test/prod-deploy-helper-test.sh`, `reports/acceptance-auditor-final.md`.

### Issue U-01: Live production deploy not executed
- Why unresolved: explicit user safety boundary.
- Needed next: operator privately sources endpoint env, reviews `plan`, then explicitly approves `deploy --yes --target-ref <ref>` across both production endpoints.

## Verdict
- Status: success.
- Goal state: fully achieved for repo-safe deploy/rollback tooling.
- Final readiness: ready for operator review and later explicit production approval; not a claim of live production deployment success.
