# Final report — Moscow tiger runtime smoke fix

## Task
- Mission: Diagnose and fix the existing `moscow-tiger` Docker `vpnkit` runtime after an independent client smoke showed OpenVPN and DNS success but HTTPS timeout.
- Target: Existing `moscow-tiger` Docker runtime and host Docker OpenVPN client smoke.
- Boundaries: No Vercel/DNS, no Steam Deck, no unrelated deployment mutation, and no committed/revealed private endpoint values or generated artifacts.
- Done when: Runtime root cause is classified, minimal fix is applied if safe, and DNS/HTTPS/literal-IP/RU smoke is green; or a hard blocker is reported with evidence.

## Context
- Task package: `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix`
- Plan: `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/plan.md`
- Slice report: `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/reports/slice-owner-runtime-diagnosis-fix.md`
- Verification artifact: `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/verification/runtime-smoke.md`
- Worktree: `.worktrees/moscow-tiger-runtime-smoke-fix`
- Branch: `aad/moscow-tiger-runtime-smoke-fix`

## Slice structure used
- One slice: runtime diagnosis, minimal fix, and smoke verification.
- Reason: one target, one runtime ownership boundary, one acceptance story, and no useful parallelism until target access/root cause classification succeeds.

## Integrated slice outcome
- Slice owner could not inspect or mutate the live runtime.
- First blocker: `config/private-endpoints.local.env` was absent in the worktree.
- Root owner copied the gitignored local endpoint file from the main checkout into the worktree.
- Second/current blocker: the copied local file contains the example placeholder SSH target, so the narrow live-read gate failed before reaching `moscow-tiger`.
- No runtime fix, source change, or live mutation was applied.

## Spec compliance
- AC1 Reproduce/classify reported failure: blocked; target access could not begin.
- AC2 Inspect Docker logs/config/processes/routes/iptables: blocked; no resolvable SSH target.
- AC3 Targeted direct-out/selected-native/proxy/route/DNS checks: blocked; no live container access.
- AC4 Minimal safe fix: not applicable; no confirmed root cause.
- AC5 Fresh client smoke green: blocked; no usable target/profile access from this environment.
- AC6 Public-safety check: passed for current artifacts; no private values were printed, staged, or committed.

## Acceptance verification
- Private endpoint gate:
  - Result: failed/blocking.
  - Evidence: after sourcing the gitignored file, `ssh -o BatchMode=yes "$VPNKIT_VPS_SSH_HOST" ...` failed with unresolved example placeholder host.
- Public-safety gate:
  - Result: passed for current work.
  - Evidence: `git status --short` shows only the untracked task package; ignored private env remains ignored.
- Source/runtime tests:
  - Result: not run.
  - Reason: no source/runtime change was made.

## System readiness
- Config/env/secrets: not ready; operator-local endpoint inventory is not populated with usable `moscow-tiger` access values in this environment.
- Runtime/deployment wiring: not verified.
- Docker/OpenVPN/sing-box routes: not verified.
- CI/remote checks: not available; branch not pushed.

## Issues
### U-01: Placeholder private endpoint inventory blocks live diagnosis
- Description: The required gitignored endpoint file exists in the worktree but contains an example SSH target rather than a usable `moscow-tiger` target.
- Evidence: slice report and `verification/runtime-smoke.md` record the sanitized failed SSH gate.
- Needed next: populate `config/private-endpoints.local.env` with operator-local `moscow-tiger` SSH/client-smoke values, then rerun the existing slice packet.

## Side findings
- Blocking findings folded into active work: U-01.
- Non-blocking follow-ups: none.

## Verdict
- Status: blocked.
- Goal state: not achieved.
- Final readiness: not ready.
- Summary: The task cannot be completed from this environment until the gitignored private endpoint inventory contains usable `moscow-tiger` access values. No failures were hidden and no unsafe mutation was attempted.

## Next-agent brief
- Objective: Continue diagnosis/fix once usable `moscow-tiger` private endpoint values are available.
- Target: Existing `moscow-tiger` Docker `vpnkit` runtime and fresh host Docker OpenVPN client smoke.
- Settled already: Task package and plan exist; current blocker is access/config, not a classified runtime bug.
- Boundaries: Keep private endpoints, profiles, rendered configs, subscriptions, auth files, logs, snapshots, and raw secrets out of tracked artifacts.
- Verification target: AC1-AC5 with sanitized runtime evidence; AC6 with `git status --short` and public-safety grep before any commit.
