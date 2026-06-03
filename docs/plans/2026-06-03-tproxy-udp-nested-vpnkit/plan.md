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
- 2026-06-03 continuation/non-DNS UDP fix: Nested subagent delegation was still blocked by max subagent depth, so slice owner made a scoped route-policy fix directly. Added a `vpnkit-tproxy-in` UDP route rule before sniffing in `config/sing-box/config.tproxy.json.template`, with a template test asserting rule presence/order, so opaque UDP/OpenVPN handshakes do not go through protocol sniffing before outbound routing. Fresh automated checks passed: `bash tests/vpnkit-singbox-template-test.sh`, `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh`, `go test ./...`, `go vet ./...`, `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`, and rendered tproxy `sing-box check` (deprecation warnings only). Fresh isolated local Docker lab `vpnkit_tproxy_udp_nested_lab2` on `21196/udp` passed OpenVPN connect, UDP DNS `NOERROR`, HTTPS hostname `200`, and literal-IP HTTPS `200`; cleanup removed isolated local containers/volumes/network. Live nested rerun is blocked before mutation because the available gitignored private endpoint file contains an unresolved placeholder VPS SSH alias and no remote client host value; no live or production containers were touched. See `verification/tproxy-udp-debug-2026-06-03-nondns.md` and updated owner report.
- 2026-06-03 continuation/live nested rerun after routing correction: Used approved SSH aliases `vibe-practicum` and `moscow-tiger` directly and attempted fresh isolated resources on new ports `21224/udp` + `21225/udp` (plus a setup-only retry reserving `21226/udp` + `21227/udp`). The isolated servers started and tproxy listeners were present, but the moscow-tiger outer client did not establish `tun0`; a matching generated live test-client profile could not be safely reconstructed from available non-tracked materials without broader secret-path probing. Cleanup removed isolated resources; production `vpnkit` remained running/restart=0/same start time. AC2 remains blocked; see `verification/inner-nested.md`.
- 2026-06-03 continuation/matching-bundle nested validation: Delegated rerun to `aad-implementer` with strict scope to use only the matching gitignored bundle already present in this worktree (`server.conf`, `pki/*`, `config.tproxy.json`, `test-client.ovpn`) and to rewrite only temp client profile `remote` lines. Isolated vibe-practicum outer/inner servers used fresh ports `21342/udp` and `21343/udp`, shared network `vpnkit_match_net_21342_21343`, and moscow-tiger client container `nested-match-21342`. Result: outer OpenVPN reached `OUTER_UP`; route to inner container endpoint proved `dev tun0`; inner OpenVPN failed with TLS handshake timeout and no `tun1`. Outer non-DNS UDP TPROXY counter incremented (`15` packets / `1230` bytes), while outer-to-inner and inner `udp/1194` tcpdump captured no packet lines and inner server accepted no client. Cleanup removed all isolated resources; production `vpnkit` metadata stayed running/restart=0/same start time. AC2 remains a concrete current-goal blocker: non-DNS UDP reaches the outer TPROXY rule but is not observed egressing toward/arriving at the inner OpenVPN server. See `verification/inner-nested-matching-bundle.md` and `reports/aad-implementer-matching-bundle-nested.md`.
- 2026-06-03 continuation/udp echo private-bypass fix: Delegated reduced UDP echo blocker fix to `aad-implementer`. Local isolated RED echo reproduced the non-DNS UDP failure without inner OpenVPN complexity: outer client route to private echo target used `tun0`, generic UDP TPROXY counter incremented, and echo timed out. Sing-box-only hypotheses (`direct-out` private route, `udp_connect`/`udp_timeout`) did not pass; kernel evidence showed TPROXY was terminal in this backend. Implemented a tproxy-mode-only private UDP bypass before the generic TPROXY rule, with MASQUERADE/FORWARD chains for RFC1918 private destinations, preserving default redirect mode. GREEN reduced echo passed using isolated project `udp_echo_fix_impl` on `21404/udp`; local nested rerun passed using `udp_echo_fix_nested` on `21405/udp` with inner `tun1` on temp subnet `10.90.0.0/24`. Targeted checks passed and cleanup removed isolated local resources. See `verification/udp-echo-tproxy-fix.md` and `reports/aad-implementer-udp-echo-tproxy-fix.md`.

