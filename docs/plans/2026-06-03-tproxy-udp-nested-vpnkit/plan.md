# Plan: TPROXY/UDP nested-tunnel vpnkit support

## Task intake

Implement and validate TPROXY/UDP nested-tunnel support for vpnkit without touching production containers.

User-approved live-test scope:
1. First perform local Docker lab test.
2. Then deploy an isolated test vpnkit server container on vibe-practicum using new ports/names/networks/volumes/state only, plus an isolated client-test container on vibe-practicum that connects to that test server.
3. If that works, run an isolated client-test container on moscow-tiger connecting to the isolated test server on vibe-practicum.

Hard boundaries:
- Do not restart/recreate/adopt/mutate production containers (`vpnkit`, `current-vpnkit-1`, or other existing services).
- Do not touch Steam Deck.
- Use isolated Docker/Compose project names, container names, ports, networks, volumes, and state directories.
- Use new OpenVPN port(s) for tests.
- Generate/use only gitignored/temp profiles/secrets.
- Do not commit generated `.ovpn`, logs, secrets, rendered configs, or private endpoint values.
- Default production mode must remain unchanged.

## Root acceptance criteria

AC1. TPROXY mode actually works for vpnkit by aligning sing-box config/inbounds/readiness/routing as needed.
AC2. UDP path is validated, including nested VPN-over-VPN behavior: outer OpenVPN into isolated test vpnkit and an inner tunnel where feasible.
AC3. Default production mode remains unchanged.
AC4. Local Docker lab passes before any live-host mutation.
AC5. Isolated test server and isolated client-test container on vibe-practicum pass without touching production services.
AC6. If vibe-practicum isolated test passes, isolated client-test container on moscow-tiger passes against the test server, or a concrete blocker is reported with evidence.
AC7. Reports include tests run, files changed, exact isolated container names/ports used, cleanup status, and whether production containers were untouched.
AC8. No secrets/profiles/logs/rendered configs/private endpoint values are committed or revealed.

## Ownership model

Single slice under `aad-slice-owner` because this is one tightly coupled runtime behavior and verification story: vpnkit TPROXY/UDP wiring plus staged local and isolated live validation. Splitting implementation from live validation would create handoff risk around the same container/profile/config state. The slice owner may sub-slice internally if needed.

## Slice: TPROXY/UDP nested-tunnel runtime support and staged validation

Goal:
- Make vpnkit tproxy mode functional for UDP nested-tunnel use while preserving default production behavior and prove it through local Docker lab and user-approved isolated live tests.

Likely areas:
- `docs/DOCKER_SETUP.md`
- Docker/Compose lab files and scripts
- vpnkit OpenVPN/sing-box runtime config rendering
- readiness/health checks
- tests for config generation/routing behavior
- safe deployment/test scripts or documentation as needed

Acceptance criteria:
- Covers AC1-AC8 above.

Test plan:
- Fresh repo checks relevant to touched files (e.g. `go test ./...`, `bash -n scripts/*.sh`, config rendering tests).
- Local Docker lab using isolated names/ports/state first.
- Isolated test deployment on vibe-practicum using private endpoint config from gitignored `config/private-endpoints.local.env` if available.
- Isolated client-test on vibe-practicum to test server.
- Isolated client-test on moscow-tiger to same test server only after previous pass.
- Evidence of production containers existing but not mutated (before/after inspect/list with safe redaction, no restarts/recreates).
- Cleanup evidence for isolated test resources, or explicit retained-for-debug list.

Dependencies:
- Depends on: private endpoint values for live-host access if local lab passes.
- Blocks: root final acceptance.

Executor:
- `aad-slice-owner`

## Plan tasks

### Task 1: Mode-aware vpnkit sing-box TPROXY runtime config

Goal:
- Make `VPNKIT_ROUTING_MODE=tproxy` use a sing-box inbound set that can receive transparent TCP/UDP packets on the routing port, while `redirect` default behavior remains unchanged.

Boundary:
- System area: vpnkit container entrypoint/config rendering/readiness.
- Primary verification: targeted shell/template tests plus `sing-box check` where available.

