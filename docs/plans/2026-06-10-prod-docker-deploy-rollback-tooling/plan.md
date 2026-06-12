# Plan: Production Docker deploy/rollback tooling

## Goal

Implement repo-safe, repeatable, one-button production Docker/Compose deploy and rollback tooling for `vpnkit` before any real production mutation occurs.

## Scope

In scope:
- Add a public-safe deploy helper (preferred `scripts/vpnkit/vpnkit-prod-deploy.sh`) with `plan`/`dry-run`, `deploy --yes --target-ref <ref> <host...>`, `rollback --yes <host...>`, and `verify <host...>` style flows.
- Default-safe behavior: dry-run/plan by default, refusal for mutating actions without `--yes`, bounded remote command timeouts, redaction, no private endpoints/secrets/log payloads printed or committed.
- Host inputs from CLI/env/gitignored `config/private-endpoints.local.env`; update tracked example keys only with placeholders if useful.
- Remote discovery of repo/Compose workdir, Compose project/service/container from Docker Compose labels or approved env overrides; avoid hard-coded production paths.
- Deploy flow: backup rollback bundle, fetch/checkout target ref, refresh/check persisted sing-box config, rebuild/recreate only vpnkit service/container, run partial smoke, auto-rollback on failed smoke, post-rollback smoke, nonzero on failed deploy/rollback smoke.
- Rollback flow using latest or explicit rollback bundle.
- Multi-host sequential behavior with stop-on-first-failed-host after rollback.
- README/runbook docs and feasible tests/static checks.

Out of scope:
- No production deploy, rollback, restart, compose up/down, remote mutation, endpoint probing, or reading/printing private endpoint values in this task.
- No unrelated runtime/routing behavior changes.
- No secrets, real hostnames/IPs, rendered configs, profiles, logs, snapshots, or image exports in tracked files.

## Acceptance criteria

AC1. A tracked deploy helper exists with safe subcommands for planning/dry-run, deploy, rollback, and verify, with mutating commands refusing unless `--yes` is passed.
AC2. Deploy design implements backup -> fetch/checkout target ref -> config refresh/check -> rebuild/recreate vpnkit service -> smoke -> automatic rollback on failed smoke -> post-rollback smoke.
AC3. Rollback bundles are created under a remote `.rollback/vpnkit/<timestamp>/`-style location and include current git ref, image metadata/tag/id where available, compose/env references, current runtime sing-box config, container inspect metadata, and an executable rollback payload without printing secret config contents.
AC4. Remote repo/Compose service discovery uses Docker/Compose labels and/or approved env overrides; no hard-coded production workdir/endpoint values.
AC5. Smoke checks cover at minimum container running, UDP 1194 published/listening, OpenVPN process and `tun0`, sing-box process and `sb-tun0` for tun mode, policy rule/table, and `sing-box check` when available; optional network checks are bounded and safe.
AC6. Multi-host deploy is sequential and stops on first host failure after rollback; there is no partial silent success.
AC7. Tracked docs explain setup, plan/dry-run, deploy, rollback, verify, env placeholders, production approval boundary, and public-safety rules.
AC8. Tests/checks cover shell syntax and safe argument/redaction/refusal behavior; mocked SSH/Docker/Compose tests are added where feasible.
AC9. Changes are committed and pushed to `feat/issue-24-smart-routing-manifest` if verification passes.

## Ownership model

Single slice: deployment tooling and runbook. The work has one system boundary (operator tooling/docs/tests) and one verification story (static/unit-style checks plus no live production mutation). A single `aad-slice-owner` should own implementation and may delegate internally.

## Delegated slice

### Slice: deploy-tooling

Goal:
- Make the repo contain a safe, documented, test-backed deploy/rollback helper meeting AC1-AC9 without mutating production.

Boundary:
- Likely files: `scripts/vpnkit/vpnkit-prod-deploy.sh`, `README.md`, `docs/*` runbook if appropriate, `config/private-endpoints.example.env`, `test/*` or existing shell test harness.
- Reuse patterns: `scripts/vpnkit/vpnkit-prod-singbox-dns-migration.sh`, public-safety/redaction patterns in existing scripts/tests, AGENTS production checklist.
- Do not touch production endpoints, private local env values, generated profiles/configs, or unrelated runtime logic.

Verification plan:
- `bash -n scripts/*.sh` or narrower syntax checks as appropriate.
- Targeted shell tests for argument parsing/refusal/redaction/host list and mocked SSH/remote commands if feasible.
- Static grep/manual checks proving no real endpoints/secrets are added and no hard-coded production paths.
- Optional existing local checks only if directly relevant and cheap.

