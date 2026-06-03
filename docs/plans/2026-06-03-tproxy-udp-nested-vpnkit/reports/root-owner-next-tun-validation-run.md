# Root owner report: next TUN validation run

## Task
- Mission: Follow `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/next-tun-validation-task.md` and finish vpnkit sing-box TUN-mode validation through all feasible safe stages.
- Target: Branch `vpnkit-tproxy-udp-nested`, worktree `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-tproxy-udp-nested`.
- Boundaries: No production `vpnkit` or `current-vpnkit-1` mutation, no Steam Deck, isolated names/ports/temp paths only, no secrets/generated profiles/rendered configs/logs/tarballs committed or printed.
- Done when: Feasible Stage A-D evidence is documented, cleanup is complete or exact blockers recorded, required checks pass, safe docs/reports are committed; push only if successful.

## Context
- Root task package: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit`.
- Slice used: one `aad-slice-owner` operational validation slice, because the task had one runtime harness/evidence/cleanup ownership boundary and splitting live resources would increase handoff risk.
- Slice report: `reports/slice-owner-next-tun-validation-run.md`.
- Required evidence artifacts updated by slice: `verification/tun-live-complete-matrix.md`, `reports/tun-live-complete-report.md`.
- Root output path: `reports/root-owner-next-tun-validation-run.md`.

## Spec compliance
- Preflight cleanup/status:
  - Status: partial.
  - Evidence: known old `vibe-practicum` TUN leftovers checked/cleaned; production metadata for `vibe-practicum` `vpnkit` and `moscow-tiger` `current-vpnkit-1` recorded before/after unchanged in `verification/tun-live-complete-matrix.md`.
  - Gap: one final exact-name cleanup command for older known `moscow-tiger` leftovers timed out; no fresh moscow resources were created by this run.
- Live TUN harness:
  - Status: done for feasible local-host stages.
  - Evidence: fresh isolated resources `vpnkit_tun_live_21741`, `vpnkit_tun_inner_21742`, `vpnkit_tun_net_21741_21742`, local client `vpnkit-tun-local-nested-21741`; temp paths under exact `/tmp/vpnkit_tun*21741/21742*`; cleanup recorded.
- Stage A local-host -> isolated `vibe-practicum` TUN server:
  - Status: baseline passed, fresh public echo not rerun.
  - Evidence: outer OpenVPN `tun0`, UDP DNS `NOERROR`, HTTPS `200`, literal-IP HTTPS `200`, `sb-tun0` counters/routing, no redirect/tproxy capture chains. Fresh public UDP echo was blocked by `moscow-tiger` SSH instability; prior same-topology public UDP proof remains in existing package evidence.
- Stage B local-host nested OpenVPN:
  - Status: failed/partial.
  - Evidence: outer `tun0` up; route to inner endpoint via outer tunnel; sing-box TUN logged packet/direct outbound to inner endpoint; inner `tun1` did not appear; TLS handshake timed out.
- Stage C/D `moscow-tiger` client stages:
  - Status: blocked/not run.
  - Evidence: `moscow-tiger` SSH timed out during preflight/fresh setup; no fresh moscow client mutation performed.
- Documentation:
  - Status: done.
  - Evidence: `tun-live-complete-matrix.md`, `tun-live-complete-report.md`, slice report, this root report.
- Commit/push:
  - Status: safe docs/report commits exist; not pushed by root because the root task ended blocked/partial rather than successful.
  - Evidence: slice commit `6176a75 Document TUN live validation run`; root report commit is this commit (`Record root TUN validation verdict`).

## Acceptance verification
- AC: Production containers untouched.
  - Covered by: before/after safe metadata only.
  - Result: passed for observed metadata.
  - Evidence: `vpnkit` and `current-vpnkit-1` stayed `running`, restart count `0`, unchanged start time.
- AC: Use isolated resources and exact cleanup.
  - Covered by: fresh resource names/ports and cleanup section in matrix.
  - Result: passed for fresh local/`vibe-practicum` resources; partial for older moscow known-leftover recheck due SSH timeout.
- AC: Stage A baseline and TUN runtime evidence.
  - Covered by: matrix Stage A.
  - Result: passed except fresh public echo rerun.
  - Evidence: OpenVPN, DNS/HTTPS/literal, counters, rules/chains evidence.
- AC: Stage B nested.
  - Covered by: matrix Stage B and slice issue U-01.
  - Result: failed/partial.
  - Evidence: route via `tun0`, TUN packet evidence, TLS timeout/no `tun1`.
- AC: Stage C/D different-host validation.
  - Covered by: attempted preflight/setup.
  - Result: blocked.
  - Evidence: intermittent `moscow-tiger` SSH timeout; production metadata later reachable/unchanged; no fresh moscow mutation.
- AC: Required checks before final commit.
  - Covered by: fresh commands in slice report and root verification run.
  - Result: passed.
- AC: No secrets/generated artifacts committed.
  - Covered by: committed file list review and docs-only status.
  - Result: passed for reviewed changes.

## System readiness
- Routes / registration: TUN baseline route/counter behavior is ready for guarded canary planning only if nested and different-host validation are excluded.
- Services / APIs: not applicable.
- Config / env / secrets: private endpoint values were not printed; generated profiles/rendered material stayed temp/gitignored.
- Permissions / access: `vibe-practicum` access was usable; `moscow-tiger` SSH instability blocked Stage C/D and fresh public echo rerun.
- Runtime / deployment wiring: no production deployment or container mutation occurred.

## Verification run
- Slice-level final checks:
  - `bash tests/vpnkit-singbox-template-test.sh`: passed.
  - `bash tests/vpnkit-setup-routing-test.sh`: passed.
  - `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh`: passed.
  - `go test ./...`: passed.
  - `git diff --check`: passed.
- Root-level integration checks after writing this report:
  - `bash tests/vpnkit-singbox-template-test.sh`: passed.
  - `bash tests/vpnkit-setup-routing-test.sh`: passed.
  - `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh`: passed.
  - `go test ./...`: passed.
  - `git diff --check`: passed.
- Remote checks / CI:
  - Not run / not available because blocked result was not pushed as a success.

## Issues
### Issue U-01: Nested OpenVPN over TUN did not complete
- Description: Stage B reached the inner endpoint through the outer TUN path, but inner OpenVPN did not establish.
- Evidence: `ip route get` used outer `tun0`; filtered sing-box TUN/direct packet evidence; no inner `tun1`; TLS handshake timeout.
- Why unresolved: Requires further isolated runtime debugging beyond the safe completed run.
- Needed next: Retry nested with additional inner-network packet/conntrack evidence or reduced UDP echo to same inner endpoint.

### Issue U-02: `moscow-tiger` SSH instability blocked Stage C/D
- Description: Fresh different-host client validation and fresh public UDP echo rerun could not be safely started.
- Evidence: SSH timeout during preflight/fresh setup; later production metadata recheck showed unchanged `current-vpnkit-1`.
- Why unresolved: External host reachability instability.
- Needed next: Retry exact known cleanup and Stage C/D when SSH is stable.

## Side findings
- Blocking findings folded into active work: U-01, U-02.
- Non-blocking follow-up candidates: none recorded separately.

## Verdict
- Status: partial / blocked.
- Goal state: partially achieved.
- Final readiness: not ready as complete A-D validation. Baseline TUN canary planning is reasonable only with explicit exclusions for nested OpenVPN and different-host validation.
- Summary: Stage A baseline live TUN validation passed on isolated `vibe-practicum` resources and cleanup was completed for fresh resources; nested and `moscow-tiger` stages remain blockers, so the branch was not pushed as successful.

## Next-agent brief
- Objective: Complete missing TUN validation evidence after host reachability stabilizes.
- Target: Exact-name moscow leftover cleanup/status, Stage C public/baseline checks, Stage D nested check, and deeper Stage B nested debugging.
- Settled already: production metadata stayed unchanged; fresh local/`vibe-practicum` resources from ports `21741/21742` were cleaned; Stage A baseline passed.
- Boundaries: Maintain all no-production-mutation/no-secret/no-broad-`/tmp` constraints.
- Verification target: Full Stage A-D matrix from `next-tun-validation-task.md` or decisive sanitized blocker evidence.
