## Task
- Mission: Diagnose/fix the Steam Deck lab live-cycle hang and rerun bounded live lifecycle evidence for issue #27 / PR #26.
- Target: `scripts/vpnkit-steamdeck-podman.sh`, `test/containers-test.sh`, isolated `vpnkit-test-steamdeck-host` Deck lab.
- Boundaries: Do not mutate default/prod `vpnkit`; do not print/commit private endpoints, logs, profiles, keys, certs, rendered configs, or secrets.
- Done when: Hang paths are bounded, safe checks pass, live lab sequence is run as far as safely possible, PR branch is ready for public-safe update.
- Expected evidence: root cause, changed files, commands/results, live matrix, cleanup state, blockers.

## Context
- Thread: Continue issue #27 / PR #26 after user said "занимайся"; previous live run hung after deploy/log output and was killed.
- Slice: Stayed whole under one slice owner; implementation was done directly because nested implementer delegation was unavailable at max subagent depth.
- Task name: Issue #27 Steam Deck test-lab lifecycle hang remediation
- Task package: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle`
- Report path: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/reports/slice-owner-live-hang-remediation.md`
- Verification path: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/verification/live-hang-remediation.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
- Branch: `feat/issue-24-smart-routing-manifest`
- Verify scope: bounded live Steam Deck lab lifecycle, safe repo checks, public-safe GitHub updates.

## Spec compliance
- Requirement / AC: Diagnose root cause of hang.
  - Status: done for script hang risks; current live startup blocker separately classified.
  - Evidence: `verify_container` had unbounded inner `podman exec`/doctor operations under a broad outer timeout; harness client smoke could run after server startup failure.
  - Gap if any: Exact prior 13h process stack cannot be recovered after kill, so diagnosis is from script behavior plus fresh bounded reproduction.
- Requirement / AC: Bound lifecycle commands and finite verify output.
  - Status: done.
  - Evidence: `scripts/vpnkit-steamdeck-podman.sh` wraps `podman ps`, logs, `pgrep`, `sing-box check`, subscription test, and `vibe-vpn doctor` in finite timeouts; logs use `--tail` only. `test/containers-test.sh` skips client smoke when server container is unavailable.
  - Gap if any: none for touched hang paths.
- Requirement / AC: Run live sequence safely against isolated lab.
  - Status: partial/current-goal blocker.
  - Evidence: `down` PASS; `up` returned bounded FAIL; `test` returned bounded FAIL; final `down` PASS. `cycle` not run because `up` failed on sing-box startup.
  - Gap if any: No green cycle; issue #27 must not be claimed done.
- Requirement / AC: Public-safe endpoint handling.
  - Status: done.
  - Evidence: endpoint loaded/discovered only into process env and redacted by harness; no endpoint committed or printed.
  - Gap if any: none.
- Requirement / AC: Safe repo checks and no tracked sensitive artifacts.
  - Status: done.
  - Evidence: see Verification run.
  - Gap if any: none.

## Acceptance verification
- AC1: Root cause diagnosed.
  - Covered by: code inspection plus fresh bounded live `up`/`test` behavior.
  - Result: passed for hang remediation; remaining blocker classified.
  - Evidence: `verification/live-hang-remediation.md`.
- AC2: Remote logs/exec/doctor paths bounded.
  - Covered by: code change and live `up` returning boundedly after finite logs.
  - Result: passed.
  - Evidence: `scripts/vpnkit-steamdeck-podman.sh`; `up` returned FAIL quickly instead of hanging.
- AC3: Live down/up/test/cycle.
  - Covered by: live commands.
  - Result: partial/blocked.
  - Evidence: `down` PASS, `up` bounded FAIL on sing-box remote rule-set fetch `unexpected EOF`, `test` bounded FAIL/skip, final cleanup PASS; `cycle` not run after failed `up`.
- AC4: Private endpoint safety.
  - Covered by: local env/discovery procedure and redacted harness output.
  - Result: passed.
  - Evidence: no endpoint in tracked changes; harness reports only `endpoint_state=yes`.
- AC5: Client smoke failure classification.
  - Covered by: test action after failed up.
  - Result: passed.
  - Evidence: server container unavailable, client smoke skipped rather than hanging.
- AC6: Repo checks / sensitive artifacts.
  - Covered by: static/proof/Go checks and tracked-file grep.
  - Result: passed.
  - Evidence: commands below.
