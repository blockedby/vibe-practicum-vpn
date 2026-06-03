# Final root report: TPROXY/UDP nested-tunnel vpnkit support

## Task
- Mission: implement and validate vpnkit TPROXY/UDP nested-tunnel support without touching production containers.
- Scope: vpnkit sing-box/runtime routing, local Docker lab, isolated vibe-practicum server/client, isolated moscow-tiger client, and nested OpenVPN-over-OpenVPN attempt.
- Worktree/branch: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-tproxy-udp-nested` / `vpnkit-tproxy-udp-nested`.
- PR: https://github.com/blockedby/vibe-practicum-vpn/pull/18 (draft).

## Slice structure
- Used one slice owner because code/config/runtime validation shared one tight acceptance story and splitting would have increased state/profile handoff risk.
- Supporting audits/classification were used for concrete failures and final acceptance evidence.

## Integrated slice result
- Implemented tproxy-mode sing-box/runtime wiring while preserving default redirect mode.
- Local and isolated live outer OpenVPN/UDP smoke now pass.
- Full independent inner VPN-over-VPN remains unaccepted/blocked.

## Files changed
- `config/sing-box/config.tproxy.json.template`
- `docker/vpnkit/entrypoint.sh`
- `docker/vpnkit/setup-routing.sh`
- `scripts/vpnkit-render-local-configs.sh`
- `tests/vpnkit-singbox-template-test.sh`
- Task package artifacts under `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/`

## Acceptance verification
- AC1 TPROXY mode works: **passed for local/live outer runtime**.
  - Evidence: local lab `vpnkit_tproxy_udp_nested_lab2` on `21196/udp` passed OpenVPN, UDP DNS `NOERROR`, HTTPS `200`, literal-IP HTTPS `200`; template and sing-box checks passed.
- AC2 UDP/nested VPN-over-VPN: **partial / blocked**.
  - Evidence passed: UDP DNS over outer OpenVPN passed locally and live; vibe-practicum and moscow-tiger outer UDP OpenVPN smokes passed.
  - Evidence blocked: pre-fix nested harness routed inner endpoint via outer `tun0` and incremented outer non-DNS UDP TPROXY counters, but inner `tun1` did not establish. Post-fix rerun could not prove AC2 because matching live test profile material was not safely available/reconstructable for the rerun harness.
- AC3 default production mode unchanged: **passed**.
  - Evidence: compose default remains redirect; redirect template covered by tests; tproxy changes are mode-specific.
- AC4 local Docker lab before live mutation: **passed**.
- AC5 isolated vibe-practicum server/client: **passed**.
  - Project `vpnkit_tproxy_live_21195`, container `vpnkit_tproxy_live_21195-vpnkit-1`, port `21195/udp`; same-host client passed.
- AC6 isolated moscow-tiger client: **passed**.
  - Project `vpnkit_tproxy_live_21195_moscow_client`, passing container `vpnkit_tproxy_live_21195_moscow_client-ovpn-client-test-run-5a34e944274c`; connected to isolated server on `21195/udp` and passed UDP DNS/HTTPS/literal-IP smokes.
- AC7 tests/files/names/ports/cleanup/production untouched: **passed**; see verification artifacts.
- AC8 no secrets committed/revealed: **passed**; private endpoint env and generated secrets remain ignored/untracked.

## Verification run
- Root fresh checks recorded in `verification/root.md`:
  - `bash tests/vpnkit-singbox-template-test.sh` — pass.
  - `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh` — pass.
  - `go test ./...` — pass.
  - `go vet ./...` — pass.
  - `go build -o /tmp/vibe-vpn-root-verify ./cmd/vibe-vpn` — pass.
- Acceptance auditor verdict: **not accepted** because AC2 full inner proof remains blocked.

## Isolated live resources and cleanup
- Successful live outer validation:
  - vibe-practicum project/container/port: `vpnkit_tproxy_live_21195` / `vpnkit_tproxy_live_21195-vpnkit-1` / `21195/udp`.
  - moscow-tiger client project/container: `vpnkit_tproxy_live_21195_moscow_client` / `vpnkit_tproxy_live_21195_moscow_client-ovpn-client-test-run-5a34e944274c`.
- Nested attempts:
  - `vpnkit_tproxy_nested_outer_21202` on `21202/udp`, `vpnkit_tproxy_nested_inner_21203` on `21203/udp`, client `vpnkit_tproxy_nested_moscow_client_21202_21203`.
  - post-fix rerun attempt: `vpnkit_tproxy_nested_outer_21224` on `21224/udp`, `vpnkit_tproxy_nested_inner_21225` on `21225/udp`, client harness `nested-debug-21224`; setup-only retry reserved `21226/udp`/`21227/udp`.
- Cleanup: all listed isolated containers/projects/volumes/networks/temp paths were removed; nothing intentionally retained.

## Production safety
- Production `vpnkit` on vibe-practicum remained running with restart count `0` and unchanged start time in before/after/cleanup metadata.
- No production containers were restarted, recreated, adopted, or mutated.
- Steam Deck was not touched.

## Issues
### U-1: Full independent inner VPN-over-VPN proof remains blocked
- Evidence: acceptance auditor report plus `verification/inner-nested.md`.
- Current state: code now includes a UDP pre-sniff tproxy route and local smoke passes, but post-fix full inner live proof could not run because matching live test profile material was not safely available/reconstructable without broader private secret probing.
- Needed next: provide/generate a matching isolated live test-client profile/harness through the repo’s gitignored secret workflow, then rerun the nested harness and prove `tun0` + route via `tun0` + `tun1` + UDP through inner.

## Final root done-state
- **Partial / blocked, not fully accepted.**
- The implementation and staged outer UDP validation succeeded, and production was untouched, but the requested nested inner VPN-over-VPN acceptance remains blocked with concrete evidence.