Existing pattern / reuse:
- `config/sing-box/config.json.template` currently provides redirect DNS/SOCKS inbounds and reusable route/outbound structure.
- `docker/vpnkit/entrypoint.sh` copies the source config into `/var/lib/vpnkit/sing-box/config.json` and waits for fixed inbounds.
- `docker/vpnkit/setup-routing.sh` already installs TCP and UDP TPROXY mangle rules when `VPNKIT_ROUTING_MODE=tproxy`.

Missing change:
- Add mode-specific sing-box config/readiness so the tproxy routing rules match an actual sing-box `tproxy` inbound, without changing the default `redirect` config.

Scope / likely files:
- `config/sing-box/` templates or mode-specific config files.
- `docker/vpnkit/entrypoint.sh`.
- tests under existing shell/Go test patterns as appropriate.

Acceptance criteria:
- Redirect/default config remains available and defaults to existing redirect mode.
- TPROXY mode produces/checks a config with TCP+UDP transparent inbound on port 2082 and DNS handling compatible with existing route rules.
- Readiness waits for the correct inbound(s) in each mode.

Test plan:
- Positive: mode-specific render/check or unit test for redirect and tproxy config/inbound names/types/ports.
- Positive: `bash -n docker/vpnkit/*.sh scripts/*.sh` if shell touched.
- Positive: `go test ./...` if Go tests added/changed.
- Manual/lab: container startup in local Docker lab after implementation.

Dependencies:
- Depends on: none.
- Blocks: Task 2 and staged validation.
- Can run parallel with: none.

Executor:
- `aad-implementer`.

### Task 2: Local/staged validation support and evidence

Goal:
- Validate the implemented tproxy/UDP path in local Docker lab first, then only proceed to isolated approved live-host tests if safe inputs are available.

Boundary:
- System area: validation commands, docs/scripts needed for safe isolated Docker lab/live tests.
- Primary verification: sanitized verification artifacts in `verification/slice.md` and final report.

Existing pattern / reuse:
- `docs/DOCKER_SETUP.md` Docker lab workflow.
- `docker/ovpn-client-test/run-tests.sh` for client-side DNS/HTTPS smoke checks.
- repo public-safety rules for private endpoints and production-container boundaries.

Missing change:
- Add/update reusable docs/scripts only if needed to run isolated tproxy validation safely.
- Capture sanitized local lab and live-test evidence, including exact isolated names/ports/state paths and cleanup.

Acceptance criteria:
- Local Docker lab passes before any live-host mutation.
- Live tests stop if `config/private-endpoints.local.env` is unavailable or local lab fails.
- Production containers are not mutated; before/after safe metadata supports this.

Test plan:
- Positive: repo checks (`go test ./...`, `go vet ./...`, `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`, relevant `bash -n`).
- Positive: local Docker lab with isolated project/container/port/state.
- Manual/live: vibe-practicum isolated test server/client-test, then moscow-tiger isolated client-test if eligible.
- Negative/blocker: record concrete blocker if Docker/live prerequisites are absent.

Dependencies:
- Depends on: Task 1 local implementation passes.
- Blocks: final slice verdict.
- Can run parallel with: none.

Executor:
- `aad-slice-owner` coordinating after implementer report; may delegate narrow audit if evidence needs independent check.

## Dependency graph

- Wave 1: Task 1 to `aad-implementer`.
- Wave 2: owner integrates Task 1 report, runs fresh repo checks and local Docker lab.
- Wave 3: approved isolated live tests only after local lab passes and private endpoint env is present.
- Wave 4: final report/ledger update and push to PR #18; no merge.

## Execution ledger