- 2026-06-03 owner final: Fresh owner verification after commits `978f3dd`/`c207e9c` passed (`bash tests/vpnkit-setup-routing-test.sh`, `bash tests/vpnkit-singbox-template-test.sh`, `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh`, `go test ./...`, `git diff --check`). Acceptance auditor accepted this blocker-fix slice with limitation that broader live nested proof remains a parent-level gap if required; report in `reports/acceptance-auditor-udp-echo-tproxy-fix.md`.

## Continuation task: live isolated validation after private UDP bypass fix

User-requested goal:
- Run approved live isolated validation now that local UDP echo and local nested OpenVPN pass after the private UDP bypass fix.
- Stage 1: isolated tproxy vpnkit server container on vibe-practicum using fresh high UDP port plus isolated client-test container on vibe-practicum; validate baseline and nested private OpenVPN if feasible using matching bundle.
- Stage 2: if Stage 1 passes, isolated client-test container on moscow-tiger connecting to the isolated tproxy vpnkit server on vibe-practicum; validate baseline and nested private OpenVPN if feasible.
- Public UDP distinction: because private Docker-IP bypass does not prove real public nested VPN endpoints, run a reduced public non-DNS UDP echo check using an isolated UDP echo endpoint on a different host/high UDP port where possible; send UDP through the outer OpenVPN tunnel and capture whether public UDP TPROXY egress works.

Additional boundaries:
- Unique names/ports/networks/volumes/temp paths only.
- Do not restart/recreate/adopt/mutate production containers or Steam Deck.
- Do not commit or print secrets, generated profiles, rendered configs, private endpoint values, raw logs, or temp artifacts.
- Cleanup all isolated resources.
- Commit only source/test/doc/report changes.
- If public UDP TPROXY fails while private nested passes, report that distinction clearly.

Pre-dispatch gate:
- Task intake: clear; this is live isolated validation only, not production deployment.
- Repo orientation/reuse: use existing Docker lab/runtime patterns in `docs/DOCKER_SETUP.md`, task-package prior evidence, gitignored private endpoint file if present, existing matching gitignored bundle if available, and SSH aliases without printing endpoint values.
- Missing pieces: fresh sanitized live evidence for same-host server/client, remote moscow-tiger client, feasible matching-bundle nested private OpenVPN, and reduced public UDP echo.
- Dependency graph: one implementation/operations task is sufficient; keep slice whole and delegate to `aad-implementer` for command execution/reporting. Owner integrates report, runs evidence review, updates final report.

### Task 3: Live isolated validation and public UDP echo distinction

Goal:
- Produce sanitized evidence for the requested live isolated validation stages after the private UDP bypass fix, with cleanup and production untouched evidence.

Acceptance criteria:
- AC3/AC8 boundaries preserved: no production mutation, no secrets/logs/profiles/private endpoints committed or printed.
- AC5: vibe-practicum isolated server + vibe-practicum isolated client baseline passes or concrete blocker recorded.
- AC6: if AC5 passes, moscow-tiger isolated client baseline passes or concrete blocker recorded.
- AC2 nested: nested private OpenVPN using matching bundle passes where feasible, or infeasibility/blocker is explicit with evidence.
- Public UDP echo: reduced public non-DNS UDP echo endpoint on different host/high UDP port is attempted where possible and outcome distinguishes public TPROXY egress from private Docker-IP bypass.
- Cleanup: all isolated containers/networks/volumes/temp paths removed or retained-for-debug explicitly listed.

Test plan:
- Source `config/private-endpoints.local.env` only if readable; do not print values.
- Capture safe before/after metadata for production container(s): names/status/restart count/start time only, no env/config dumps.
- Use fresh high UDP ports and unique Compose/project/container/network/volume/temp names.
- Validate baseline through outer OpenVPN: client connect, UDP DNS result, HTTPS hostname result, literal-IP HTTPS result (or equivalent existing client-test checks).
- Validate nested private OpenVPN if feasible with matching generated bundle/profile; rewrite only temp profile remote lines.
- Public UDP echo: run isolated echo endpoint on different host/high UDP port where possible; send non-DNS UDP through outer tunnel from client and record pass/fail plus counters/routing evidence.
- Cleanup commands for every isolated resource.

