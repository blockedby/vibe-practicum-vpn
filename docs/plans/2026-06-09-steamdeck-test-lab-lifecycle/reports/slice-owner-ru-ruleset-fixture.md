## Task
- Mission: Resolve the Steam Deck lab startup blocker caused by sing-box remote RU `.srs` rule-set downloads and rerun bounded isolated lifecycle as far as feasible.
- Target: sing-box render/templates, lab setup defaults, isolated Deck deploy state refresh, client-smoke bounding, tests/proofs/docs/evidence.
- Boundaries: Do not touch prod/default `vpnkit`; do not commit or print private endpoint/profile/key/cert/rendered/log content; keep issue #24 changes incidental only.
- Done when: Lab render avoids GitHub RU rule-set startup dependency, targeted checks pass, live isolated lifecycle is green or next blocker is precisely classified, commit is pushed, issue/PR are updated.
- Expected evidence: local proof/checks, rendered fixture inspection, runtime `sing-box check`, live matrix, commit/PR/issue update links.

## Context
- Thread: Continue issue #27 / PR #26.
- Slice: RU ruleset fixture fallback.
- Task package: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle`
- Report path: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/reports/slice-owner-ru-ruleset-fixture.md`
- Verification path: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/verification/ru-ruleset-fixture-live.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
- Branch: `feat/issue-24-smart-routing-manifest`

## Spec compliance
- Default remote RU rule sets remain default:
  - Status: done
  - Evidence: `scripts/vpnkit-render-local-configs.sh` defaults `VPNKIT_RULESET_SOURCE_MODE=remote`; `python3 test/sing-box-smart-routing-proof.py` covers remote/default invariants; explicit remote disposable render passed.
- Lab defaults to local fixture:
  - Status: done
  - Evidence: `test/containers-test.sh` exports `VPNKIT_RULESET_SOURCE_MODE=local-fixture` for `steamdeck-host`; `scripts/vpnkit-test-lab-setup.sh` also defaults local-fixture.
- Local fixture preserves policy shape:
  - Status: done
  - Evidence: rendered local entries keep `geoip-ru` / `geosite-category-ru` tags as local/source paths; route rules still point to `direct-out`; final remains `selected-native-out`; adblock/dev-direct unchanged.
- Avoid remote GitHub startup dependency:
  - Status: done for the current blocker
  - Evidence: live `up` PASS in `ru-ruleset-fixture-up4.log`; remote container config verified local-fixture and startup logs no longer show RU GitHub rule-set downloads.
- Live lifecycle green:
  - Status: partial
  - Evidence: `down` PASS, `up` PASS, `test` bounded FAIL; `cycle` not rerun after `test` failure.

## Acceptance verification
- AC1 default production-ish render uses remote binary RU `.srs` unless overridden:
  - Result: passed
  - Evidence: proof plus explicit remote disposable render.
- AC2 lab setup defaults local-fixture and generates local RU source JSON:
  - Result: passed
  - Evidence: disposable lab render and live transfer listing include `geoip-ru.json` and `geosite-category-ru.json`.
- AC3 local-fixture config retains tags/rules/final and avoids GitHub downloads:
  - Result: passed
  - Evidence: proof, disposable render inspection, live `up4` runtime.
- AC4 tests/proof and sing-box check:
  - Result: passed
  - Evidence: smart-routing proof PASS; local rewritten-path `sing-box check` PASS; live runtime `sing-box check` PASS.
- AC5 live isolated Deck lifecycle green if feasible:
  - Result: partial/failed after server-up
  - Evidence: `test6` bounded FAIL: SOCKS HTTPS `SSL_ERROR_SYSCALL`; OpenVPN client TLS succeeds but DNS probe to pushed VPN DNS is refused.
- AC6 required checks:
  - Result: passed
  - Evidence: `bash -n scripts/*.sh test/*.sh`, `go test ./...`, `go vet ./...`, `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`, sensitive tracked artifact check all PASS.
- AC7 commit/push and GitHub updates:
  - Result: passed
  - Evidence: current branch head pushed to `feat/issue-24-smart-routing-manifest`; issue update https://github.com/blockedby/vibe-practicum-vpn/issues/27#issuecomment-4667856262; PR update https://github.com/blockedby/vibe-practicum-vpn/pull/26#issuecomment-4667856378.