Report path:
- `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/reports/slice-owner-deploy-tooling.md`

Status:
- pending delegation

## Execution ledger

2026-06-10 deploy-tooling slice owner update:
- Implemented `scripts/vpnkit/vpnkit-prod-deploy.sh` with `plan`/`dry-run`, `deploy --yes --target-ref`, `rollback --yes`, and `verify` flows.
- Added `test/prod-deploy-helper-test.sh` for local refusal/redaction/host-list coverage.
- Updated `README.md` and `config/private-endpoints.example.env` with public-safe usage and placeholder env knobs.
- Verification evidence recorded in `verification/local.md`.
- No production deploy/rollback/verify/probe was run.

2026-06-10 audit-gap-fix slice update:
- Mission: close acceptance audit gaps AC3 explicit rollback-bundle metadata/env references and AC8 mocked SSH/Docker/Compose path coverage without production mutation.
- Scope: `scripts/vpnkit/vpnkit-prod-deploy.sh`, `test/prod-deploy-helper-test.sh`, task-package verification/report artifacts only unless a minimal docs note is required.
- Do-not-touch: do not read or print `config/private-endpoints.local.env`; no live deploy/rollback/verify against real hosts; no real endpoints/secrets/logs in tracked files.

### Task 2: AC3/AC8 audit gap fix
Goal:
- Rollback bundles explicitly capture public-safe image tag/name and image ID where available plus compose/env reference artifacts without env values.
- Add lightweight mocked SSH/timeout path tests that prove deploy/verify/rollback routing/refusal/redaction/host sequencing without contacting production.

Boundary:
- System area: shell deploy helper and shell tests.
- Primary verification: syntax check, updated helper test with mocks, `git diff --check`, secret-like addition scan.

Existing pattern / reuse:
- Reuse existing `make_bundle()`, `run_remote()`, redaction, timeout/ssh override env vars, and `test/prod-deploy-helper-test.sh` style.

Missing change:
- Add explicit rollback bundle metadata files for image ref/id and env/compose references (names/paths/approved override names only; never values).
- Extend tests with fake `ssh` and fake `timeout` commands that execute the embedded remote script locally with mocked `docker`, `docker compose`, `git`, `date`, and shell helpers.

Acceptance criteria:
- AC3: bundle writes explicit artifacts for image tag/name, image ID when inspect can provide it, compose file refs, env file refs / approved env override names or refs without values, current runtime sing-box config, container inspect metadata, and executable rollback payload.
- AC8: mocked path coverage exercises/refuses mutating actions without `--yes`, and for approved mocked paths proves deploy/verify/rollback remote command routing, redaction, and sequential host handling without real SSH/production contact.

Evidence route:
- Existing automated checks: `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`; `test/prod-deploy-helper-test.sh`; `git diff --check`.
- Add/extend test: update `test/prod-deploy-helper-test.sh` with fake ssh/timeout path tests.
- Bounded acceptance probe: local mock-only shell test; no real endpoints, no private env file.
- Access/runtime needed: local shell only.
- Outcome boundary: PASS proves repo-safe command construction/routing and bundle artifact writes in a mocked remote path; does not prove live production host readiness.

Test plan:
- Positive: mocked `deploy --yes --target-ref main host-a host-b` sequences hosts and creates bundle metadata; mocked `verify host-a`; mocked `rollback --yes host-a` routes to rollback.
- Negative: existing deploy/rollback refusal without `--yes`; redaction catches secret-like mocked output.
- Edge cases: no env values are emitted in bundle reference artifact; output hosts are redacted as `<host>`.

Dependencies:
- Depends on: initial deploy-tooling slice implementation.
- Blocks: final report for audit-gap-fix.
- Can run parallel with: none (single coherent helper/test update).

Executor:
- aad-implementer

Task 2 status: ready for implementation dispatch.

2026-06-10 audit-gap-fix completion update:
- Task 2 status: done.
- AC3 evidence: `scripts/vpnkit/vpnkit-prod-deploy.sh` `make_bundle()` now writes explicit `image-ref.txt`, `image-id.txt`, `compose-files.txt`, `env-references.txt`, plus legacy compatibility refs and prior rollback artifacts without env values.
- AC8 evidence: `test/prod-deploy-helper-test.sh` now includes fake `timeout`/`ssh` and mocked remote `docker`/Compose/`git`/`date` paths for `verify`, `rollback`, and two-host `deploy` sequencing; redaction of mocked token-like output is asserted.
- Fresh verification: `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh` PASS; `test/prod-deploy-helper-test.sh` PASS; `git diff --check` PASS; audit-gap-fix secret-like diff scan PASS.
- Remaining limitation: no live production deploy/rollback/verify was run by scope; mock tests do not prove real host runtime readiness.

