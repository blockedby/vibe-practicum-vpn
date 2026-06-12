## Task
- Mission: Implement the production deploy helper redesign for git-only release/image-tag deploy and no-build rollback.
- Target: `scripts/vpnkit/vpnkit-prod-deploy.sh`, `test/prod-deploy-helper-test.sh`, `README.md`, task package evidence.
- Boundaries: No live production mutation; no private endpoints/secrets/generated profiles/logs/image exports; preserve unrelated changes.
- Done when: Acceptance criteria are implemented and proven by local/static/mocked checks.
- Expected evidence: syntax/test/diff/grep evidence in `verification/prod-deploy-redesign-local.md`.

## Context
- Thread: production deploy helper redesign requested under issue-24 worktree routing context.
- Slice: single implementation slice; subagent delegation was unavailable due max nested subagent depth, so slice owner implemented directly.
- Task package: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling`
- Report path: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/reports/slice-owner-prod-deploy-redesign.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
- Branch: `feat/issue-24-smart-routing-manifest`
- Verify scope: local/static/mocked remote only.

## Spec compliance
- AC1 git-only CLI and deploy ID:
  - Status: done
  - Evidence: helper supports `--deploy-id`, default timestamp+short SHA, and no source-mode option; tests assert override/default and refusal of `--source-mode`.
- AC2 non-mutating plan/dry-run:
  - Status: done
  - Evidence: plan/dry-run output includes `mutation=none`, release dir, image tag, no-build activation/rollback steps.
- AC3 deploy remote flow:
  - Status: done for tooling/mocked evidence
  - Evidence: mocked deploy covers discovery, git ref resolution, `/opt/vpnkit/releases/<deploy-id>` layout, rollback metadata, build/tag `vpnkit:<deploy-id>`, no-build activation, tun config/mode check, smoke, and sequential hosts.
- AC4 rollback flow:
  - Status: done for tooling/mocked evidence
  - Evidence: rollback reads previous image/config/mode metadata, reactivates with `--no-build`, and prints manual recovery command on rollback smoke failure.
- AC5 tun smoke requirement:
  - Status: done
  - Evidence: smoke requires `VPNKIT_ROUTING_MODE=tun`, sing-box config check, `sb-tun0`, policy rule, and route table; mocked redirect mode fails.
- AC6 readability/self-transfer:
  - Status: done
  - Evidence: removed giant quoted `remote_script` variable; helper uses local `__remote` subcommand over stdin self-transfer.
- AC7 tests:
  - Status: done
  - Evidence: `test/prod-deploy-helper-test.sh` covers refusal/safety, removed source-mode/source transfer, deploy ID, release/image metadata, no-build rollback, tun smoke, and manual recovery.
- AC8 docs:
  - Status: done
  - Evidence: README production helper section documents tooling-only use, git-only source, release layout, image-tag rollback, approval boundary, and no live mutation during documentation.

## Acceptance verification
- All acceptance criteria:
  - Covered by: `bash -n`, `test/prod-deploy-helper-test.sh`, `git diff --check`, targeted source-transfer grep, public-safety grep.
  - Result: passed
  - Evidence: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/verification/prod-deploy-redesign-local.md`.

## System readiness
- Routes / registration: not relevant.
- Services / APIs: not relevant.
- Config / env / secrets: done for public-safe docs/tests; no real env read or committed.
- Permissions / access: live production access intentionally not used.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: ready for tooling-only review; live production readiness remains explicitly unproven until operator-approved run.

## Verification run
- Local / targeted checks:
  - `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`: passed.
  - `test/prod-deploy-helper-test.sh`: passed.
  - `git diff --check`: passed.
  - no forbidden helper/docs source-transfer grep: passed.
  - public-safety grep: passed with only mock/negative-test matches.
- Remote checks / CI:
  - Status: not available before push / not run.
  - Evidence: no PR/check invocation in this slice.

## Issues
- None.

## Side findings
- Blocking findings folded into active work: none.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: success
- Goal state: fully achieved for local tooling implementation.
- Final readiness: ready for review/mocked-tooling acceptance; not a live production deployment approval.
- Summary: The helper now follows the requested git-only deploy-id release/image-tag model with no-build rollback and tun-required smoke, backed by local mocked tests and public-safe docs.

## Next-agent brief
- Objective: If continuing, review/commit/push/PR this scoped change and run CI if available.
- Target: changed files listed in git status.
- Settled already: no live production mutation; source transfer fallback is removed; local verification passes.
- Boundaries: keep private endpoint values and generated artifacts out of tracked files.
- Verification target: CI or rerun local verification from the artifact.
- Expected output: PR/check evidence or merge-readiness report.
