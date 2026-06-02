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

---

## Task
- Mission: Finalize the user-confirmed `moscow-tiger` OpenVPN MTU/MSS hotfix in tracked source/docs/evidence and attempt source-based deploy/smoke gating.
- Target: `config/openvpn/server.tpl`, render guard/docs, task-package evidence, and `moscow-tiger` source-based runtime readiness.
- Boundaries: No Vercel/DNS/Steam Deck/unrelated deployment mutation. No private endpoint values, rendered configs, generated profiles, subscription URLs, auth files, logs, or secrets printed or committed.
- Done when: source render contains `tun-mtu 1400` and `mssfix 1360`, guard/docs/evidence are public-safe, and source-deployed runtime plus baseline/2ip smoke pass or are honestly blocked.
- Expected evidence: source diff, local render grep, checks, deploy/smoke evidence or access blocker.

## Context
- Thread: User reports live root cause is MTU/MSS; manual live OpenVPN config hotfix made baseline smoke pass.
- Slice: single implementation/runtime-finalization slice; stayed whole.
- Task package: `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix`
- Report path: `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/reports/slice-owner-runtime-diagnosis-fix.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/moscow-tiger-runtime-smoke-fix`
- Branch: `aad/moscow-tiger-runtime-smoke-fix`
- Verify scope: OpenVPN render source, public-safe docs/evidence, source-based live deploy/smoke if private endpoint access is usable.

## Spec compliance
- Source durability (`mssfix 1360`, `tun-mtu 1400` in correct render source)
  - Status: done locally.
  - Evidence: `config/openvpn/server.tpl`; `internal/config/openvpn_template_test.go`; throwaway render grep showed both directives in rendered `server.conf`.
  - Gap if any: live source-based deployment not confirmed from this environment.
- Guard/docs/evidence
  - Status: done locally.
  - Evidence: `go test ./internal/config`; `docs/DOCKER_SETUP.md`; `verification/runtime-smoke.md`.
  - Gap if any: none for source/docs.
- Runtime deployment
  - Status: blocked here.
  - Evidence: `config/private-endpoints.local.env` still has the example SSH placeholder; SSH fails before target access.
  - Gap if any: operator/root owner must provide usable gitignored endpoint values or perform deploy/smoke externally.
- Subscription/extra-nodes safety
  - Status: done locally.
  - Evidence: docs record gitignored `sub_url`; throwaway render wrote `extra-nodes=[]`; no values printed.
  - Gap if any: none locally.
- Fresh baseline smoke and explicit 2ip smoke after source deploy
  - Status: blocked here.
  - Evidence: no usable live endpoint/profile access; user-provided manual-hotfix baseline smoke pass is recorded as historical evidence only.

## Acceptance verification
- AC1 source durability
  - Covered by: template grep, Go guard, throwaway render grep.
  - Result: passed locally.
  - Evidence: `grep -nE '^(tun-mtu 1400|mssfix 1360)$' config/openvpn/server.tpl`; rendered server grep showed lines 8-9.
- AC2 guard/docs
  - Covered by: `go test ./internal/config`, docs/task-package updates.
  - Result: passed locally.
  - Evidence: `go test ./internal/config` passed; `docs/DOCKER_SETUP.md` documents MTU/MSS rationale and gitignored subscription/extra-nodes handling.
- AC3 runtime deployment
  - Covered by: pre-live endpoint gate.
  - Result: blocked.
  - Evidence: SSH failed before live access because `VPNKIT_VPS_SSH_HOST` is still `your-vps-ssh-alias` in the gitignored local file.
- AC4 subscription/extra-nodes safety
  - Covered by: render check and public-safety review.
  - Result: passed locally.
  - Evidence: throwaway render produced `extra-nodes=[]`; no `sub_url` value or rendered config content was stored.
- AC5 baseline smoke after source deploy
  - Covered by: not run from this branch/source.
  - Result: blocked here.
  - Evidence: no live access/profile due placeholder endpoint; user-reported manual-hotfix baseline pass recorded separately.
- AC6 explicit 2ip smoke
  - Covered by: not run.
  - Result: blocked here.
  - Evidence: same endpoint/profile blocker.
- AC7 relevant repo checks/public safety
  - Covered by: local checks and git review.
  - Result: passed locally before commit pending final status review.
  - Evidence: `bash -n scripts/*.sh`, `go test ./...`, `git diff --check` passed.

## System readiness
- Routes / registration: runtime readiness blocked here; user-reported live hotfix pass suggests route path works when MTU/MSS is present.
- Services / APIs: not relevant.
- Config / env / secrets: source config ready; operator-local endpoint file remains placeholder in this environment.
- Permissions / access: blocked for live deploy/smoke.
- Runtime / deployment wiring: source render ready; live source-based redeploy not confirmed here.

## Verification run
- Local / targeted checks:
  - `go test ./internal/config`: passed.
  - `bash -n scripts/*.sh`: passed.
  - `grep -nE '^(tun-mtu 1400|mssfix 1360)$' config/openvpn/server.tpl`: passed.
  - Throwaway `VPNKIT_SECRETS_DIR=$tmp scripts/vpnkit-render-local-configs.sh` plus rendered grep: passed for OpenVPN directives; extra-nodes fallback emitted `[]`.
  - `git diff --check`: passed.
- Local / full checks:
  - `go test ./...`: passed.
- Remote checks / CI:
  - Status: not available before push; this owner has not pushed.

## Issues
### Issue R-01: MTU/MSS source durability
- Description: The live fix was previously only manual runtime state.
- Evidence: tracked OpenVPN template lacked MTU/MSS directives before this pass.
- Resolution: Added `tun-mtu 1400` and `mssfix 1360` to `config/openvpn/server.tpl`, added a Go guard, and documented the public-safe rationale.
- Depends on: none.

### Issue U-01: Source-based deploy and fresh smokes blocked by placeholder endpoint file
- Description: This worktree cannot SSH to `moscow-tiger` or run fresh host Docker client/2ip smokes because the gitignored endpoint file still contains the example SSH placeholder.
- Evidence: SSH pre-live gate fails before access with unresolved `your-vps-ssh-alias`.
- Why unresolved: external/operator-local private endpoint boundary.
- Needed next: provide usable gitignored endpoint/profile/secrets in this worktree or have root/operator run source render/deploy and smokes, then append sanitized evidence.
- Depends on: operator-local private endpoint values/access.

## Side findings
- Blocking findings folded into active work: U-01.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: partial.
- Goal state: source durability achieved; final runtime acceptance not achieved in this environment.
- Final readiness: ready for root/operator source-based deploy/smoke, not ready to claim complete runtime finalization.
- Summary: The branch now persists the MTU/MSS fix and proves local render durability, but live source-deploy, fresh baseline smoke, and 2ip smoke remain blocked here by placeholder private endpoint access.

## Next-agent brief
- Objective: Complete source-based live deployment and final smokes using usable gitignored endpoint/secrets.
- Target: `moscow-tiger` Docker/Podman runtime from branch `aad/moscow-tiger-runtime-smoke-fix` rendered source.
- Settled already: MTU/MSS root cause is accepted from user live evidence; source template and guard are in place; do not re-open broad diagnosis first.
- Boundaries: keep all endpoints, profiles, rendered configs, subscriptions, auth files, logs, and private values out of tracked files/chat.
- Verification target: confirm running OpenVPN config includes `tun-mtu 1400` and `mssfix 1360` from source render; fresh host Docker client tunnel/DNS/HTTPS/literal-IP; explicit 2ip route evidence.
- Expected output: sanitized deploy/render evidence, smoke matrix, commit hash/push status if committed, blockers if any.