## Root integration status

Final status: done for repo-safe tooling. Slice implementation and audit-gap fix reports are integrated. Final audit (`reports/acceptance-auditor-final.md`) accepts AC1-AC9 for tooling-only readiness. Live production deployment remains out of scope pending explicit operator approval and private endpoint env.

2026-06-13 prod-deploy-redesign update:
- Mission: redesign existing production deploy helper to be git-only with deploy-id release/image-tag activation and no archive/scp source mode, without live production mutation.
- Scope: `scripts/vpnkit/vpnkit-prod-deploy.sh`, `test/prod-deploy-helper-test.sh`, README/docs/config examples as needed, and this task package only.
- Do-not-touch: no live production deploy/rollback/verify, no private endpoint reads/prints, no generated secrets/profiles/logs/images, preserve unrelated worktree/index changes.
- Reuse discovery: existing helper/test patterns already cover safe subcommands, remote discovery, mock ssh/timeout remote execution, redaction, refusal without `--yes`, sequential hosts, rollback bundles, and README tooling-only docs. Repo guidance requires git-only production helper, tun full-tunnel acceptance, and local/mocked verification.
- Missing pieces: remove source-mode/archive/scp behavior; deploy-id default/override; `/opt/vpnkit/releases/<deploy-id>` plus current/previous symlinks where feasible; candidate image `vpnkit:<deploy-id>`; activation and rollback by image tag without rebuild on rollback; persisted sing-box config + `VPNKIT_ROUTING_MODE` pair backup/restore; tun mode required smoke; exact manual recovery command on rollback-smoke failure; more readable `__remote` self-transfer/subcommand structure if practical; matching tests/docs.

### Task 3: Production deploy helper redesign
Goal:
- Make the production deploy helper implement the requested git-only release/image-tag deploy and no-build rollback design, with focused tests/docs and no live mutation.

Boundary:
- System area: shell deploy helper, shell tests, public README/docs/config examples.
- Primary verification: syntax check, mocked helper tests, `git diff --check`, targeted no-archive/scp grep, public-safety grep.

Existing pattern / reuse:
- Reuse `scripts/vpnkit/vpnkit-prod-deploy.sh` subcommand/refusal/redaction/remote discovery and `test/prod-deploy-helper-test.sh` fake ssh/timeout patterns.
- Prefer readable shell functions and local `__remote` subcommand/self-transfer over giant remote heredoc variables.

Missing change:
- Implement acceptance criteria from the 2026-06-13 routing context, including deploy-id, release layout, image tag activation, rollback metadata/config-mode restore, tun-required smoke, manual recovery command, and docs/tests.

Acceptance criteria:
- AC1-AC8 from the 2026-06-13 routing context are all covered by code, tests, or explicit tooling-only documentation.
- No archive fallback or scp source-transfer behavior remains in helper/test/docs except intentional negative assertions/wording.
- No live production mutation is performed.

Evidence route:
- Existing automated checks: `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`; `test/prod-deploy-helper-test.sh`; `git diff --check`.
- Add/extend tests: mocked remote execution should cover refusal/safety, no archive/scp behavior, deploy_id generation/override, release/image tag metadata, no-build rollback, tun smoke requirement, and manual recovery command output.
- Bounded acceptance probe: local shell/mock-only tests and greps; no real SSH endpoint.
- Access/runtime needed: local shell only.
- Outcome boundary: PASS proves public-safe helper behavior and command construction under mocks; does not prove live production readiness.

Test plan:
- Positive: plan/dry-run text describes release/image rollback flow; deploy with override/default deploy ID creates release/image metadata; rollback uses previous image/release/config/mode and does not build; verify/smoke requires tun mode and checks sing-box config, sb-tun0, policy rule, route.
- Negative: mutating commands refuse without `--yes`; source-mode/archive option refused/absent; no scp source transfer; rollback smoke failure prints exact manual recovery command.
- Edge cases: missing private endpoint env is not required for local tests; secret-like output redacted; host names redacted in output.
- Manual: no live production action by scope.

