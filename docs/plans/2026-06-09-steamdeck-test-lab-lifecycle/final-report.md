## Task
- Mission: Integrate issue #27 Steam Deck test-lab lifecycle runner work and decide root done-state.
- Target: PR #26 branch `feat/issue-24-smart-routing-manifest`, issue #27 lifecycle runner scope.
- Boundaries: No production/default `vpnkit` mutation; no committed/generated secrets, profiles, PEM/key/cert material, rendered private configs, or private endpoints.
- Done when: lifecycle implementation is present, safe verification passes, PR is updated, and live Deck cycle is either green or precisely blocked.

## Context
- GitHub issue: https://github.com/blockedby/vibe-practicum-vpn/issues/27
- Related PR: https://github.com/blockedby/vibe-practicum-vpn/pull/26
- Related issue: #24
- Task package: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
- Branch: `feat/issue-24-smart-routing-manifest`

## Spec compliance
- AC1 lifecycle command: done. `test/containers-test.sh --scenario steamdeck-host --action up|test|down|cycle` exists and is documented.
- AC2 isolated lab defaults/no prod container: done. Defaults use `vpnkit-test-steamdeck-host`, `localhost/vpnkit:test-steamdeck-host`, `~/.local/state/vpnkit-labs/steamdeck-host`, UDP `21194`; helper refuses default `vpnkit` unless explicitly overridden.
- AC3 gitignored generated artifacts: done. Lab artifacts live under ignored `secrets/vpnkit-labs/steamdeck-host/...`; tracked docs/template are public-safe.
- AC4 isolated test PKI and production-like rendering: done. `scripts/vpnkit-test-lab-setup.sh` generates throwaway cert/profile material and uses existing render/templates/rule sets.
- AC5 lab `tun` mode: done. Lab defaults to `tun`; `sb-tun0` check is mode-aware.
- AC6 disabled `vibe-vpn` daemon/subscription: done. Missing lab `sub_url` is non-fatal for OpenVPN/sing-box path.
- AC7 explicit missing/placeholder prerequisites: done after remediation. Placeholder values fail fast with `FAIL lifecycle:prereq-*`.
- AC8 honest matrix: partial/acceptable limitation. Scaffold policy-visible checks remain `SKIP` and are not counted as green acceptance.
- AC9 safe repo checks: done, all root final checks passed.
- AC10 live Deck cycle: not complete. An initial bounded live attempt reached isolated deploy/startup evidence but timed out; after remediation, available local private file contains no real non-placeholder Deck endpoint/target, so final live cycle is blocked by private environment data.
- AC11 PR #26 update: done. Commits pushed and PR comments added.

## Acceptance verification
- Lifecycle UX / isolation / docs: covered by commits `f789c4b` and `83fd2d4`, shell syntax checks, and placeholder negative harness run. Result: passed for implementation path.
- Config/profile generation: covered by `scripts/vpnkit-test-lab-setup.sh` smoke and no tracked sensitive artifact check. Result: passed locally.
- Safe repo checks: covered by `verification/root-final.md`. Result: passed.
- Live Deck lifecycle: covered by sanitized attempted run plus remediation. Result: blocked, not accepted green. Post-attempt cleanup removed the isolated `vpnkit-test-steamdeck-host` lab container via the helper; production/default `vpnkit` was not targeted.

## System readiness
- Config / env / secrets: public template and docs updated; real private Deck values are still required outside git.
- Runtime / deployment wiring: implemented and bounded with timeouts; needs a real non-placeholder Deck env for final acceptance.
- Production readiness: not claimed; Steam Deck remains test/lab only.

## Verification run
- `bash -n scripts/*.sh test/*.sh`: PASS
- `python3 -m py_compile scripts/*.py test/*.py`: PASS
- manifest validation with disposable public deps (`PyYAML jsonschema`) for test and production intents: PASS
- `python3 test/sing-box-smart-routing-proof.py`: PASS
- `go test ./...`: PASS
- `go vet ./...`: PASS
- `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: PASS
- placeholder/private-file bounded cycle diagnostic: PASS for expected fast prerequisite failure
- tracked `.ovpn/.pem/.key/.crt/.log` check: PASS

## Issues
### Issue R-01: Initial lifecycle implementation
- Resolution: Added lifecycle runner, lab setup generator, Podman helper safety/config updates, docs/template, and task evidence.
- Evidence: commit `f789c4b feat: add steamdeck lab lifecycle runner`.

### Issue R-02: Placeholder env and hang remediation
- Resolution: Added placeholder rejection, unified SSH/endpoint precedence, and configurable remote timeouts.
- Evidence: commit `83fd2d4 fix: bound steamdeck lab live prerequisites`.

### Issue U-01: Live Deck cycle not green
- Description: Final intended live `cycle` could not be accepted green because no real non-placeholder private Deck endpoint/target values are available in this worktree. The absolute local private file checked by root contains placeholder/missing Deck lab values.
- Evidence: `verification/root-final.md`; prior sanitized live attempt timed out before remediation and did not establish a green matrix. Afterward, root ran isolated cleanup for `vpnkit-test-steamdeck-host`; production/default `vpnkit` was not targeted.
- Needed next: operator with real private Deck bindings should source `config/private-endpoints.local.env` containing non-placeholder `VPNKIT_TEST_SSH_TARGET`/`VPNKIT_STEAMDECK_SSH_TARGET`/`VPNKIT_STEAMDECK_SSH_HOST` and `VPNKIT_TEST_ENDPOINT`/`VPNKIT_STEAMDECK_LAN_ENDPOINT`, then run `test/containers-test.sh --scenario steamdeck-host --action cycle`.

## Verdict
- Status: partial / blocked on private live environment.
- Goal state: implementation and safe local verification achieved; full issue #27 acceptance not achieved because live lifecycle cycle is not green.
- Final readiness: ready for bounded live retry with real non-placeholder Deck env; not ready to claim issue #27 done.
