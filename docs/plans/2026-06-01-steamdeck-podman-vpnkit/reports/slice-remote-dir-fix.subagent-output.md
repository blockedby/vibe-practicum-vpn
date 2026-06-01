## Task
- Mission: Fix Steam Deck Podman script remote-dir `~` handling before root verification.
- Target: `scripts/vpnkit-steamdeck-podman.sh` and minimal runbook/task-package evidence.
- Boundaries: no VPS mutation; no rendered secrets required, printed, or committed; no scope broadening.
- Done when: `~`/`~/...` resolve to the Deck user's `$HOME` before remote dir use, absolute paths remain supported, targeted checks pass, and fix is committed/pushed.

## Context
- Slice: S1 Steam Deck Podman deploy/run/verify follow-up integration fix; stayed whole.
- Task package: `docs/plans/2026-06-01-steamdeck-podman-vpnkit`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit`
- Branch: `pi/steamdeck-podman-vpnkit`
- Commit: `1744a64 Fix Steam Deck remote dir expansion`
- Pushed: `origin/pi/steamdeck-podman-vpnkit`

## Spec compliance
- Normalize `~` / `~/...` over SSH: done. Evidence: `normalize_remote_dir` in `scripts/vpnkit-steamdeck-podman.sh`; read-only checks resolved default to `/home/deck/.local/state/vpnkit` and `~` to `/home/deck`.
- Preserve absolute remote paths: done. Evidence: `/tmp/vpnkit-test` resolved unchanged.
- Secrets unprinted: done. No rendered-secret commands run; only read-only SSH and path normalization checks. Secret scan only found the existing redaction pattern line.
- Docs/runbook: minimal clarification added in `docs/STEAMDECK_PODMAN_VPNKIT.md`.
- Commit/push: done. Evidence: `1744a64`, pushed to `origin/pi/steamdeck-podman-vpnkit`.

## Acceptance verification
- AC1: `~` and `~/...` resolve to remote `$HOME` before remote mkdir/tar/podman volume use.
  - Covered by: `resolve-remote-dir` action and command dispatch normalizing before `sync`, `build`, `run`, `deploy`.
  - Result: passed.
  - Evidence: default -> `/home/deck/.local/state/vpnkit`; `--remote-dir '~'` -> `/home/deck`.
- AC2: absolute paths remain supported.
  - Covered by: read-only normalization check.
  - Result: passed.
  - Evidence: `--remote-dir /tmp/vpnkit-test resolve-remote-dir` -> `/tmp/vpnkit-test`.
- AC3: `check-ssh` still works.
  - Covered by: live read-only Deck check.
  - Result: passed.
  - Evidence: hostname `steamdeck`, Podman `5.3.2`, UID `1000`, `/dev/net/tun:present`.
- AC4: syntax remains valid.
  - Covered by: `bash -n scripts/vpnkit-steamdeck-podman.sh`.
  - Result: passed.
- AC5: relative paths are not silently misused.
  - Covered by: negative read-only check.
  - Result: passed.
  - Evidence: `remote dir must be absolute or start with ~/: relative/path`; expected failure.

## System readiness
- Runtime/deployment wiring: ready for root verification with corrected remote-dir normalization.
- Config/secrets: unchanged; live deploy still requires operator-rendered gitignored inputs from earlier S1 status.
- VPS mutation: none.

## Verification run
- `bash -n scripts/vpnkit-steamdeck-podman.sh`: passed.
- `scripts/vpnkit-steamdeck-podman.sh --ssh-target deck check-ssh`: passed.
- `scripts/vpnkit-steamdeck-podman.sh --ssh-target deck resolve-remote-dir`: passed, `/home/deck/.local/state/vpnkit`.
- `scripts/vpnkit-steamdeck-podman.sh --ssh-target deck --remote-dir '~' resolve-remote-dir`: passed, `/home/deck`.
- `scripts/vpnkit-steamdeck-podman.sh --ssh-target deck --remote-dir /tmp/vpnkit-test resolve-remote-dir`: passed, `/tmp/vpnkit-test`.
- `scripts/vpnkit-steamdeck-podman.sh --ssh-target deck --remote-dir relative/path resolve-remote-dir`: expected failure passed.
- `git diff --check`: passed.
- Secret-oriented grep of changed files: no real secrets found; only existing redaction regex containing `vless://` matched.

## Issues
### Issue R-02: Literal `~` remote dir could be used in single-quoted remote commands
- Description: Default `REMOTE_DIR=~/.local/state/vpnkit` could be expanded locally or remain literal inside single-quoted remote commands, risking wrong remote mkdir/tar/Podman volume paths.
- Evidence: root integration blocker; reproduced by inspecting script command construction.
- Resolution: default now remains literal until SSH normalization; `sync`, `build`, `run`, and `deploy` normalize via remote `$HOME` before using `REMOTE_DIR`; absolute paths preserved; relative paths rejected.
- Depends on: none.

## Side findings
- Blocking findings folded into active work: R-02.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: success.
- Goal state: achieved.
- Final readiness: ready for root verification, except the pre-existing live-deploy limitation requiring rendered local secrets.
- Summary: Remote-dir expansion blocker is fixed, verified read-only on the Deck, committed, and pushed.