Dependencies:
- Depends on: prior helper implementation in this branch.
- Blocks: final slice report and verification artifact.
- Can run parallel with: none (single-writer shell helper/test redesign).

Executor:
- aad-implementer

Task 3 status: done.

2026-06-13 prod-deploy-redesign completion update:
- Subagent dispatch attempted but blocked by nested subagent depth; slice owner implemented the bounded shell/test/docs redesign directly in the current worktree.
- Changed files: `scripts/vpnkit/vpnkit-prod-deploy.sh`, `test/prod-deploy-helper-test.sh`, `README.md`, task-package report/verification artifacts.
- Evidence: `verification/prod-deploy-redesign-local.md` records PASS for syntax check, helper test, `git diff --check`, forbidden source-transfer grep, and public-safety grep.
- No live production deploy/rollback/verify was run.
- Report: `reports/slice-owner-prod-deploy-redesign.md`.

2026-06-13 prod-deploy-redesign follow-up blocker pass:
- Mission: confirm/fix root integration blockers after Task 3 without live production mutation.
- Scope: `scripts/vpnkit/vpnkit-prod-deploy.sh`, `test/prod-deploy-helper-test.sh`, task-package report/verification updates. Docs only if behavior text needs correction.
- Do-not-touch: no live production endpoints, no private env reads/prints, no generated profiles/config/logs/images, no source archive/scp fallback/source-mode option, preserve unrelated changes.
- Reuse discovery: current helper already has local/remote split, mock ssh/timeout tests, deploy-id override, release root/current/previous metadata, candidate-image metadata, auto-rollback on smoke failure, and no source-transfer assertions. Current likely gaps: local default deploy_id uses `git rev-parse HEAD`; deploy_id validation permits `/`; candidate image is tagged from existing container image after compose build and compose up relies only on `VPNKIT_IMAGE`; `require_tun_pair` is outside rollback-protected conditional under `set -e`.
- Missing pieces: derive default deploy_id from resolved `--target-ref` short SHA; separate stricter deploy_id validation from ref/rollback path; make compose build/up/rollback actually consume `VPNKIT_IMAGE` through a generated Compose override (or equivalent) and assert no-build activation/rollback; wrap deploy activation/config/smoke failures so rollback is attempted.

### Task 4: Follow-up blocker fixes for deploy-id/image activation/rollback safety
Goal:
- Fix confirmed root-integration blockers in the production deploy helper redesign and prove them with local/mocked tests.

Boundary:
- System area: shell deploy helper and shell tests.
- Primary verification: syntax check, targeted mocked helper tests, `git diff --check`, source-transfer grep, public-safety grep.

Existing pattern / reuse:
- Reuse current `__remote` functions, `run_bounded`, mock ssh/timeout/docker patterns in `test/prod-deploy-helper-test.sh`, and task-package verification/report paths.

Missing change:
- Default deploy_id must be UTC timestamp plus short SHA from resolved `--target-ref`, not local HEAD.
- Deploy_id must not allow `/` or nested release dirs; keep rollback-id/path support separate.
- Candidate image activation/rollback must actually use `vpnkit:<deploy-id>` or previous image via no-build Compose override/equivalent under current compose shape.
- Deploy activation/config/smoke failures, including `require_tun_pair`, must attempt rollback.

Acceptance criteria:
- Tests prove target-ref-derived default deploy_id, deploy-id slash rejection while target_ref/rollback paths remain valid where appropriate, image-tag activation/no-build behavior via compose override/equivalent, rollback no-build behavior, and auto-rollback when tun config/mode check fails.
- Existing prior-slice acceptance still passes.
- No source archive/scp fallback/source-mode option is reintroduced.
- No live production mutation or private endpoint use.

Evidence route:
- `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`
- `test/prod-deploy-helper-test.sh`
- `git diff --check`
- source-transfer grep and public-safety grep recorded in `verification/prod-deploy-redesign-local.md`.

Dependencies:
- Depends on: Task 3 redesign.
- Blocks: follow-up final report.
- Can run parallel with: none; single helper/test edit.

Executor:
- aad-implementer preferred; owner may apply tiny integration/report updates if delegation is unavailable.

Task 4 status: ready for implementation dispatch.

