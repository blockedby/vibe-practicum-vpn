## Task
- Mission: Diagnose/fix the remaining isolated Steam Deck lab runtime data-path/DNS/SOCKS failure after RU fixture startup was fixed.
- Target: `scripts/vpnkit-render-local-configs.sh`, `scripts/vpnkit-test-lab-setup.sh`, `config/openvpn/server.tpl`, `README.md`, `test/sing-box-smart-routing-proof.py`.
- Boundaries: Keep production/default behavior unchanged; do not mutate prod/default `vpnkit`; do not print/commit private endpoints, profiles, certs, rendered configs, logs, or secrets.
- Done when: Lab render has a safe selected outbound fixture and pushed DNS path, local checks pass, live Deck lifecycle is green if private bindings are available, and PR/issue status is updated.
- Expected evidence: Root cause, changed files, local checks, live matrix or precise blocker.

## Context
- Thread: Continue issue #27 / PR #26 until Steam Deck lab lifecycle is green if feasible.
- Slice: Runtime data-path/DNS/SOCKS.
- Task package: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle`.
- Report path: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/reports/slice-owner-runtime-datapath-dns.md`.
- Verification path: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/verification/runtime-datapath-dns-live.md`.
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`.
- Branch: `feat/issue-24-smart-routing-manifest`.
- Ownership model: Slice stayed whole; no sub-slices. Owner made the small coupled fix directly.

## Spec compliance
- Requirement / AC: Root cause documented with evidence.
  - Status: done.
  - Evidence: prior `ru-ruleset-fixture-test6.log` symptoms plus render/code facts documented in `verification/runtime-datapath-dns-live.md`.
  - Gap if any: none for local diagnosis.
- Requirement / AC: Lab selected outbound fixture explicit, lab-default only, production/default proxy/VLESS preserved, tag/final shape intact.
  - Status: done.
  - Evidence: `VPNKIT_SELECTED_OUTBOUND_MODE=proxy|direct-fixture`; renderer default `proxy`; lab setup default `direct-fixture`; disposable renders passed for both modes.
  - Gap if any: live data-path still unproven without private env.
- Requirement / AC: DNS wiring preserves production safety and lets lab client DNS enter sing-box TUN.
  - Status: partial.
  - Evidence: `VPNKIT_OPENVPN_PUSH_DNS` renderer default `10.89.0.1`; lab setup default `172.19.0.1`; disposable lab render asserts pushed DNS `172.19.0.1`.
  - Gap if any: live pushed-DNS probe not run because private env absent.
- Requirement / AC: Repo checks pass.
  - Status: done.
  - Evidence: see Verification run.
- Requirement / AC: Commit/push and GitHub issue/PR update.
  - Status: missing in this report version.
  - Evidence: local changes are not yet committed/pushed at report-write time.
  - Gap if any: requires commit/push and `gh` update after final status.

## Acceptance verification
- AC1 Root cause for SOCKS/DNS/client-smoke failure is documented with evidence.
  - Covered by: prior live log symptom + render/code inspection.
  - Result: passed.
  - Evidence: `verification/runtime-datapath-dns-live.md`.
- AC2 Lab selected outbound fixture is explicit, lab-only default; production/default remains proxy/VLESS; tag/final shape intact.
  - Covered by: renderer knobs and disposable render assertions.
  - Result: passed locally.
  - Evidence: `VPNKIT_SELECTED_OUTBOUND_MODE`; disposable lab/default render checks.
- AC3 DNS wiring changes pass config checks and pushed VPN DNS works for lab client.
  - Covered by: render assertion for lab DNS target; live client probe not available.
  - Result: partial.
  - Evidence: `VPNKIT_OPENVPN_PUSH_DNS` and lab render check; live not run.
- AC4 Live isolated `down/up/test/cycle` green if feasible.
  - Covered by: attempted live gate.
  - Result: blocked/not run.
  - Evidence: `config/private-endpoints.local.env` absent; command exited `NO_PRIVATE_ENV` before mutation.
- AC5 Repo checks pass or skips justified.
  - Covered by: shell, proof, Python, Go, artifact checks.
  - Result: passed.
  - Evidence: Verification run.
- AC6 Commit/push and issue #27 / PR #26 updated.
  - Covered by: pending owner finalization.
  - Result: not yet run.
  - Evidence: none yet.

