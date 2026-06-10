## Task
- Mission: Finish issue #27 / PR #26 Steam Deck isolated lab lifecycle after RU rule-set, data-path, DNS, and direct-fixture blockers.
- Target: `feat/issue-24-smart-routing-manifest`, isolated `steamdeck-host` lab scenario.
- Boundaries: No default/prod `vpnkit` mutation; no private endpoint/profile/key/cert/rendered config/log disclosure; Steam Deck evidence is test/lab only, not production readiness.
- Done when: Required isolated lab `down`, `up`, `test`, and `cycle` are green with bounded commands, safe repo checks pass, commits are pushed, and GitHub issue/PR are updated public-safely.

## Context
- GitHub issue: https://github.com/blockedby/vibe-practicum-vpn/issues/27
- Related PR: https://github.com/blockedby/vibe-practicum-vpn/pull/26
- Related issue: #24
- Task package: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle`
- Latest verification: `verification/root-final-live-green.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
- Branch: `feat/issue-24-smart-routing-manifest`

## Spec compliance
- AC1 lifecycle command: done. `test/containers-test.sh --scenario steamdeck-host --action up|test|down|cycle` exists and is documented.
- AC2 isolated lab/no prod container: done. Live runs targeted `vpnkit-test-steamdeck-host`; default/prod `vpnkit` was not touched.
- AC3 gitignored generated artifacts: done. Generated lab material remains under ignored paths; tracked docs/templates are public-safe.
- AC4 production-like smart-routing shape: done. RU/adblock/dev-direct/final policy shape is preserved; lab uses explicit local/direct fixtures only where needed for reproducible isolated acceptance.
- AC5 lab `tun` mode: done. Live `up`, `test`, and `cycle` verified `tun0`, `sb-tun0`, policy route setup, and runtime `sing-box check`.
- AC6 disabled `vibe-vpn` daemon/subscription path: done. Lab smoke proceeds without subscription; daemon remains disabled unless explicitly enabled.
- AC7 missing/placeholder prerequisites: done from prior checks; explicit placeholders fail fast.
- AC8 honest matrix: done. Required lifecycle checks passed; route-decision/policy-visible scaffold rows remain explicit `SKIP` and are not claimed as required acceptance.
- AC9 safe repo checks: passed after final live run.
- AC10 live Deck lifecycle: passed. Required `down`, `up`, `test`, and `cycle` completed boundedly; final cleanup also passed.
- AC11 PR/issue updates: done by slice updates; final public-safe status update remains to be posted after this report commit.

## Acceptance verification
- RU rule-set reproducibility:
  - Covered by: local render/proof checks and live `up`.
  - Result: passed.
  - Evidence: `VPNKIT_RULESET_SOURCE_MODE=local-fixture` lab default, generated local source JSON RU fixtures, live `up` with no GitHub RU `.srs` download.
- Direct selected-outbound lab fixture:
  - Covered by: render assertions, `sing-box check`, live `server:socks-inbound`.
  - Result: passed.
  - Evidence: `VPNKIT_SELECTED_OUTBOUND_MODE=direct-fixture` lab default; default/proxy render remains VLESS; live SOCKS check passed.
- DNS path:
  - Covered by: `VPNKIT_OPENVPN_PUSH_DNS` lab default and live client smoke.
  - Result: passed.
  - Evidence: client smoke completed TLS/cert validation, pushed DNS query, HTTPS hostname, and HTTPS literal-IP checks.
- Live lifecycle:
  - Covered by: `verification/root-final-live-green.md`.
  - Result: passed.
  - Evidence: `down` PASS, `up` PASS, `test` PASS with PASS=10 FAIL=0 SKIP=2, `cycle` PASS with PASS=13 FAIL=0 SKIP=2, final cleanup `down` PASS.
- Public-safety:
  - Covered by: redacted harness output and tracked-file check.
  - Result: passed.
  - Evidence: no tracked `.ovpn`, `.pem`, `.key`, `.crt`, `secrets/`, `rendered/`, or `logs/` paths; endpoint only process-local/redacted.

