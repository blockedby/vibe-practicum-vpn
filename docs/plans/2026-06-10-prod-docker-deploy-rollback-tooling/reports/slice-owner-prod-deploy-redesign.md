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

## 2026-06-13 follow-up blocker pass

## Task
- Mission: Inspect and fix root integration blocker findings for the production deploy helper redesign.
- Target: `scripts/vpnkit/vpnkit-prod-deploy.sh`, `test/prod-deploy-helper-test.sh`, task-package evidence.
- Boundaries: local/static/mocked tests only; no live production mutation; no private endpoints/secrets/generated artifacts; no source archive/scp fallback/source-mode option.
- Done when: blockers are fixed or rebutted with code/test evidence and required local checks pass.
- Expected evidence: syntax check, helper test, diff check, source-transfer grep, public-safety grep.

## Context
- Thread: root integration follow-up for production deploy helper redesign.
- Slice: prod-deploy-redesign follow-up blocker pass.
- Task package: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling`.
- Report path: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/reports/slice-owner-prod-deploy-redesign.md`.
- Verification path: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/verification/prod-deploy-redesign-local.md`.
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`.
- Branch: `feat/issue-24-smart-routing-manifest`.

## Spec compliance
- Requirement: default deploy_id should be UTC timestamp + resolved `--target-ref` short SHA.
  - Status: done.
  - Evidence: `default_deploy_id "$target_ref"` uses `git rev-parse --short=12 "${ref}^{commit}"`; tests assert `HEAD` and `HEAD~1` short SHA in generated deploy IDs.
- Requirement: candidate image activation/rollback should actually use image tags with no rebuild.
  - Status: done.
  - Evidence: helper writes a generated Compose image override and calls `up -d --no-build`; tests assert `docker_tag=sha256:candidatebuild vpnkit:<deploy-id>`, override file usage, and no rollback `compose_build`.
- Requirement: deploy activation/config/smoke failures, including `require_tun_pair`, should attempt rollback.
  - Status: done.
  - Evidence: `deploy()` now treats `activate_image && require_tun_pair` as rollback-protected; `require_tun_pair` explicitly returns nonzero inside shell conditional context; tests force TUN pair failure and assert rollback start/activation.
- Requirement: deploy_id validation should prevent nested release dirs via `/` while keeping target_ref/rollback validation separate.
  - Status: done.
  - Evidence: separate `deploy_id_re` rejects `/`; `ref_id_re` remains separate for refs/rollback paths; tests assert `--deploy-id nested/id` fails.

## Acceptance verification
- AC: Confirmed blockers fixed or rebutted.
  - Covered by: code changes and `test/prod-deploy-helper-test.sh` assertions.
  - Result: passed.
  - Evidence: see verification artifact follow-up blocker evidence map.
- AC: Existing prior-slice acceptance still passes.
  - Covered by: full helper test suite.
  - Result: passed.
  - Evidence: `test/prod-deploy-helper-test.sh` PASS.
- AC: Required fresh checks.
  - Covered by: syntax, helper test, diff check, source-transfer grep, public-safety grep.
  - Result: passed.
  - Evidence: `verification/prod-deploy-redesign-local.md`.

## System readiness
- Config / env / secrets: done for tooling scope; no env values/secrets added; generated Compose override uses only image tags.
- Runtime / deployment wiring: done for mocked/static scope; no live production readiness claimed.
- Permissions / access: no live access used or required.

## Verification run
- Local / targeted checks:
  - `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`: passed.
  - `test/prod-deploy-helper-test.sh`: passed.
  - `git diff --check`: passed.
  - Source-transfer grep: passed for helper/README; only intentional negative-test/task-package wording remains.
  - Public-safety grep: passed; no suspicious added secret/private endpoint material outside intentional mock/negative-test assertions.
- Remote checks / CI: not available before push; no PR/CI checked in this follow-up.

## Issues
### Issue R-01: Default deploy_id used local HEAD
- Description: Existing default used local `HEAD`, not the resolved requested target ref.
- Evidence: prior `default_deploy_id()` called `git rev-parse --short=12 HEAD`.
- Resolution: `default_deploy_id()` now accepts target ref and resolves `${ref}^{commit}`; tests assert target-derived SHA.

### Issue R-02: Image activation could reuse pre-existing container image and ignore VPNKIT_IMAGE
- Description: Prior flow tagged from the container after `compose build` and relied on `VPNKIT_IMAGE=... compose up --no-build` without ensuring Compose consumed it.
- Evidence: code inspection of prior `activate_image()`.
- Resolution: build image ID is read from `docker compose images -q`, tagged as `vpnkit:<deploy-id>`, and activation/rollback use generated Compose image override files with `--no-build`.

### Issue R-03: TUN pair check failure could skip rollback
- Description: `require_tun_pair` was called outside explicit rollback-protected failure handling and shell `set -e` is unreliable inside conditional function contexts without explicit returns.
- Evidence: forced mock TUN failure initially continued past the failing mock command until explicit returns were added.
- Resolution: `require_tun_pair` now returns on each failing command and deploy wraps activation/config/smoke in rollback path; tests assert rollback on forced TUN pair failure.

### Issue R-04: deploy_id allowed slash
- Description: Shared id regex allowed `/`, which could create nested release dirs if used for deploy IDs.
- Evidence: prior `valid_id_re='^[A-Za-z0-9._@:+/-]+$'`.
- Resolution: split deploy ID validation from ref/rollback path validation; tests assert slash deploy ID rejection.

## Side findings
- Blocking findings folded into active work: R-01 through R-04.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: success.
- Goal state: fully achieved for local/static/mocked tooling follow-up.
- Final readiness: ready for parent integration, with the explicit limitation that no live production mutation/readiness was performed.
- Summary: Confirmed blockers were fixed and covered by fresh local/mocked verification.
