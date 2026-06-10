## Task
- Mission: Integrate issue #27 Steam Deck test-lab lifecycle runner and 2026-06-10 live hang remediation results.
- Target: PR #26 branch `feat/issue-24-smart-routing-manifest`, issue #27 isolated Steam Deck lab scope.
- Boundaries: No default/prod `vpnkit` mutation; no committed/generated secrets, profiles, PEM/key/cert material, rendered private configs, raw logs, or private endpoints.
- Done when: lifecycle implementation is present, hang-prone live paths are bounded, safe verification passes, PR/issue are updated, and live Deck cycle is either green or precisely blocked.

## Context
- GitHub issue: https://github.com/blockedby/vibe-practicum-vpn/issues/27
- Related PR: https://github.com/blockedby/vibe-practicum-vpn/pull/26
- Related issue: #24
- Task package: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle`
- Latest slice report: `reports/slice-owner-live-hang-remediation.md`
- Latest verification: `verification/live-hang-remediation.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
- Branch: `feat/issue-24-smart-routing-manifest`

## Spec compliance
- AC1 lifecycle command: done. `test/containers-test.sh --scenario steamdeck-host --action up|test|down|cycle` exists and is documented.
- AC2 isolated lab defaults/no prod container: done. Defaults use `vpnkit-test-steamdeck-host`, `localhost/vpnkit:test-steamdeck-host`, isolated remote lab state, and UDP `21194`; helper refuses default `vpnkit` unless explicitly overridden.
- AC3 gitignored generated artifacts: done. Lab artifacts remain under ignored `secrets/`/`logs/`; tracked docs/template are public-safe.
- AC4 isolated test PKI and production-like rendering: done. Lab generation uses throwaway test material and existing sing-box/OpenVPN templates/rule sets.
- AC5 lab `tun` mode: done. Lab defaults to `tun`; `sb-tun0` checks are mode-aware.
- AC6 disabled `vibe-vpn` daemon/subscription: done for lab path.
- AC7 explicit missing/placeholder prerequisites: done; placeholders fail fast with clear diagnostics.
- AC8 honest matrix: done; unavailable/unaccepted paths are reported as FAIL/SKIP rather than green.
- AC9 safe repo checks: passed again at root after latest commits.
- AC10 live Deck cycle: partial/blocked. Latest live `down` passed; `up` returned bounded failure instead of hanging; `test` returned bounded failure with client smoke skipped; `cycle` was not run because `up` failed.
- AC11 PR #26 / issue #27 updates: done with public-safe comments and pushed commits.

## Acceptance verification
- Hang diagnosis and remediation:
  - Covered by: code inspection plus fresh bounded live `up`/`test` evidence.
  - Result: passed for hang class.
  - Evidence: `verify_container` now bounds `podman ps`, finite logs, process probes, `sing-box check`, subscription probe, and `vibe-vpn doctor`; `test` skips client smoke when the explicit Steam Deck server container is unavailable.
- Live lab sequence:
  - Covered by: live commands in `verification/live-hang-remediation.md`.
  - Result: partial/blocked.
  - Evidence: `down` PASS; `up` bounded FAIL due sing-box remote RU `.srs` rule-set download `unexpected EOF`; `test` bounded FAIL/server unavailable/client smoke skipped; final cleanup `down` PASS; `cycle` not run after failed `up`.
- Public-safety:
  - Covered by: redacted env handling and tracked-file check.
  - Result: passed.
  - Evidence: no tracked `.ovpn`, PEM/key/cert/log/secrets paths; endpoint was not printed or committed.
- GitHub updates:
  - Covered by: pushed commits and public comments.
  - Result: passed.
  - Evidence: issue comment https://github.com/blockedby/vibe-practicum-vpn/issues/27#issuecomment-4667492219 and PR comment https://github.com/blockedby/vibe-practicum-vpn/pull/26#issuecomment-4667492399.

## System readiness
- Config / env / secrets: public-safe; real private Deck values stayed local. No tracked sensitive artifacts.
- Runtime / deployment wiring: partial. Lifecycle no longer hangs on the previous verify/doctor/client-smoke paths, but live container startup currently depends on successful outbound RU rule-set downloads from GitHub.
- Production readiness: not claimed; Steam Deck remains isolated test/lab only.