- AC7: Commit/push/GitHub updates.
  - Covered by: pending owner finalization.
  - Result: not yet run at time of this report write.
  - Evidence: pending commit/push/comment.

## System readiness
- Routes / registration: not relevant.
- Services / APIs: not relevant.
- Config / env / secrets: ready except current live Deck startup blocker from outbound remote rule-set fetch; no secrets committed.
- Permissions / access: Deck SSH available for bounded lab operations.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: partial; isolated lab deploy runs but container exits on sing-box remote rule-set download `unexpected EOF`.

## Verification run
- Local / targeted checks:
  - `bash -n scripts/vpnkit-steamdeck-podman.sh test/containers-test.sh`: passed.
  - `python3 test/sing-box-smart-routing-proof.py`: passed.
- Local / full checks:
  - `bash -n scripts/*.sh test/*.sh`: passed.
  - `go test ./...`: passed.
  - `go vet ./...`: passed.
  - `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: passed.
  - `git ls-files | grep -Ei '(\.ovpn$|\.pem$|\.key$|logs/|secrets/)' || true`: passed/no tracked sensitive artifact paths.
- Remote checks / CI:
  - Status: pending push/PR update.
  - Evidence: to be collected after push.

## Issues
### Issue R-01: Verify/doctor commands were not individually bounded
- Description: The outer remote verify timeout existed, but individual `podman exec` and doctor commands could stall after finite logs, matching the previous apparent post-log hang behavior.
- Evidence: `verify_container` before this change used bare `podman exec ... pgrep`, bare subscription test, and bare `vibe-vpn doctor`.
- Resolution: Wrapped each verify/log/process/doctor `podman` operation with finite `timeout --preserve-status` using existing `VERIFY_TIMEOUT`/`LOGS_TIMEOUT` knobs.
- Depends on: none.

### Issue R-02: Client smoke could run after server startup failure
- Description: After an `up` failure left the isolated server container exited, `test` could still attempt client smoke against the generated profile/endpoint and wait for its timeout.
- Evidence: A bounded debug run was killed by outer timeout while reaching the client-smoke area after server unavailable; code did not gate client smoke on explicit Steam Deck server availability.
- Resolution: `test/containers-test.sh` now skips `client:steamdeck-profile-smoke` when explicit `steamdeck-host` server container is unavailable.
- Depends on: none.

### Issue U-01: Live Deck lab startup fails on remote RU rule-set download
- Description: Fresh bounded `up` deploys/builds/runs the isolated lab, but sing-box exits while fetching remote `.srs` rule sets from `raw.githubusercontent.com` with `unexpected EOF`.
- Evidence: Redacted live `up` output: `FATAL start service: ... rule-set ... raw.githubusercontent.com ... unexpected EOF`; then `lifecycle:deploy` FAIL. The command returned boundedly.
- Why unresolved: This is a current-goal live acceptance blocker outside the original hang path; changing smart-routing rule-set source semantics needs a separate scoped fix/decision to preserve production-like behavior.
- Needed next: Decide whether the Deck lab should vendor/cache RU `.srs` rule sets, disable remote RU rule-set downloads for lab acceptance, or treat Deck outbound GitHub fetch as an environment prerequisite.
- Depends on: product/lab acceptance decision.

## Side findings
- Blocking findings folded into active work: R-01, R-02; U-01 blocks green cycle acceptance.
- Non-blocking findings tracked separately: none created.

## Verdict
- Status: partial / blocked.
- Goal state: Hang remediation achieved; issue #27 live acceptance not done.
- Final readiness: not ready for issue closure because green `cycle` is blocked by live sing-box rule-set download failure.
- Summary: The prior hang class is bounded now, `up`/`test` return finite results, and isolated cleanup completed; remaining blocker is live Deck lab startup failure on remote RU rule-set downloads.

## Next-agent brief
- Objective: Resolve U-01 or obtain acceptance decision, then rerun full `down`/`up`/`test`/`cycle` and update issue/PR.
- Target: sing-box lab rule-set availability/startup behavior for `steamdeck-host`.
- Settled already: verify/doctor/log/client-smoke hang paths are bounded; do not re-expand into prod container or secret handling.
- Boundaries: isolated `vpnkit-test-steamdeck-host` only; no private endpoint/log/profile/key/cert disclosure.
- Verification target: green bounded live `test/containers-test.sh --scenario steamdeck-host --action cycle` or a precise accepted environment blocker.
- Expected output: updated verification matrix, commit/push, public-safe PR/issue status.
