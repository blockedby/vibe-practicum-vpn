## Task
- Mission: Implement safe production Docker/Compose deploy/rollback tooling for vpnkit before any real deploy.
- Target: `scripts/vpnkit/vpnkit-prod-deploy.sh`, operator docs/env placeholders, and local static tests.
- Boundaries: Public-safe local/static only; no production endpoints read, probed, restarted, deployed, or rolled back.
- Done when: AC1-AC9 are satisfied by tracked tooling/docs/tests and passing local checks.

## Context
- Slice: deploy-tooling; stayed whole, no sub-slices. Implementation was completed directly because nested delegation was unavailable at max subagent depth.
- Task package: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
- Branch: `feat/issue-24-smart-routing-manifest`
- PR: #26

## Files changed
- Added `scripts/vpnkit/vpnkit-prod-deploy.sh`.
- Added `test/prod-deploy-helper-test.sh`.
- Updated `README.md` with production helper runbook/usage.
- Updated `config/private-endpoints.example.env` with placeholder-only helper env knobs.
- Updated `plan.md` execution ledger and `verification/local.md`.

## Commits
- `feat(deploy): add safe vpnkit production deploy helper` (pushed to `origin/feat/issue-24-smart-routing-manifest`; final hash reported by slice owner).

## Usage examples
```bash
scripts/vpnkit/vpnkit-prod-deploy.sh plan --target-ref origin/main your-prod-ssh-alias
scripts/vpnkit/vpnkit-prod-deploy.sh dry-run --target-ref origin/main your-prod-ssh-alias
scripts/vpnkit/vpnkit-prod-deploy.sh deploy --yes --target-ref <commit-or-branch> host-a host-b
scripts/vpnkit/vpnkit-prod-deploy.sh rollback --yes host-a host-b
scripts/vpnkit/vpnkit-prod-deploy.sh rollback --yes --rollback-id .rollback/vpnkit/<timestamp> host-a
scripts/vpnkit/vpnkit-prod-deploy.sh verify host-a host-b
```

## Spec compliance / acceptance verification
- AC1 safe subcommands/refusal: done. `vpnkit-prod-deploy.sh` supports `plan`, `dry-run`, `deploy`, `rollback`, `verify`; mutating commands refuse without `--yes`. Evidence: `test/prod-deploy-helper-test.sh` PASS.
- AC2 deploy sequence: done in helper remote payload: rollback bundle -> `git fetch`/checkout -> render/persisted sing-box check -> `compose up -d --build vpnkit` -> smoke -> auto-rollback -> post-rollback smoke.
- AC3 rollback bundles: done. Remote `.rollback/vpnkit/<timestamp>/` includes git ref, image metadata, compose reference, runtime sing-box config, container inspect, executable `rollback.sh`; script avoids printing file contents.
- AC4 discovery: done. Uses Compose Docker labels and approved overrides (`VPNKIT_PROD_WORKDIR`, `VPNKIT_PROD_SERVICE`, `VPNKIT_PROD_CONTAINER`, `VPNKIT_PROD_PROJECT`); no hard-coded production host/path.
- AC5 smoke checks: done in `smoke()`: container running, UDP 1194 mapping/listener, OpenVPN/`tun0`, sing-box, `sing-box check`, and tun-mode `sb-tun0` policy rule/table.
- AC6 multi-host sequencing: done. Local loop processes hosts sequentially and exits on first failed host after remote deploy rollback handling.
- AC7 docs: done. README runbook and endpoint example placeholders updated with approval and safety boundaries.
- AC8 tests/checks: done. Syntax, refusal, dry-run/redaction, env host-list, public-safety diff scan, and `git diff --check` passed.
- AC9 commit/push: done; see commit section.

## System readiness
- Config/env/secrets: Placeholder-only env docs added; real endpoint env remains gitignored. No secret values read or committed.
- Runtime/deployment wiring: Tooling models the production deploy/rollback path but live readiness remains HANDOFF pending explicit operator approval and local endpoint env.
- Production mutation: not performed by design.

## Verification run
- `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`: passed.
- `test/prod-deploy-helper-test.sh`: passed.
- Public-safety diff scan for private keys/VLESS URLs/token assignments: passed (no matches).
- `git diff --check`: passed.
- Evidence artifact: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/verification/local.md`.

## Issues
- Blocking findings folded into active work: none.
- Non-blocking findings requiring GitHub follow-up: none.
- U-01 Production deploy not executed: unresolved by required scope boundary. Needed next: explicit operator approval plus local `config/private-endpoints.local.env`, then run plan/deploy/verify on all production endpoints.

## Verdict
- Status: success for repo-safe deploy/rollback tooling readiness.
- Not claimed: live production deploy-readiness or endpoint health.

## Next-agent brief
- If continuing to live operations, first source local endpoint env privately, run `plan` for all production hosts, review discovered labels/overrides, then run `deploy --yes --target-ref <approved-ref>` only after explicit approval.