## Verification run
- Slice verification:
  - `bash -n scripts/vpnkit-steamdeck-podman.sh test/containers-test.sh`: PASS
  - `bash -n scripts/*.sh test/*.sh`: PASS
  - `python3 test/sing-box-smart-routing-proof.py`: PASS
  - `go test ./...`: PASS
  - `go vet ./...`: PASS
  - `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: PASS
  - tracked sensitive artifact grep: PASS
  - PR checks: no checks reported on branch.
- Root re-verification after integration:
  - `bash -n scripts/vpnkit-steamdeck-podman.sh test/containers-test.sh`: PASS
  - `python3 test/sing-box-smart-routing-proof.py`: PASS
  - `go test ./...`: PASS
  - `go vet ./...`: PASS
  - `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: PASS
  - tracked `.ovpn/.pem/.key/.crt/logs/secrets` path check: PASS
  - `git status --short --branch`: clean relative to tracked files, branch at `origin/feat/issue-24-smart-routing-manifest` before this final report update.

## Issues
### Issue R-01: Initial lifecycle implementation
- Resolution: Added lifecycle runner, lab setup generator, Podman helper safety/config updates, docs/template, and task evidence.
- Evidence: commit `f789c4b feat: add steamdeck lab lifecycle runner`.

### Issue R-02: Placeholder env and first timeout remediation
- Resolution: Added placeholder rejection, unified SSH/endpoint precedence, and configurable remote timeouts.
- Evidence: commit `83fd2d4 fix: bound steamdeck lab live prerequisites`.

### Issue R-03: Verify/doctor/client-smoke hang class
- Description: A previous live run appeared hung after deploy/log output. The most likely script-level hang class was unbounded inner verify/doctor `podman exec` operations plus client smoke running after server startup failure.
- Resolution: Wrapped the relevant verify/log/exec/doctor operations with finite timeouts and skipped client smoke when the explicit Steam Deck server container is unavailable.
- Evidence: commit `b723068 fix: bound steamdeck lab verify hangs`; latest `up`/`test` returned boundedly.

### Issue U-01: Green live `cycle` is blocked by remote RU rule-set fetch failure
- Description: The isolated lab now returns boundedly, but sing-box exits during startup while downloading remote RU `.srs` rule sets from GitHub with `unexpected EOF`.
- Evidence: `verification/live-hang-remediation.md` summarizes the redacted live output and matrix.
- Why unresolved: Current evidence points to Deck outbound/network/rule-set availability, not the previous lifecycle hang. Changing rule-set sourcing/caching semantics needs a separate scoped acceptance decision.
- Needed next: Decide whether the lab should vendor/cache RU `.srs` files, make the live lab fail with a documented outbound prerequisite, or add a lab-specific fallback that preserves intended smart-routing acceptance.

## Side findings
- Blocking findings folded into active work: R-03 resolved; U-01 remains blocking for issue #27 done-state.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: partial / blocked.
- Goal state: hang remediation achieved and safely verified; issue #27 live acceptance not achieved.
- Final readiness: not ready for issue closure because no green `cycle` exists.
- Summary: The prior 13h hang class is bounded now and isolated cleanup completed; the remaining blocker is a live Deck sing-box startup failure caused by remote RU rule-set download EOF.

## Next-agent brief
- Objective: Resolve U-01 or record an explicit accepted environment blocker, then rerun the full bounded live `cycle`.
- Target: `steamdeck-host` sing-box rule-set availability/startup behavior.
- Settled already: lifecycle command, isolated lab safety, placeholder handling, verify/doctor/log/client-smoke timeouts.
- Boundaries: isolated `vpnkit-test-steamdeck-host` only; no prod/default `vpnkit`; no private endpoint/log/profile/key/cert disclosure.
- Verification target: green `test/containers-test.sh --scenario steamdeck-host --action cycle`, or public-safe blocked status with a precise outbound/rule-set prerequisite.
