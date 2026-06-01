## Task
- Mission: close the cleanup-on-failure acceptance gap for `scripts/vpnkit-vibe-vpn-e2e.sh`.
- Target: e2e runner cleanup flags/messages and `docs/VPNKIT_VIBE_VPN_RUNBOOK.md` cleanup docs.
- Boundaries: no broader e2e architecture changes, no real secrets, no VPS mutation, no fake full e2e success.
- Done when: failed runs keep artifacts by default, and an explicit flag can clean up failed runs while honoring image cleanup toggles.
- Expected evidence: syntax check, help flag evidence, and missing-subscription failure runs proving both cleanup modes.

## Context
- Thread: parent/root task “Implement planned vibe-vpn-in-vpnkit container e2e”; narrow cleanup follow-up.
- Slice: cleanup semantics follow-up; kept whole under one slice owner. Implementation was done directly because nested subagent delegation was blocked by max subagent depth.
- Task package: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e`.
- Report path: `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/slice-owner-cleanup-followup.md`.
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/containerized-vpnkit-openvpn-singbox`.
- Branch: `pi/containerized-vpnkit-openvpn-singbox`.
- Verify scope: focused script/help/missing-subscription cleanup behavior only.

## Spec compliance
- Requirement / AC: on failure keep artifacts by default unless a cleanup flag is provided.
  - Status: done.
  - Evidence: default missing-subscription run logs `failure: preserving artifacts by default`; `--cleanup-on-failure` run logs `failure: cleaning up artifacts ... because --cleanup-on-failure was set`.
  - Gap if any: none.
- Requirement / AC: cleanup-on-failure runs compose `down --remove-orphans --volumes` and honors image cleanup toggles.
  - Status: done.
  - Evidence: cleanup command builder includes `--rmi local` only when `CLEANUP_IMAGES=1`; verification with `--no-cleanup-images` logged a command ending in `down --remove-orphans --volumes` without `--rmi local`.
  - Gap if any: none.
- Requirement / AC: docs and help expose the new flag.
  - Status: done.
  - Evidence: help output and `docs/VPNKIT_VIBE_VPN_RUNBOOK.md` include `--cleanup-on-failure`.
  - Gap if any: none.

## Acceptance verification
- AC1: default failure runs keep artifacts and print manual cleanup guidance.
  - Covered by: `scripts/vpnkit-vibe-vpn-e2e.sh --run-id cleanup-default-missing-sub --log-file logs/vpnkit-vibe-vpn-e2e/cleanup-default-missing-sub.log --no-build --no-cleanup-images || true`.
  - Result: passed.
  - Evidence: log includes `missing required vibe-vpn subscription input`, `failure: preserving artifacts by default`, and `cleanup with: docker compose ... down --remove-orphans --volumes` with no `--rmi local`.
- AC2: `--cleanup-on-failure` failure runs execute cleanup path and honor image cleanup toggle.
  - Covered by: `scripts/vpnkit-vibe-vpn-e2e.sh --run-id cleanup-flag-missing-sub --log-file logs/vpnkit-vibe-vpn-e2e/cleanup-flag-missing-sub.log --no-build --cleanup-on-failure --no-cleanup-images || true`.
  - Result: passed.
  - Evidence: log includes `failure: cleaning up artifacts ... because --cleanup-on-failure was set` and `+ docker compose ... down --remove-orphans --volumes` with no `--rmi local`.
- AC3: help output and runbook document the flag.
  - Covered by: `scripts/vpnkit-vibe-vpn-e2e.sh --help | grep` and doc diff.
  - Result: passed.
  - Evidence: help output lists `--cleanup-on-failure        Clean up containers/volumes after failed runs`; runbook useful options and cleanup section mention the flag.
- AC4: cleanup message does not show `--rmi local` when image cleanup is disabled.
  - Covered by: both missing-subscription runs with `--no-cleanup-images` and grep for cleanup command ending at `--volumes`.
  - Result: passed.
  - Evidence: grep matched `cleanup with: ... down --remove-orphans --volumes$` and `+ docker compose ... down --remove-orphans --volumes$`.

## System readiness
- Routes / registration: not relevant.
- Services / APIs: not relevant.
- Config / env / secrets: ready for scoped behavior; verification intentionally used missing subscription input and did not add secrets.
- Permissions / access: not relevant.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: ready for scoped script cleanup behavior; full Docker e2e remains outside this follow-up.

## Verification run
- Local / targeted checks:
  - `bash -n scripts/vpnkit-vibe-vpn-e2e.sh`: passed.
  - `scripts/vpnkit-vibe-vpn-e2e.sh --help | grep -E -- '--cleanup-on-failure|--keep-artifacts|--cleanup-images|--no-cleanup-images'`: passed.
  - default missing-subscription run with `--no-cleanup-images`: passed for expected failure/retention semantics.
  - missing-subscription run with `--cleanup-on-failure --no-cleanup-images`: passed for expected cleanup path/log message.
- Local / full checks:
  - Full Docker e2e: not run; out of scope and subscription input unavailable.
- Remote checks / CI:
  - Status: not checked before push.

## Issues
### Issue R-01: Missing explicit cleanup-on-failure control
- Description: the script preserved failed-run artifacts but had no flag to automatically clean failed runs.
- Evidence: pre-change script had `KEEP_ARTIFACTS`, success cleanup, and default failure preservation only.
- Resolution: added `--cleanup-on-failure` and failure cleanup branch.
- Depends on: none.

### Issue R-02: Cleanup command could show `--rmi local` when image cleanup was disabled
- Description: pre-change manual cleanup command used `${CLEANUP_IMAGES:+ --rmi local}`, which expands for `CLEANUP_IMAGES=0` because the variable is still set.
- Evidence: script code before change.
- Resolution: added `cleanup_command()` that appends `--rmi local` only when `CLEANUP_IMAGES -eq 1`.
- Depends on: none.

## Side findings
- Blocking findings folded into active work: R-01, R-02.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: success.
- Goal state: fully achieved.
- Final readiness: ready for the scoped cleanup follow-up.
- Summary: the cleanup acceptance gap is closed; failed runs keep artifacts by default and `--cleanup-on-failure` enables automatic compose cleanup with correct image-toggle messaging.
