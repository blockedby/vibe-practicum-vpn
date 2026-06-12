## Task
- Mission: Close strict audit follow-up blockers for production deploy helper redesign.
- Target: `scripts/vpnkit/vpnkit-prod-deploy.sh`, `test/prod-deploy-helper-test.sh`, task-package verification/plan artifacts.
- Boundaries: Local/static/mocked only; no live production mutation, real SSH endpoints, private endpoints, generated profiles/configs/logs/images, or archive/scp/source-mode behavior.
- Done when: release-pointer rollback and explicit TUN mode restore/enforcement are implemented and proven by mocked tests plus required static checks.
- Expected evidence: fresh syntax check, helper test, `git diff --check`, source-transfer grep, public-safety grep.

## Context
- Slice: root audit follow-up strict closure.
- Task package: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling`.
- Report path: `docs/plans/2026-06-10-prod-docker-deploy-rollback-tooling/reports/slice-owner-strict-audit-closure.md`.
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`.
- Branch: `feat/issue-24-smart-routing-manifest`.

## Spec compliance
- Release-pointer rollback: done.
  - Evidence: rollback metadata now includes `previous-release-target.txt`; tests assert deploy and rollback `current`/`previous` symlink targets.
- Mode restore/enforcement: done.
  - Evidence: generated deploy and rollback Compose overrides include selected image and `VPNKIT_ROUTING_MODE: tun`; tests inspect both files.
- Public safety/no source transfer: done.
  - Evidence: required greps pass; no live production mutation was run.

## Acceptance verification
- AC1 release-pointer rollback metadata and symlink behavior:
  - Covered by: `test/prod-deploy-helper-test.sh` mocked prior-release/current/previous assertions.
  - Result: passed.
- AC2 explicit TUN mode pairing in override:
  - Covered by: override file content assertions in `test/prod-deploy-helper-test.sh`.
  - Result: passed.
- AC3 no source-transfer/public-safety regression:
  - Covered by: source-transfer grep and public-safety grep.
  - Result: passed.

## System readiness
- Runtime/deployment wiring: locally/mocked ready for the strict audited paths.
- Config/env/secrets: public-safe; no private values read or committed.
- Permissions/access: live production access intentionally not used.

## Verification run
- `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`: passed.
- `test/prod-deploy-helper-test.sh`: passed.
- `git diff --check`: passed.
- source-transfer grep on helper/README: passed.
- public-safety grep on production helper/docs diff: passed.

## Issues
### Issue R-01: Release-pointer rollback partial closed
- Description: auditor found rollback did not directly prove restoring `current` to the prior release target.
- Resolution: added prior current target metadata and rollback symlink restoration; added direct mocked symlink assertions.

### Issue R-02: Explicit TUN mode restore partial closed
- Description: auditor found mode restore was implied by TUN checks but not explicitly enforced in override content.
- Resolution: generated Compose overrides now set `VPNKIT_ROUTING_MODE: tun`; tests inspect deploy and rollback overrides.

## Side findings
- Blocking findings folded into active work: R-01, R-02.
- Non-blocking findings: none.

## Verdict
- Status: success.
- Goal state: fully achieved for local/static/mocked strict audit follow-up.
- Final readiness: ready except live production/CI evidence remains outside this bounded follow-up.
