## Task
- Mission: Remediate issue #27 live-attempt blockers before another Steam Deck lab lifecycle run.
- Target: `test/containers-test.sh`, `scripts/deck/vpnkit-steamdeck-podman.sh`, README/template docs, task verification.
- Boundaries: Do not touch prod/default `vpnkit`; do not print/commit secrets, generated profiles, logs, or private endpoints.
- Done when: placeholders fail fast, remote operations are bounded, docs/templates are updated, safe checks pass, and live status is classified.

## Context
- Thread: Root live attempt timed out after placeholder env was treated as usable.
- Slice: Issue #27 Steam Deck test-lab lifecycle runner live remediation.
- Task package: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle`
- Report path: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/reports/slice-owner-live-remediation.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
- Branch: `feat/issue-24-smart-routing-manifest`
- PR: https://github.com/blockedby/vibe-practicum-vpn/pull/26

## Spec compliance
- Reject documented placeholder values for explicit `steamdeck-host`: done.
  - Evidence: placeholder negative cycle command exited `rc=1` with `ssh_target_state=placeholder`, `endpoint_state=placeholder`, `FAIL lifecycle:prereq-ssh` before cleanup, and `FAIL lifecycle:prereq-endpoint` before deploy.
- SSH precedence: done.
  - Evidence: harness/helper derive `VPNKIT_TEST_SSH_TARGET` -> `VPNKIT_STEAMDECK_SSH_TARGET` -> `VPNKIT_STEAMDECK_SSH_HOST` -> `deck`; README/template updated.
- Endpoint precedence/non-placeholder requirement: done.
  - Evidence: harness requires non-placeholder `VPNKIT_TEST_ENDPOINT` or `VPNKIT_STEAMDECK_LAN_ENDPOINT`; placeholder test failed before deploy.
- Bounded remote operations: done.
  - Evidence: configurable timeouts added for harness SSH probes, remote command exec, deploy, client smoke; helper build/run/logs/verify and generic remote commands.
- Public-safe docs/templates: done.
  - Evidence: README and `config/private-endpoints.example.env` updated with precedence and timeout knobs; no real private values added.

## Acceptance verification
- AC1 `bash -n scripts/*.sh test/*.sh` passes.
  - Result: passed.
- AC2 placeholder scenario env check exits nonzero quickly with clear FAIL.
  - Result: passed. Safe placeholder-only cycle command exited `rc=1` immediately with prerequisite FAILs and no cleanup/deploy.
- AC3 safe local repo checks as needed.
  - Result: passed. `python3 -m py_compile scripts/*.py test/*.py`; `python3 test/sing-box-smart-routing-proof.py`.
- AC4 bounded live cycle with real private values if available.
  - Result: not run. `config/private-endpoints.local.env` absent; endpoint state missing. Classified as U-01.

## System readiness
- Routes / registration: not relevant.
- Services / APIs: not relevant.
- Config / env / secrets: ready except live private Deck env absent locally.
- Permissions / access: blocked for live Deck acceptance by absent private env.
- Runtime / deployment wiring: script-level remediation ready; live cycle still requires real Deck endpoint/SSH env.

## Verification run
- Local / targeted checks:
  - `bash -n scripts/*.sh test/*.sh`: passed.
  - Placeholder negative `steamdeck-host --action up`: passed expected failure behavior (`rc=1`, clear FAIL diagnostics).
  - `python3 -m py_compile scripts/*.py test/*.py`: passed.
  - `python3 test/sing-box-smart-routing-proof.py`: passed.
- Remote checks / CI:
  - Status: pending push/PR update at time of report creation.

## Issues
### Issue R-01: Placeholder examples accepted as usable live prerequisites
- Description: Explicit `steamdeck-host` treated example values as usable (`endpoint_set=yes`, placeholder SSH target shown).
- Evidence: Root sanitized live attempt plus local placeholder negative reproduction.
- Resolution: Added placeholder classifier for `your-*`, `*.invalid`, `192.0.2.*`, `203.0.113.*`; explicit scenario fails before deploy with clear diagnostics.

### Issue R-02: Helper used default Deck alias instead of resolved harness target
- Description: Harness selection and helper deployment target could diverge.
- Evidence: Root saw harness placeholder target while helper still used default `deck` alias.
- Resolution: Unified precedence in harness/helper and exported resolved target to helper for explicit lab lifecycle.

### Issue R-03: Remote deploy/verify/client operations could hang until outer timeout
- Description: Root cycle timed out after 1800s during remote deploy/verify/log/smoke path.
- Evidence: Root sanitized timeout evidence.
- Resolution: Added configurable timeout wrappers and documented knobs.

### Issue U-01: Live Deck cycle not rerun in this worktree
- Description: No real non-placeholder private Deck endpoint was available locally.
- Evidence: `config/private-endpoints.local.env` absent; sanitized state endpoint `missing`.
- Why unresolved: External/private environment boundary.
- Needed next: Operator/parent with real private Deck bindings should source `config/private-endpoints.local.env` and rerun bounded `test/containers-test.sh --scenario steamdeck-host --action cycle`.

## Side findings
- Blocking findings folded into active work: R-01, R-02, R-03.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: partial success.
- Goal state: script remediation achieved; live acceptance remains blocked by absent private Deck env.
- Final readiness: ready for another bounded live attempt with real non-placeholder Deck env; not live-accepted yet.