Executor: `aad-implementer`.
Report path: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/aad-implementer-live-validation-after-private-bypass.md`.
Verification path: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/live-validation-after-private-bypass.md`.
Progress path: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-live-validation-after-private-bypass.md`.
Status: ready for dispatch.

## Continuation task: public non-DNS UDP through generic vpnkit TPROXY variants

User-requested goal:
- Investigate public non-DNS UDP forwarding through generic vpnkit sing-box TPROXY for an outer OpenVPN client using an isolated live UDP echo server on vibe-practicum and an isolated local-host client through the outer OpenVPN tunnel.
- Continue after any passing result; attempt all feasible variants in order and commit a sanitized results matrix/report.

Additional boundaries:
- Use the provided worktree/branch; do not create a new worktree.
- Do not restart/recreate/adopt/mutate production `vpnkit`, `current-vpnkit-1`, or Steam Deck.
- This task's client is the local host; do not use moscow-tiger as a test client unless only a read-only metadata check is needed.
- Use unique project/container/network/volume/temp names and fresh high UDP ports for every live resource.
- Keep generated profiles/logs/secrets/rendered configs/subscription URLs/private endpoints/tcpdump raw logs/temp artifacts out of git and out of reports; report only sanitized summaries.
- Source `config/private-endpoints.local.env` only if readable and without printing values; stop before live mutation if missing.

Pre-dispatch gate:
- Task intake: clear; public non-DNS UDP generic TPROXY investigation with optional robust source/config fix, not production deployment.
- Repo orientation/reuse: reuse existing vpnkit tproxy templates and routing scripts, prior live-validation task package evidence, Docker/Compose isolation conventions, `config/private-endpoints.local.env`, and source checks from prior tasks.
- Missing pieces: fresh public UDP variant matrix, route-via-outer-`tun0` evidence, UDP TPROXY/bypass counters, sanitized sing-box/tcpdump summaries, production untouched metadata, cleanup evidence, and any scoped source/config fix with tests/docs if robust.
- Dependency graph: keep as one owner slice; delegate one command-heavy implementation/investigation task to `aad-implementer`; owner integrates report/matrix, runs fresh source checks if source/test/docs changed, commits sanitized artifacts, and reports final state.

### Task 4: Public non-DNS UDP TPROXY variants matrix

Goal:
- Attempt the seven required variants in order against an isolated live UDP echo endpoint and isolated local-host outer OpenVPN client, distinguishing generic public UDP TPROXY behavior from existing private UDP bypass.

Acceptance criteria:
- AC-S1 through AC-S8 from the user routing packet are satisfied or blockers are explicit.
- The results matrix includes variant/config delta, implementation mode, isolated resource names/ports, route-via-`tun0` proof, echo result, counters, sing-box log summary, tcpdump summary, cleanup, and production untouched evidence.
- If a robust source/config fix emerges, it is implemented with targeted tests/docs and committed; otherwise only sanitized docs/reports and safe test harness changes are committed.

Test plan:
- Live/manual: variants 1-7 in required order using fresh resources and safe sanitized evidence.
- Source checks after source/test edits: `bash tests/vpnkit-setup-routing-test.sh`, `bash tests/vpnkit-singbox-template-test.sh`, `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh`, `go test ./...`, `git diff --check` if feasible.
- Final: `git status --short`, commit IDs, cleanup evidence.

Executor: `aad-implementer`.
Report path: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/aad-implementer-public-udp-variants.md`.
Verification path: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/public-udp-variants-matrix.md`.
Progress path: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-public-udp-variants.md`.
Status: ready for dispatch.

Execution ledger update for Task 4:
- 2026-06-03: Attempted to dispatch public UDP variant matrix to `aad-implementer`, but Pi nested subagent call was blocked by max depth. Owner completed only planning/report scaffolding, reused prior Variant 1 baseline public echo evidence, performed a local sing-box syntax feasibility check for Variant 2, and ran fresh source checks (`bash tests/vpnkit-setup-routing-test.sh`, `bash tests/vpnkit-singbox-template-test.sh`, `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh`, `go test ./...`, `git diff --check`). No live resources were created or cleaned by this continuation, and no production/Steam Deck commands were run. Task 4 remains blocked/partial; see `verification/public-udp-variants-matrix.md` and `reports/slice-owner-public-udp-variants.md`.
