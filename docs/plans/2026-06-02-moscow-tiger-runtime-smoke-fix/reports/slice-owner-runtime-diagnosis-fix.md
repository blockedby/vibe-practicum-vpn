## Task
- Mission: Continue diagnosing and fixing the existing `moscow-tiger` Docker `vpnkit` runtime after `config/private-endpoints.local.env` was copied into the worktree.
- Target: Existing `moscow-tiger` Docker runtime and fresh host Docker OpenVPN client smoke.
- Boundaries: No Vercel/DNS/Steam Deck/unrelated deployment mutation. Do not commit or reveal real endpoints, SSH aliases, private domains, generated profiles, rendered configs, subscription URLs, auth values, or raw logs.
- Done when: AC1-AC6 are proven, or a hard blocker prevents safe live work.
- Expected evidence: Sanitized runtime evidence, targeted diagnosis, minimal fix if confirmed, fresh smoke result, public-safety check.

## Context
- Thread: User reported OpenVPN connects and DNS succeeds, but hostname HTTPS times out from a Docker client smoke against the `moscow-tiger` public UDP endpoint.
- Slice: single root slice — runtime diagnosis, minimal fix, and smoke verification.
- Task name: Moscow tiger runtime smoke fix
- Task package: `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix`
- Report path: `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/reports/slice-owner-runtime-diagnosis-fix.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/moscow-tiger-runtime-smoke-fix`
- Branch: `aad/moscow-tiger-runtime-smoke-fix`
- Verify scope: `moscow-tiger` Docker runtime plus fresh host Docker OpenVPN client smoke.

## Root-cause classification
- Status: unresolved / access-blocked.
- Classification possible from current evidence: the reported symptom remains consistent with a post-DNS TCP egress/routing/proxy-selection problem, but this owner still could not safely inspect or mutate the live runtime to prove redirect/routing vs selected-native/proxy outbound vs DNS hijack vs route matching vs upstream selection.
- Blocking fact: `config/private-endpoints.local.env` is now present, but its VPS SSH target value is still the example placeholder (`your-vps-ssh-alias`) and is not resolvable. The live gate failed before reaching `moscow-tiger`.

## Fix summary
- No runtime or repo source fix was applied.
- Reason: after sourcing `config/private-endpoints.local.env`, the narrow SSH read gate failed with `Could not resolve hostname your-vps-ssh-alias`. The copied file is present but not populated with usable operator-local endpoint values.
- Only task-package markdown was updated: `plan.md`, `verification/runtime-smoke.md`, and this report.
- Commit hash: none; no public source/docs change requiring a commit was made beyond task-package artifacts.

## Spec compliance
- AC1 reproduce/classify failure
  - Status: missing / blocked
  - Evidence: continuation live gate failed before target access; see `verification/runtime-smoke.md`.
  - Gap: populate `config/private-endpoints.local.env` with a usable operator-local `VPNKIT_VPS_SSH_HOST` for `moscow-tiger`.
- AC2 inspect runtime state
  - Status: missing / blocked
  - Evidence: no live Docker commands ran because the SSH target was the unresolved example placeholder.
  - Gap: target containers/logs/config/processes/listeners/routes/iptables/nftables still need inspection.
- AC3 targeted route/outbound/DNS/upstream checks
  - Status: missing / blocked
  - Evidence: in-container checks require target access.
  - Gap: checks still need to distinguish redirect/routing, selected native/proxy outbound, DNS hijack, route matching, and upstream/proxy selection.
- AC4 minimal safe fix
  - Status: not applicable yet
  - Evidence: no confirmed blocker root cause.
  - Gap: apply only after AC1-AC3 classify the cause.
- AC5 fresh host Docker client smoke
  - Status: missing / blocked
  - Evidence: client smoke requires usable endpoint/profile access not available here.
  - Gap: rerun DNS, hostname HTTPS, literal-IP HTTPS, and RU/2ip-style probes after diagnosis/fix.
- AC6 public-safety check
  - Status: done for current work
  - Evidence: values were not printed; `git status --short` shows only the untracked task package; no private files were staged or committed.
  - Gap: none for current blocked attempt.