2026-06-13 prod-deploy-redesign follow-up blocker completion update:
- Task 4 status: done.
- Changed files: `scripts/vpnkit/vpnkit-prod-deploy.sh`, `test/prod-deploy-helper-test.sh`, `verification/prod-deploy-redesign-local.md`, `reports/slice-owner-prod-deploy-redesign.md`, plan/progress artifacts.
- R-01 fixed: default deploy_id now derives from resolved `--target-ref` short SHA; tests assert `HEAD` and `HEAD~1` derived deploy IDs when available.
- R-02 fixed: activation/rollback now use generated Compose image override files with selected image tags and `up -d --no-build`; tests assert candidate image tagging from compose image ID, override file usage, and no rollback build.
- R-03 fixed: `require_tun_pair` explicitly returns failure and deploy wraps activation/config/smoke failures in rollback; tests force TUN pair failure and assert rollback starts.
- R-04 fixed: deploy ID validation rejects `/` separately from target ref / rollback path validation.
- Verification evidence: `verification/prod-deploy-redesign-local.md` records PASS for syntax check, helper test, `git diff --check`, source-transfer grep, and public-safety grep.
- No live production deploy/rollback/verify was run.

2026-06-13 root audit follow-up blocker pass:
- Mission: close strict user-requested audit partials for release-pointer rollback and explicit TUN mode restoration in production deploy helper redesign, using local/static/mocked evidence only.
- Scope: `scripts/vpnkit/vpnkit-prod-deploy.sh`, `test/prod-deploy-helper-test.sh`, task-package verification/report/plan artifacts. No docs unless behavior text needs correction.
- Do-not-touch: no live production mutation or real SSH endpoints, no private env reads/prints, no generated profiles/configs/logs/images, no archive/scp/source-mode behavior.
- Reuse discovery: current helper already writes rollback metadata, release/current/previous symlinks, Compose image override, TUN pair check, and tests via fake ssh/timeout/docker/git.
- Missing pieces: rollback metadata must record pre-deploy current release target; deploy must set current to candidate and previous to prior target consistently; rollback must restore current to prior target while preserving failed/current release as previous; Compose override must explicitly enforce `VPNKIT_ROUTING_MODE: tun` for activation and rollback; tests must directly inspect symlinks and override contents.

### Task 5: Strict audit closure for release pointer and TUN mode rollback
Goal:
- Make rollback restore the previous release pointer and explicitly enforce TUN mode in activation/rollback Compose override, with mocked tests proving both.

Boundary:
- System area: shell deploy helper and shell tests.
- Primary verification: syntax check, helper tests, `git diff --check`, source-transfer grep, public-safety grep.

Existing pattern / reuse:
- Reuse current `write_metadata()`, `activate_image()`, `rollback_to()`, `compose_up_no_build_with_image()`, and mock test harness.

Missing change:
- Add `previous-release-target.txt` (or equivalent) in rollback metadata.
- During deploy activation, set `previous` to the prior `current` target and `current` to the candidate release.
- During rollback, set `current` to the metadata prior release target and `previous` to the failed/current release target where available.
- Generated Compose image override must include an environment entry enforcing `VPNKIT_ROUTING_MODE=tun`; rollback override must do the same.

Acceptance criteria:
- Tests prove `current`/`previous` link values after deploy and after rollback.
- Tests prove deploy and rollback override files include selected image and `VPNKIT_ROUTING_MODE: tun` (or equivalent enforced env).
- Prior redesign tests continue to pass; no archive/scp/source-mode behavior is reintroduced.

Evidence route:
- `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`
- `test/prod-deploy-helper-test.sh`
- `git diff --check`
- source-transfer grep and public-safety grep.

Dependencies:
- Depends on: Task 4 redesign blocker fixes.
- Blocks: final strict audit closure report.
- Can run parallel with: none.

Executor:
- aad-implementer

Task 5 status: ready for implementation dispatch.

2026-06-13 root audit follow-up strict closure completion update:
- Task 5 status: done.
- R-01 fixed: rollback metadata records `previous-release-target.txt`; deploy sets `current` to candidate release and `previous` to prior current; rollback restores `current` to the prior release and `previous` to the failed release. Mocked tests directly assert these symlink targets.
- R-02 fixed: generated deploy and rollback Compose image overrides explicitly include `VPNKIT_ROUTING_MODE: tun`; mocked tests inspect both override files.
- Verification evidence: `verification/prod-deploy-redesign-local.md` records PASS for syntax check, helper test, `git diff --check`, source-transfer grep, and public-safety grep.
- Prior audit partials for release-pointer rollback and explicit mode restore are closed under local/static/mocked evidence. Live production/CI evidence remains out of scope unless separately authorized/requested.