## System readiness
- Routes / registration: done locally; `route.final` remains `selected-native-out` and policy proof passes.
- Services / APIs: not relevant.
- Config / env / secrets: partial; lab config render semantics fixed, but live private endpoint env absent.
- Permissions / access: blocked for live Deck mutation by missing local private env.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: partial; rendered wiring fixed, live Deck lifecycle not rerun.

## Verification run
- Local / targeted checks:
  - `bash -n scripts/vpnkit-render-local-configs.sh scripts/vpnkit-test-lab-setup.sh test/containers-test.sh scripts/vpnkit-steamdeck-podman.sh`: passed.
  - `python3 test/sing-box-smart-routing-proof.py`: passed.
  - Disposable lab setup/render assertion: passed; lab renders direct `selected-native-out`, local RU fixtures, and OpenVPN DNS `172.19.0.1`.
  - Disposable explicit/default render assertion: passed; proxy/VLESS selected outbound and OpenVPN DNS `10.89.0.1` preserved.
- Local / full checks:
  - `go test ./...`: passed.
  - `go vet ./...`: passed.
  - `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: passed.
  - `python3 -m py_compile $(find scripts test -name '*.py' -print)`: passed.
  - Sensitive tracked artifact check: passed.
- Remote checks / CI:
  - Status: not checked before push.
  - Evidence: local changes not pushed at this report-write point.

## Issues
### Issue R-01: Lab SOCKS/default egress used an impossible dummy selected proxy
- Description: Lab-generated `selected-native-out` was a VLESS outbound to `127.0.0.1:443` with no fixture proxy listening there.
- Evidence: `scripts/vpnkit-test-lab-setup.sh` dummy canary plus prior live `server:socks-inbound` `SSL_ERROR_SYSCALL`.
- Resolution: Added `VPNKIT_SELECTED_OUTBOUND_MODE=proxy|direct-fixture`; lab defaults direct fixture while preserving `selected-native-out` tag/final.
- Depends on: none.

### Issue R-02: Lab pushed DNS targeted local OpenVPN tun0 instead of sing-box TUN
- Description: OpenVPN pushed `10.89.0.1`, the server-side OpenVPN `tun0` address; client DNS packets to that local address terminate in INPUT and do not traverse sing-box TUN.
- Evidence: prior live client DNS refused after TLS success; fixed render check shows lab now pushes `172.19.0.1`.
- Resolution: Added `VPNKIT_OPENVPN_PUSH_DNS`; production/default remains `10.89.0.1`, lab setup defaults `172.19.0.1`.
- Depends on: none.

### Issue U-01: Live Steam Deck lifecycle not rerun from this worktree
- Description: The required live `down/up/test/cycle` could not be executed because the gitignored private endpoint file is absent.
- Evidence: live gate returned `NO_PRIVATE_ENV`; no remote mutation was attempted.
- Why unresolved: authorized private Deck bindings are not available in this worktree.
- Needed next: source/provide `config/private-endpoints.local.env` (or approved non-placeholder env) and rerun isolated lab `down`, `up`, `test`, and `cycle`.
- Depends on: private env availability.

## Side findings
- Blocking findings folded into active work: R-01, R-02.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: partial.
- Goal state: locally fixed and verified; live lifecycle not achieved in this worktree.
- Final readiness: ready for bounded live retry, not accepted green.
- Summary: Lab render now has explicit direct selected-outbound fixture and tunneled pushed DNS while preserving production defaults, but issue #27 still needs a live Deck cycle with private bindings.

## Next-agent brief
- Objective: Finish issue #27 acceptance by running live isolated Steam Deck lab lifecycle after private env is available.
- Target: `test/containers-test.sh --scenario steamdeck-host --action down|up|test|cycle`.
- Settled already: RU `.srs` startup blocker fixed; selected outbound fixture and lab pushed DNS render semantics fixed; production/default render remains proxy/VLESS and DNS `10.89.0.1`.
- Boundaries: do not touch prod/default `vpnkit`; do not print/commit private endpoints, profiles, rendered configs, cert/key/PEM, or logs with secrets.
- Verification target: green live `down`, `up`, `test`, and `cycle`, or precise new blocker with cleanup state.
- Expected output: update `verification/runtime-datapath-dns-live.md`, this report, issue #27, and PR #26.