## Acceptance verification
- AC1: Reproduce/classify reported failure with sanitized evidence
  - Covered by: attempted continuation pre-live gate only
  - Result: blocked
  - Evidence: `ssh -o BatchMode=yes "$VPNKIT_VPS_SSH_HOST" ...` failed with unresolved placeholder host after sourcing the local env file.
- AC2: Inspect `moscow-tiger` runtime state
  - Covered by: not run
  - Result: blocked
  - Evidence: no resolvable VPS SSH target.
- AC3: Targeted checks for redirect/routing/native/proxy/DNS/route/upstream
  - Covered by: not run
  - Result: blocked
  - Evidence: no resolvable VPS SSH target.
- AC4: Minimal safe fix
  - Covered by: not run
  - Result: not applicable
  - Evidence: no classified root cause.
- AC5: Fresh Docker OpenVPN client smoke green or honest blocker
  - Covered by: blocker evidence
  - Result: blocked honestly
  - Evidence: `verification/runtime-smoke.md` records present-but-placeholder endpoint file and stop condition.
- AC6: Public-safety check
  - Covered by: redacted env inspection and `git status --short`
  - Result: passed for current work
  - Evidence: no private endpoint values or artifacts printed/staged/committed; task artifacts contain placeholders/path names only.

## System readiness
- Routes / registration: not verified; live runtime blocked.
- Services / APIs: not relevant.
- Config / env / secrets: blocked; local env file is present but still has placeholder VPS SSH target.
- Permissions / access: blocked; no usable live target access value available.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: not ready; runtime diagnosis/fix/smoke not performed.

## Verification run
- Local / targeted checks:
  - `sed -n '1,120p' config/private-endpoints.local.env | sed -E 's/(=).*/=REDACTED/'`: passed as a public-safety check; confirms file presence without printing values.
  - `ssh -o BatchMode=yes "$VPNKIT_VPS_SSH_HOST" ...`: failed before live access; safe error was `Could not resolve hostname your-vps-ssh-alias`.
  - `git status --short`: passed; shows untracked task-package directory only.
- Local / full checks:
  - Source/runtime tests: not run; no source/runtime changes made.
- Remote checks / CI:
  - Status: not available before push; branch was not pushed by this owner.

## Issues
### Issue U-01: Placeholder private endpoint inventory blocks live diagnosis
- Description: The active worktree now contains `config/private-endpoints.local.env`, but it appears to be the example/template content rather than a populated operator-local file. `VPNKIT_VPS_SSH_HOST` resolves to the documented placeholder `your-vps-ssh-alias`, so live access cannot begin.
- Evidence: after sourcing the file, the narrow SSH read gate failed with `Could not resolve hostname your-vps-ssh-alias: Name or service not known`.
- Why unresolved: external/operator-local secret/access boundary; this owner must not invent or expose private endpoint values.
- Needed next: replace the placeholder local file with a populated gitignored `config/private-endpoints.local.env` containing the usable `moscow-tiger` VPS SSH alias/endpoint and any required client-smoke endpoint/profile values, then rerun AC1-AC5.
- Depends on: operator-provided private endpoint values/access.

## Side findings
- Blocking findings folded into active work: U-01.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: blocked
- Goal state: not achieved
- Final readiness: not ready
- Summary: The previous absent-file blocker is superseded, but live work remains blocked because the copied local endpoint file is still placeholder content; no root cause, fix, or smoke pass can be honestly claimed.

## Next-agent brief
- Objective: Continue the `moscow-tiger` runtime diagnosis/fix/smoke after the gitignored endpoint file is populated with real operator-local values.
- Target: Existing `moscow-tiger` Docker `vpnkit` runtime and fresh host Docker OpenVPN client smoke.
- Settled already: Public-safety rules are active; the task package and plan exist; copied env file is present but unusable because `VPNKIT_VPS_SSH_HOST` is the example placeholder; no source/runtime changes have been made by this owner.
- Boundaries: Do not reveal or commit private endpoint values, generated profiles, rendered configs, subscription URLs, auth files, raw logs, snapshots, or private hostnames.
- Verification target: AC1-AC5 with sanitized evidence in `verification/runtime-smoke.md`; AC6 via `git status --short` and public-safety review before commit/final report.
- Expected output: Root-cause classification, minimal fix summary if any, fresh smoke matrix, commit hash if public-safe repo changes are made, and updated plan/report artifacts.
