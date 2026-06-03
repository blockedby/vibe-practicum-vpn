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

## Execution ledger

- 2026-06-03: Root worktree created at `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-tproxy-udp-nested` on branch `vpnkit-tproxy-udp-nested` from `main`.
- 2026-06-03: Root task package initialized.

- 2026-06-03: Draft PR opened: https://github.com/blockedby/vibe-practicum-vpn/pull/18.