## System readiness
- Routes / registration: not applicable beyond existing scripts.
- Services / APIs: not applicable.
- Config / env / secrets: ready for lab; private bindings remain local/gitignored.
- Permissions / access: Deck SSH access worked for bounded isolated lab operations.
- Database / migrations: not applicable.
- Frontend-backend integration: not applicable.
- Runtime / deployment wiring: ready for issue #27 lab scope. Production readiness is not claimed.

## Verification run
- Local / targeted checks:
  - `bash -n scripts/vpnkit-render-local-configs.sh scripts/vpnkit-test-lab-setup.sh scripts/vpnkit-steamdeck-podman.sh scripts/vpnkit-steamdeck-client-test.sh test/containers-test.sh`: passed.
  - `python3 test/sing-box-smart-routing-proof.py`: passed.
- Local / full checks:
  - `go test ./...`: passed.
  - `go vet ./...`: passed.
  - `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: passed.
  - `python3 -m py_compile $(find scripts test -name '*.py' -print)`: passed.
  - Sensitive tracked artifact check: passed/no matches.
- Remote checks / CI:
  - Live Deck isolated lab: passed; see `verification/root-final-live-green.md`.
  - PR checks: no required checks were reported previously for this branch.

## Issues
### Issue R-01: Remote RU `.srs` startup dependency
- Description: Lab sing-box exited when GitHub RU remote binary rule-set download returned `unexpected EOF`.
- Resolution: Added explicit `VPNKIT_RULESET_SOURCE_MODE=remote|local-fixture`; lab defaults local-fixture and generates local source JSON fixtures.
- Evidence: commits `53dec3d`, `59b18ee`; live `up` passed with local fixtures.

### Issue R-02: Persisted sing-box config drift
- Description: Isolated lab state could reuse stale `/var/lib/vpnkit/sing-box/config.json` and mask newly rendered config.
- Resolution: Isolated Steam Deck run path removes persisted lab sing-box config before start.
- Evidence: live `up` used refreshed rendered config.

### Issue R-03: Lab selected outbound was an impossible dummy proxy
- Description: Dummy VLESS `selected-native-out` to `127.0.0.1:443` made default/SOCKS egress fail.
- Resolution: Added `VPNKIT_SELECTED_OUTBOUND_MODE=proxy|direct-fixture`; lab defaults direct-fixture while keeping final/tag `selected-native-out`.
- Evidence: commit `4cb45c7`; live `server:socks-inbound` passed.

### Issue R-04: Lab pushed DNS targeted local OpenVPN server address
- Description: Pushed DNS `10.89.0.1` terminates locally in `tun` mode and did not enter sing-box TUN.
- Resolution: Added `VPNKIT_OPENVPN_PUSH_DNS`; lab defaults `172.19.0.1`, production/default remains `10.89.0.1`.
- Evidence: commit `4cb45c7`; live client DNS probe passed.

### Issue R-05: Direct-fixture DNS detour rejected by sing-box
- Description: DNS TLS servers detoured through empty direct `selected-native-out`; sing-box rejected startup with `detour to an empty direct outbound makes no sense`.
- Resolution: Renderer omits DNS TLS detour only in direct-fixture mode; default/proxy keeps it.
- Evidence: commit `f4c389a`; live `up` and `cycle` passed.

## Side findings
- Blocking findings folded into active work: all current blockers resolved.
- Non-blocking findings tracked separately: route-decision and policy-visible live extensions remain explicit scaffold `SKIP` rows; repo-local smart-routing proof covers required policy semantics for this issue.

## Verdict
- Status: success.
- Goal state: fully achieved for issue #27 isolated Steam Deck lab lifecycle.
- Final readiness: ready for PR/issue review in lab scope; production readiness not claimed.
- Summary: The isolated Steam Deck lab lifecycle is now green with bounded `down`, `up`, `test`, and `cycle`, and final cleanup passed.