- 2026-06-03: Root worktree created at `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-tproxy-udp-nested` on branch `vpnkit-tproxy-udp-nested` from `main`.
- 2026-06-03: Root task package initialized.
- 2026-06-03: Draft PR opened: https://github.com/blockedby/vibe-practicum-vpn/pull/18.
- 2026-06-03: Slice owner refined execution plan. Pre-dispatch gate passed for Task 1: intake/boundaries/repo orientation/reuse/missing pieces/tasks/dependencies are recorded above.
- 2026-06-03: Attempted to delegate Task 1 to `aad-implementer`; pi-subagents blocked nested call at max depth, so slice owner implemented scoped Task 1 changes directly.
- 2026-06-03: Added tproxy sing-box template, mode-aware entrypoint config selection/readiness, render support, and template tests. Automated checks passed: `bash tests/vpnkit-singbox-template-test.sh`, `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh`, `sing-box check` on dummy rendered redirect/tproxy configs, `go test ./...`, `go vet ./...`, `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`.
- 2026-06-03: Local Docker lab attempted with isolated project `vpnkit_tproxy_udp_nested_lab`, port `21194/udp`, generated gitignored local lab secrets under `secrets/`. Result: container/listeners/rules start; OpenVPN client connects; UDP DNS through tunnel times out even though UDP TPROXY mangle counter increments. Current-goal blocker U-1 recorded in `verification/slice.md` and owner report. No live tests attempted.
- 2026-06-03: Cleanup completed for isolated lab via `docker compose -p vpnkit_tproxy_udp_nested_lab down -v --remove-orphans`; no lab containers remained. Existing non-slice containers were not touched.
- 2026-06-03 continuation: Delegation to `aad-implementer` was blocked by max subagent depth, so slice owner debugged directly under the active worktree. Resolved local U-1 for the existing Docker lab smoke by adding tproxy-mode protocol special cases: UDP/53 REDIRECT to sing-box DNS inbound `5353`, TCP REDIRECT to tproxy-mode redirect inbound `2083`, and non-DNS UDP remains on TPROXY inbound `2082` with early fwmark policy rule. Fresh checks passed: `bash tests/vpnkit-singbox-template-test.sh`, `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh`, `go test ./...`, `go vet ./...`, `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`. Local Docker lab `vpnkit_tproxy_udp_nested_lab` on host port `21194/udp` passed OpenVPN connect, UDP DNS `NOERROR`, HTTPS hostname `200`, literal-IP HTTPS `200`; see `verification/tproxy-udp-debug.md`. Live/nested staging is blocked because `config/private-endpoints.local.env` is absent; no live-host mutation attempted. Cleanup removed isolated lab containers/volumes/network; production/hard-boundary containers untouched.
- 2026-06-03 continuation/live: Private endpoint env became available and was sourced without printing values. Ran approved isolated live validation using vibe-practicum Compose project `vpnkit_tproxy_live_21195`, OpenVPN test port `21195/udp`, and moscow-tiger client project `vpnkit_tproxy_live_21195_moscow_client`. Same-host vibe-practicum client and remote moscow-tiger client both passed OpenVPN UDP connect, UDP DNS `NOERROR`, HTTPS hostname `200`, and literal-IP HTTPS `200`. Isolated server runtime showed UDP DNS REDIRECT counters, TCP REDIRECT counters, and non-DNS UDP TPROXY rule/listener present. Full inner VPN-over-VPN was not run because only one generated test-client identity/profile was available, making simultaneous inner reuse unsafe/non-independent; nested-adjacent UDP live evidence is recorded. Cleanup removed isolated containers, volumes, networks, and temp paths; production `vpnkit` metadata remained running/restart=0/same start time before/after. See `verification/live-isolated.md`.
- 2026-06-03 continuation/inner-nested: Made a focused full inner OpenVPN-over-OpenVPN attempt using isolated vibe-practicum outer/inner vpnkit servers (`vpnkit_tproxy_nested_outer_21202` on `21202/udp`, `vpnkit_tproxy_nested_inner_21203` on `21203/udp`) and an isolated moscow-tiger nested client project (`vpnkit_tproxy_nested_moscow_client_21202_21203`). The outer tunnel came up, `ip route get <inner-endpoint>` from the client showed the inner endpoint routed via `tun0`, and the outer server's non-DNS UDP TPROXY counter incremented (`9` packets / `738` bytes) during the inner OpenVPN attempt. The inner tunnel did not establish (`tun1` never appeared; inner client log stopped after UDP remote setup; inner server showed no accepted client), so AC2 full inner VPN-over-VPN remains concretely blocked on non-DNS UDP TPROXY transport for OpenVPN handshakes. Cleanup removed all isolated resources; production `vpnkit` remained running/restart=0/same start time. See `verification/inner-nested.md`.
