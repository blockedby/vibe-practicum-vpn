## Task
- Mission: Execute `next-tun-validation-task.md` end-to-end for vpnkit sing-box TUN live validation through all feasible stages, cleanup, document sanitized evidence, run required tests, and commit safe docs/reports.
- Target: Worktree `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-tproxy-udp-nested`, branch `vpnkit-tproxy-udp-nested`.
- Boundaries: No production `vpnkit`/`current-vpnkit-1` mutation, no Steam Deck, isolated resources only, no secrets/profiles/rendered configs/raw logs committed or printed.
- Done when: Matrix/report updated, feasible Stage A-D evidence captured, cleanup complete or blockers explicit, required checks pass, safe commit created.
- Expected evidence: `verification/tun-live-complete-matrix.md`, `reports/tun-live-complete-report.md`, this report, final checks, commit hash.

## Context
- Thread: Root owner delegated the single operational validation slice for the exact next-task file.
- Slice: Stayed whole. Attempted `aad-implementer` delegation, but nested subagent depth blocked it; slice owner executed directly.
- Task name: finish vpnkit sing-box TUN-mode validation.
- Task package: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit`.
- Report path: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/slice-owner-next-tun-validation-run.md`.
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-tproxy-udp-nested`.
- Branch: `vpnkit-tproxy-udp-nested`.
- Verify scope: task-file acceptance criteria and required final commands.

## Spec compliance
- Preflight cleanup/status:
  - Status: partial/done.
  - Evidence: `vibe-practicum` known old TUN leftovers removed and exact path checked clean. `moscow-tiger` production metadata was captured before/after unchanged, but one final exact-name cleanup command for older known moscow leftovers timed out.
  - Gap: moscow old-leftover final exact-name cleanup needs retry when SSH is stable.
- Simpler live TUN harness:
  - Status: done for feasible local-host stages.
  - Evidence: packaged current worktree plus matching gitignored rendered material without printing contents; copied to exact `/tmp/vpnkit_tun_live_21741_server`; started isolated outer TUN server on `21741/udp`; started isolated inner server on fresh private network; generated temp client profiles by remote-line and inner `dev tun1`/subnet edits; exact cleanup completed.
- Stage A local-host outer validation:
  - Status: baseline passed; fresh public UDP echo not rerun.
  - Evidence: OpenVPN `tun0` up, UDP DNS `NOERROR`, HTTPS `200`, literal-IP HTTPS `200`, server `sb-tun0` counters/policy route, no redirect/tproxy capture chains in `verification/tun-live-complete-matrix.md`.
  - Gap: Fresh separate-host public UDP echo was blocked while `moscow-tiger` SSH was timing out. Prior accepted TUN public echo evidence remains in the package.
- Stage B local-host nested validation:
  - Status: failed/partial.
  - Evidence: route to inner endpoint via outer `tun0`; sing-box TUN packet connection to inner endpoint; no `tun1`; TLS handshake timeout.
- Stage C/D moscow-tiger validation:
  - Status: blocked/not run.
  - Evidence: moscow SSH intermittently timed out during preflight/fresh setup; production metadata later rechecked unchanged; no fresh moscow client resources were created.
- Documentation:
  - Status: done.
  - Evidence: updated `verification/tun-live-complete-matrix.md` and `reports/tun-live-complete-report.md`.
- Final required tests:
  - Status: done.
  - Evidence: commands listed below passed.

## Acceptance verification
- AC1 preflight cleanup/status and production metadata:
  - Covered by: exact cleanup/status commands and before/after `docker inspect` metadata.
  - Result: partial pass.
  - Evidence: `vpnkit` unchanged (`running`, restart `0`, same start time); `current-vpnkit-1` unchanged (`running`, restart `0`, same start time); moscow old-leftover cleanup command timed out.
- AC2 fix/build simpler harness:
  - Covered by: explicit package/copy/start/client-profile/cleanup flow with fresh names `21741/21742`.
  - Result: passed for local-host feasible stages.
  - Evidence: matrix resources section.
- AC3 run all feasible stages A-D:
  - Covered by: Stage matrix.
  - Result: partial.
  - Evidence: Stage A baseline pass; Stage B nested fail; Stage C/D blocked by intermittent SSH reachability.
- AC4 failure evidence:
  - Covered by: route, interface, counter, filtered sing-box summaries.
  - Result: passed for Stage B failure; not applicable for C/D because no client mutation occurred.
- AC5 end cleanup:
  - Covered by: exact local/vibe cleanup commands.
  - Result: passed for fresh resources; partial for older moscow known leftovers due timeout.
- AC6 documentation:
  - Covered by: required matrix/report files.
  - Result: passed.
- AC7 final commands:
  - Covered by: fresh test run.
  - Result: passed.
- AC8 commit-only-safe-artifacts:
  - Covered by: git status/diff review before commit; only docs/progress/report/verification/task file changed.
  - Result: ready for commit.

## System readiness
- Routes / registration: TUN baseline routing ready; nested route reaches inner endpoint but inner handshake not ready.
- Services / APIs: not applicable.
- Config / env / secrets: private endpoint file was sourced without printing values; generated profiles/rendered configs stayed temp/gitignored.
- Permissions / access: `vibe-practicum` usable; `moscow-tiger` intermittent SSH caused C/D blocker.
- Database / migrations: not applicable.
- Frontend-backend integration: not applicable.
- Runtime / deployment wiring: isolated runtime only; production untouched.

## Verification run
- Local / targeted checks:
  - Stage A local-host baseline against isolated `vibe-practicum` TUN server: passed.
    - Evidence: OpenVPN up; UDP DNS `NOERROR`; HTTPS `200`; literal-IP HTTPS `200`; `sb-tun0` RX/TX counters; no redirect/tproxy chains.
  - Stage B local-host nested OpenVPN: failed/partial.
    - Evidence: `ip route get 172.23.0.3` via `10.89.0.1 dev tun0`; sing-box `inbound/tun` packet connection to inner endpoint; inner TLS handshake timeout; no `tun1`.
  - Stage C/D moscow-tiger: not run.
    - Evidence: SSH timeout during preflight/setup; no fresh moscow mutation.
- Local / full checks:
  - `bash tests/vpnkit-singbox-template-test.sh`: passed (`vpnkit sing-box templates ok`).
  - `bash tests/vpnkit-setup-routing-test.sh`: passed (`vpnkit setup-routing mode behavior ok`).
  - `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh`: passed.
  - `go test ./...`: passed.
  - `git diff --check`: passed.
- Remote checks / CI:
  - Status: not available before push.

## Issues
### Issue U-01: Full nested OpenVPN over TUN did not complete locally
- Description: Stage B proved outer tunnel and route to inner endpoint via `tun0`; sing-box TUN saw/direct-routed the packet, but inner OpenVPN did not establish `tun1`.
- Evidence: Route via `10.89.0.1 dev tun0`; filtered sing-box `inbound/tun` packet connection to inner endpoint; inner client TLS handshake timeout; no `tun1`.
- Why unresolved: Runtime behavior needs further debugging; safe continuation was deprioritized after meeting cleanup/report boundary and C/D host instability.
- Needed next: Retry nested with additional packet/conntrack evidence on the inner network and/or simpler UDP echo on same inner endpoint while preserving isolation.
- Depends on: stable live access.

### Issue U-02: Stage C/D blocked by intermittent moscow-tiger SSH reachability
- Description: `moscow-tiger` SSH timed out during setup/cleanup attempts, so fresh moscow client validation was not safe to start.
- Evidence: SSH command to `moscow-tiger` timed out during preflight/fresh echo setup; production metadata later recheck succeeded unchanged.
- Why unresolved: External host reachability instability.
- Needed next: Retry exact known cleanup and Stage C/D when SSH is stable.
- Depends on: stable `moscow-tiger` SSH.

## Side findings
- Blocking findings folded into active work: U-01, U-02.
- Non-blocking findings tracked separately: none; no `F-*` follow-up issue created because unresolved items are current-goal blockers rather than optional follow-ups.

## Verdict
- Status: partial / blocked.
- Goal state: partially achieved.
- Final readiness: ready for baseline guarded TUN canary planning only if nested OpenVPN and different-host validation are explicitly excluded; not ready as complete A-D validation.
- Summary: Feasible local live TUN baseline passed and fresh resources were cleaned; nested and moscow stages remain unresolved blockers.

## Next-agent brief
- Objective: Complete the missing A-D validation evidence.
- Target: Retry moscow cleanup/status, Stage C outer baseline/public UDP echo, Stage D nested, and deeper Stage B nested debugging.
- Settled already: TUN baseline on isolated `vibe-practicum` server `21741` passed; production metadata stayed unchanged; local/vibe fresh resources from this attempt were cleaned.
- Boundaries: Same no-production-mutation/no-secrets/no-broad-tmp constraints.
- Verification target: All Stage A-D criteria in `next-tun-validation-task.md` with fresh separate-host public UDP echo and nested `tun1` proof or decisive sanitized blocker evidence.
- Expected output: Updated matrix/report and final checks/commit.