## System readiness
- Routes / registration: done for render/lab mode; live server config shape PASS.
- Services / APIs: not relevant.
- Config / env / secrets: done; local fixture mode avoids remote RU download; no private values committed.
- Permissions / access: partial; live Deck access worked via `deck` alias, endpoint discovered without printing.
- Database / migrations: not relevant.
- Runtime / deployment wiring: partial; isolated server starts and checks pass, but data-path/DNS/SOCKS client acceptance remains failing.

## Verification run
- Local / targeted checks:
  - `bash -n scripts/*.sh test/*.sh`: passed.
  - `python3 test/sing-box-smart-routing-proof.py`: passed.
  - Disposable local fixture/remote renders: passed.
  - Local rewritten-path `sing-box check`: passed.
- Local / full checks:
  - `go test ./...`: passed.
  - `go vet ./...`: passed.
  - `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: passed.
  - Sensitive tracked artifact grep: passed.
- Remote/live checks:
  - Isolated Deck `down`: passed.
  - Isolated Deck `up`: passed.
  - Isolated Deck `test`: failed boundedly after server-up.
  - Isolated Deck final cleanup `down`: passed.

## Issues
### Issue R-01: RU remote rule-set startup dependency in lab
- Description: Lab sing-box could exit while downloading remote RU `.srs` files from GitHub.
- Evidence: prior live blocker; current templates default remote but local fixture mode now available.
- Resolution: Added `VPNKIT_RULESET_SOURCE_MODE=remote|local-fixture`; lab defaults local-fixture and generates source JSON fixtures.
- Depends on: none.

### Issue R-02: Persisted sing-box config drift in isolated lab state
- Description: The remote lab state reused `/var/lib/vpnkit/sing-box/config.json`, masking newly rendered local-fixture config.
- Evidence: live `up` initially still showed GitHub RU downloads despite local rendered config.
- Resolution: Isolated Steam Deck run path removes persisted lab sing-box config before starting the test container so entrypoint copies fresh rendered config.
- Depends on: none.

### Issue R-03: Client smoke could outlive harness timeout
- Description: Local OpenVPN client smoke could continue until outer command timeout.
- Evidence: bounded test attempts hung until outer timeout.
- Resolution: Added explicit client container timeout and cleanup in `scripts/vpnkit-steamdeck-client-test.sh`; harness passes timeout through.
- Depends on: none.

### Issue R-04: Lab client cert missing X509 key usage
- Description: OpenVPN client rejected server cert with `VERIFY KU ERROR`.
- Evidence: `ru-ruleset-fixture-test5.log`.
- Resolution: Lab cert generation now includes `keyUsage` and regenerates stale certs without the extension.
- Depends on: none.

### Issue U-01: Live lab data path/DNS/SOCKS still not green
- Description: After server starts, SOCKS HTTPS fails and OpenVPN client DNS probe fails.
- Evidence: `ru-ruleset-fixture-test6.log`: server readiness and runtime `sing-box check` PASS; `server:socks-inbound` fails with `SSL_ERROR_SYSCALL`; client TLS completes but DNS to pushed VPN DNS is refused.
- Why unresolved: Next current-goal blocker remains runtime routing/DNS behavior and needs a focused follow-up fix beyond RU rule-set startup fallback.
- Needed next: Diagnose why container DNS service/pushed VPN DNS is refused and why SOCKS egress via selected-native-out fails in lab, then rerun `test`/`cycle`.
- Depends on: live isolated lab access.

## Side findings
- Blocking findings folded into active work: R-02, R-03, R-04.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: partial
- Goal state: RU rule-set blocker resolved; full Steam Deck lifecycle not green.
- Final readiness: ready for next focused runtime data-path/DNS blocker; not accepted done for issue #27.
- Summary: Local-fixture mode and persisted-state refresh made isolated `up` green without GitHub RU downloads; live `test` now reaches a later bounded DNS/SOCKS/client-smoke failure.

## Next-agent brief
- Objective: Fix remaining isolated Steam Deck lab runtime data-path/DNS/SOCKS failure after server-up.
- Target: `docker/vpnkit/setup-routing.sh`, OpenVPN pushed DNS/server config, sing-box DNS/SOCKS behavior, and `test/containers-test.sh` server/client checks.
- Settled already: RU rule-set local-fixture fallback works; persisted sing-box config refresh works; lab cert KU works; client smoke is bounded.
- Boundaries: isolated `vpnkit-test-steamdeck-host` only; do not mutate prod/default `vpnkit`; do not print or commit private values.
- Verification target: live `down`/`up`/`test`/`cycle` green or a precise environment blocker.
- Expected output: updated verification evidence, issue/PR comment, commit hash.
