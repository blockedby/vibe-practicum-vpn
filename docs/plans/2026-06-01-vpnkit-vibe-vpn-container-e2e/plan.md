# Plan: add `vibe-vpn` into the containerized vpnkit lab

## Goal
Add a repo-supported plan for running the Go `vibe-vpn` service inside the existing Dockerized vpnkit OpenVPN -> sing-box lab so future implementation can validate real VLESS subscription behavior, failover/switching, and interaction with the currently working REDIRECT path.

## Non-goals / boundaries
- Do not implement code, Dockerfile, compose, script, config, or test changes in this planning slice.
- Do not commit or document real subscription URLs, full `vless://` links, tokens, private keys, generated OpenVPN/mobile profiles, rendered sing-box configs, or VPS-specific secrets.
- Do not replace the currently working OpenVPN -> sing-box REDIRECT lab as the first implementation step.
- Do not introduce broad permanent `10.89.0.0/24` NAT/MASQUERADE bypasses.
- Do not require live VPS mutation; all real inputs must be copied/rendered by an operator into gitignored local paths.

## Current repo evidence
- `docker-compose.yml` defines `vpnkit` and `ovpn-client-test` with fixed `container_name` values today. `vpnkit` is privileged, exposes fixed host port `1194/udp`, sets `VPNKIT_ROUTING_MODE=redirect`, mounts `./secrets/vps/rendered/openvpn:/etc/openvpn:ro`, `./secrets/vps/rendered/sing-box:/etc/sing-box:ro`, and `./logs:/var/log/vpnkit`.
- `docker/vpnkit/Dockerfile` installs `openvpn`, routing tools, curl, tcpdump, and sing-box `1.13.11`, then runs `/usr/local/bin/entrypoint.sh`.
- `docker/vpnkit/entrypoint.sh` currently validates `/etc/sing-box/config.json`, starts `sing-box run` and `openvpn --config /etc/openvpn/server.conf`, waits for `tun0`, runs `setup-routing.sh`, and exits when either child exits via `wait -n`.
- `docker/vpnkit/setup-routing.sh` supports `redirect`, `tproxy`, and `tun`; current compose uses `redirect`. In redirect mode it redirects TCP from OpenVPN clients to sing-box `:2082` and UDP/53 to `:5353` for DNS hijack.
- `config/sing-box/config.json.template` uses a sing-box `redirect` inbound on `0.0.0.0:2082`, a DNS inbound on `0.0.0.0:5353`, Google DoT servers `tls://8.8.8.8` and `tls://8.8.4.4` detoured through `selected-native-out`, and route rules that hijack DNS with final `selected-native-out`.
- `scripts/vpnkit-copy-vps-secrets.sh` copies VPS OpenVPN and sing-box material into gitignored `secrets/vps/...`; `scripts/vpnkit-render-local-configs.sh` renders OpenVPN, sing-box config, and a test client profile under `secrets/vps/...`; `scripts/vpnkit-collect-evidence.sh` collects redacted compose, routing, listener, and log evidence.
- `cmd/vibe-vpn/main.go` exposes `doctor`, `test`, `daemon`, `status`, `refresh`, `pick`, `apply`, `current`, `rollback`, and related commands. `cmdDaemon` builds scheduled rotation and failover services.
- `internal/config/config.go` defines `subscription_file`, `runtime`, `sing_box_bin`, `sing_box_config`, `sing_box_service`, `state_dir`, `production_socks`, `test_socks`, service mode, health/test/logging settings, and validates sing-box runtime paths.
- `internal/singbox/singbox.go` applies a selected outbound by backing up a sing-box config and restarting a systemd service with `systemctl`; this is a mismatch for a container without systemd unless adapted or avoided initially.
- `examples/vibe-vpn-config.yaml` targets VPS paths such as `/etc/vibe-vpn/sub_url`, `/etc/sing-box-vibe/tproxy-canary.json`, `sing-box-vibe-router`, `/var/lib/vibe-vpn`, and `/var/log/vibe-vpn/`.
- `systemd/vibe-vpn.service` exists for VPS install, but the container lab should not depend on systemd as its process supervisor.
- `docs/plans/2026-05-31-containerized-vpnkit/plan.md` records the current lab outcome: TPROXY and sing-box TUN were rejected with evidence; the final working path is REDIRECT + DNS hijack, with DNS/TCP leaving through `outbound/vless[selected-native-out]`.
- `~/code/positions` was accessible. High-level reusable pattern observed: e2e workflows use isolated Docker Compose services/profiles, explicit setup commands, environment/config files such as `.env.test`, health/readiness checks, and documented cleanup. No secrets were copied or inspected beyond filenames/documented patterns.

## Proposed architecture
### Server container process model
- Keep `vpnkit` as the single server container that owns OpenVPN, sing-box, routing setup, and the new `vibe-vpn` process for lab runs.
- Replace the ad-hoc two-background-process entrypoint with explicit lightweight supervision in the entrypoint or a small shell supervisor: start sing-box, OpenVPN, and optionally `vibe-vpn daemon`; trap TERM/INT; fail the container if a required child exits unexpectedly; collect last logs before exit.
- Avoid systemd in the container. `vibe-vpn` should be launched directly as `/usr/local/bin/vibe-vpn daemon --config /etc/vibe-vpn/config.yaml` for daemon tests, and as CLI subcommands for setup/acceptance checks.
- Build or copy the `vibe-vpn` binary into the image during implementation, preferably via a multi-stage Dockerfile using the repo module, so the lab tests the current branch binary rather than a host-local artifact.

### Binary and paths
- Binary path: `/usr/local/bin/vibe-vpn` inside `vpnkit`.
- Container config path: `/etc/vibe-vpn/config.yaml` rendered from a tracked sanitized template plus gitignored inputs.
- Subscription file path: `/etc/vibe-vpn/sub_url`, mounted read-only from a gitignored local file.
- Optional static nodes path: `/etc/vibe-vpn/extra-nodes.json`, mounted read-only when present.
- State/log paths: `/var/lib/vibe-vpn` and `/var/log/vibe-vpn`, backed by Docker volumes or `./logs`/gitignored state directories for evidence collection.
- sing-box config path for the lab: start with `/etc/sing-box/config.json` because it is already mounted and checked by the entrypoint.

### Coexistence with sing-box/OpenVPN/routing
- Initial implementation should run `vibe-vpn` in observe/control-limited mode, not as the owner of sing-box process supervision.
- sing-box remains started by the container supervisor using the rendered REDIRECT-compatible config; OpenVPN remains started by the supervisor; `setup-routing.sh` remains the owner of packet steering.
- `vibe-vpn` may read subscriptions, run isolated benchmark/test flows, write state, and report current/selected nodes. It should not restart sing-box through `systemctl` in the first slice.
- For apply/failover slices, add a container runtime adapter or config mode that updates `/etc/sing-box/config.json` and signals/restarts the supervised sing-box process without systemd. Do not reuse `internal/singbox.Apply`'s systemctl restart path unmodified inside the container.

## Config and secrets design
- Add a tracked sanitized template such as `config/vibe-vpn/container-lab.yaml.template` in a later implementation slice; this planning slice does not add it.
- Keep real inputs in gitignored `secrets/vps/...` or a new gitignored `secrets/vpnkit/vibe-vpn/...` subtree. Required operator-provided files should include subscription URL(s), optional extra nodes, and rendered OpenVPN/sing-box inputs.
- Rendered configs remain gitignored: `/secrets/vps/rendered/sing-box/config.json`, `/secrets/vps/rendered/openvpn/server.conf`, `/secrets/vps/openvpn/client/test-client.ovpn`, and future rendered `/secrets/vps/rendered/vibe-vpn/config.yaml`.
- Reports and evidence must redact full `vless://` links, UUIDs, private keys, passwords, tokens, and subscription URLs. Extend `scripts/vpnkit-collect-evidence.sh` redaction if new vibe-vpn logs include node links or config snippets.
- Mount secrets read-only into the container where possible; only state/log directories should be writable.

## E2E design
### Parallel-safe runner and compose isolation
- E2E execution must be via a tracked script, proposed path `scripts/vpnkit-vibe-vpn-e2e.sh`, rather than a loose sequence of manual `docker compose` commands.
- Script flags should include at minimum: `--run-id ID` (default: UTC timestamp plus short random suffix), `--log-file PATH` (default under `logs/vpnkit-vibe-vpn-e2e/<run-id>.log`), `--keep-artifacts` (preserve containers/images/logs/state for debugging), `--no-build` (reuse an existing image when explicitly requested), and `--cleanup-images`/`--no-cleanup-images` (default cleanup on success).
- The script must set a unique `COMPOSE_PROJECT_NAME`, for example `vpnkit-vibe-vpn-e2e-${run_id}`, or pass `docker compose -p` consistently for every compose command. Run IDs must be shell-safe and included in log/evidence paths.
- Compose services used by e2e must not use fixed `container_name` values, or the e2e runner must use a compose override/profile that removes/replaces them. Fixed names such as `vpnkit` and `ovpn-client-test` would prevent parallel runs.
- Avoid fixed host port conflicts for parallel runs. Prefer no published OpenVPN host port for internal e2e client checks; if a host port is required, the script must allocate a free UDP port or allow `--openvpn-port 0|PORT` and pass it through compose instead of hard-coding `1194:1194/udp`.
- All stdout/stderr from setup, build, compose, `vibe-vpn`, client probes, and evidence collection must be tee'd to a per-run log file under ignored `logs/`. The log path must be printed at start and recorded in the final report/evidence.

### Containers
- `vpnkit`: privileged gateway container running sing-box, OpenVPN, routing setup, and optionally `vibe-vpn daemon` or one-shot CLI commands.
- `ovpn-client-test`: existing test client container using rendered `test-client.ovpn` to join the OpenVPN server and run network probes.
- Optional future `vpnkit-vibe-vpn-cli`/compose profile: one-shot helper container or `docker compose exec vpnkit vibe-vpn ...` commands for `doctor`, `test`, `list`, `pick`, and `current` without changing long-running process mode.

### Commands to run later
```bash
scripts/vpnkit-copy-vps-secrets.sh vibe-practicum
scripts/vpnkit-render-local-configs.sh
# future implementation: render vibe-vpn config too

scripts/vpnkit-vibe-vpn-e2e.sh \
  --run-id manual-$(date -u +%Y%m%dT%H%M%SZ) \
  --log-file logs/vpnkit-vibe-vpn-e2e/manual-$(date -u +%Y%m%dT%H%M%SZ).log
```

The runner should internally execute the compose lifecycle with the unique project name/run-id, for example:

```bash
docker compose -p "$COMPOSE_PROJECT_NAME" build vpnkit ovpn-client-test
docker compose -p "$COMPOSE_PROJECT_NAME" up -d vpnkit
docker compose -p "$COMPOSE_PROJECT_NAME" exec -T vpnkit vibe-vpn doctor --config /etc/vibe-vpn/config.yaml
docker compose -p "$COMPOSE_PROJECT_NAME" exec -T vpnkit vibe-vpn test --config /etc/vibe-vpn/config.yaml --limit-kib 64 --max 2
docker compose -p "$COMPOSE_PROJECT_NAME" --profile test up --abort-on-container-exit ovpn-client-test
scripts/vpnkit-collect-evidence.sh "logs/vpnkit-vibe-vpn-evidence-${RUN_ID}.txt"
```

Cleanup policy for the runner:
- Always attempt `docker compose -p "$COMPOSE_PROJECT_NAME" down --remove-orphans --volumes` at the end of a run unless `--keep-artifacts` is set.
- On success, remove e2e-built images (for example with `docker compose -p "$COMPOSE_PROJECT_NAME" down --rmi local` or explicit image IDs captured during build) so passing runs do not accumulate local build artifacts.
- On failure, keep containers/images/volumes/evidence unless the operator explicitly requests cleanup, and print the exact inspect/log/cleanup commands with the run-id/project name.
- Never delete the per-run log file or redacted evidence artifacts automatically.

### Acceptance checks and evidence
- Compose/config readiness: `docker compose config`, `docker compose build`, `sing-box check -c /etc/sing-box/config.json`, `vibe-vpn doctor --config /etc/vibe-vpn/config.yaml`.
- Process readiness: `ps`/logs show sing-box, OpenVPN, and expected vibe-vpn mode running; container exits if a required process dies.
- OpenVPN path: test client receives an OpenVPN IP, `tun0` exists in `vpnkit`, and REDIRECT counters increase for client traffic.
- DNS path: DNS queries from the test client are hijacked to sing-box and resolved through Google DoT detoured via `selected-native-out`; no direct DNS bypass is introduced.
- HTTPS/domain path: `curl https://ifconfig.me` or equivalent from the OpenVPN client succeeds through selected VLESS; sing-box logs show outbound `selected-native-out`.
- Literal-IP path: a literal-IP HTTPS check succeeds through the same path to avoid relying only on DNS behavior.
- vibe-vpn subscription validation: `vibe-vpn test --max 2` uses real gitignored subscription input and records OK/failed node results without printing secrets unredacted.
- Switching/failover: after a later apply/runtime-adapter slice, `vibe-vpn apply best` or daemon failover changes the active sing-box outbound and OpenVPN client traffic continues to pass.
- Evidence artifacts: redacted `scripts/vpnkit-collect-evidence.sh` output, the runner's per-run log file under `logs/vpnkit-vibe-vpn-e2e/<run-id>.log`, docker logs, selected command outputs, and `git status --short` for changed implementation files.

## Integration strategy with existing REDIRECT path
- Preserve REDIRECT as the baseline packet path because the 2026-05-31 package records it as the proven Docker-compatible architecture.
- Initial `vibe-vpn` role: observe/control-limited. It should validate subscriptions and benchmark candidates with isolated test SOCKS/runtime behavior where possible, while the entrypoint-owned sing-box continues to serve OpenVPN traffic.
- Later `vibe-vpn` role: controlled ownership of sing-box config selection only, via a container-safe adapter. It may render/update the `selected-native-out` in `/etc/sing-box/config.json` and request a supervised sing-box restart/reload, but it should not own OpenVPN or routing setup.
- Avoid duplicate sing-box ownership: exactly one component should start/stop the sing-box process. The supervisor starts/stops sing-box; `vibe-vpn` asks the supervisor or container adapter for reload/restart when apply/failover is enabled.

## Risks and decisions
- Process supervision: the current entrypoint exits on first child death but has no third-process policy. Decide required/optional `vibe-vpn` modes before implementation.
- Duplicate sing-box ownership: VPS code assumes systemd service restarts. Container work must not let both entrypoint and `vibe-vpn` independently own the sing-box process.
- Preserve Google DoT: keep existing template's Google DoT over `selected-native-out`; e2e must prove DNS is not bypassing the VLESS route.
- No broad NAT: retain REDIRECT/DNS hijack or another scoped mechanism; broad MASQUERADE would invalidate the lab goal.
- Real VLESS validation: fully meaningful tests require operator-provided subscription secrets in gitignored files and network access from Docker.
- Failover/switching tests: require at least two valid candidate nodes or a controlled invalid-node fixture plus one valid node; plan for skip/waiver only when insufficient real subscription data is available.
- sing-box config format drift: Dockerfile pins sing-box 1.13.11 and current DNS syntax emits a legacy warning; implementation should either preserve the known working version or update template/tests together.

## Implementation slices with acceptance criteria
### Slice 1: Build and wire `vibe-vpn` into the vpnkit image in observe mode
Goal: container image contains the branch's `vibe-vpn` binary and can run `doctor`/`test` against gitignored lab config without changing the working REDIRECT data path.
Acceptance criteria:
- `docker compose build vpnkit` builds `vibe-vpn` into `/usr/local/bin/vibe-vpn`.
- `docker compose exec -T vpnkit vibe-vpn doctor --config /etc/vibe-vpn/config.yaml` passes with mounted gitignored inputs.
- `vibe-vpn test --config /etc/vibe-vpn/config.yaml --limit-kib 64 --max 2` runs against real subscription data without unredacted secret output in committed evidence.
- Existing OpenVPN client REDIRECT e2e still passes.

### Slice 2: Container-safe config rendering and secret workflow
Goal: operator can render vibe-vpn container config from templates and gitignored inputs using the existing `vpnkit-render-local-configs.sh` pattern.
Acceptance criteria:
- Tracked templates contain no real subscription URLs, full VLESS links, tokens, private keys, generated profiles, or VPS-specific secrets.
- Rendered vibe-vpn config and subscription files are gitignored and mounted read-only.
- Evidence collector redacts vibe-vpn-specific secret/log patterns.
- Static secret grep over tracked docs/config/scripts passes.

### Slice 3: Supervised daemon mode without sing-box ownership conflict
Goal: optional compose mode runs `vibe-vpn daemon` alongside sing-box/OpenVPN under one supervisor while sing-box process ownership remains unambiguous.
Acceptance criteria:
- Supervisor policy is documented and implemented: required children, optional children, signal handling, and failure behavior.
- Logs show sing-box, OpenVPN, and `vibe-vpn daemon` startup; killing a required child fails the container predictably.
- `vibe-vpn daemon` does not call systemctl inside the container in this slice.
- REDIRECT OpenVPN e2e still passes while daemon runs.

### Slice 4: Container runtime adapter for apply/failover switching
Goal: enable `vibe-vpn` to switch the selected sing-box outbound in the container without systemd and without taking over routing/OpenVPN.
Acceptance criteria:
- Apply path updates only the intended selected outbound/config and creates backups under the configured state dir.
- sing-box is reloaded/restarted by a single container-safe mechanism owned by the supervisor/adapter.
- `vibe-vpn current`, `apply best`, and rollback semantics are verified in-container.
- OpenVPN client traffic succeeds before and after a switch; evidence shows traffic uses the newly selected outbound.

### Slice 5: Real failover/switching e2e runner and runbook
Goal: document and prove the full lab flow with real gitignored VLESS inputs through a parallel-safe script.
Acceptance criteria:
- E2E is invoked through `scripts/vpnkit-vibe-vpn-e2e.sh`; the script supports `--run-id`, `--log-file`, `--keep-artifacts`, `--no-build`, and image cleanup toggles.
- Two e2e runs can be started concurrently without fixed container-name or host-port collisions, using unique `COMPOSE_PROJECT_NAME`/run-id isolation and no hard-coded host OpenVPN port dependency.
- Passing runs execute compose cleanup and remove locally built e2e images; failing runs preserve containers/images/volumes/logs/evidence by default for debugging and print cleanup instructions.
- Every run writes a complete per-run log under ignored `logs/` and records the path in the evidence/report.
- E2E report includes redacted command outputs for doctor, test, OpenVPN path, DNS path, HTTPS/domain path, literal-IP path, apply/switch, and failure-triggered failover where feasible.
- If insufficient valid nodes exist, report the exact limitation and prove the one-node path plus negative invalid-node handling.
- Runbook lists setup, run, evidence, cleanup, and troubleshooting commands.
- `git status --short` and secret-safety grep are included in final evidence.

## Dependency graph
- Slice 1 depends on the current REDIRECT lab and existing Go build passing.
- Slice 2 can run in parallel with Slice 1, but final acceptance for Slice 1 needs the rendered config from Slice 2.
- Slice 3 depends on Slice 1.
- Slice 4 depends on Slice 3 and a design decision for the container runtime adapter.
- Slice 5 depends on Slices 1-4 and operator-provided real subscription/OpenVPN secrets.

## Later verification commands
```bash
git status --short
go test ./...
go vet ./...
go build -o /tmp/vibe-vpn ./cmd/vibe-vpn
bash -n scripts/vpnkit-copy-vps-secrets.sh scripts/vpnkit-render-local-configs.sh scripts/vpnkit-collect-evidence.sh
docker compose config
docker compose build vpnkit ovpn-client-test
docker compose up -d vpnkit
docker compose exec -T vpnkit sing-box check -c /etc/sing-box/config.json
docker compose exec -T vpnkit vibe-vpn doctor --config /etc/vibe-vpn/config.yaml
docker compose exec -T vpnkit vibe-vpn test --config /etc/vibe-vpn/config.yaml --limit-kib 64 --max 2
docker compose --profile test up --abort-on-container-exit ovpn-client-test
scripts/vpnkit-collect-evidence.sh
# Static safety checks, examples only; tune patterns before enforcing:
git grep -nE 'vless://|subscription|private[_-]?key|BEGIN (RSA |OPENSSH |PRIVATE )?KEY' -- ':!docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/plan.md'
git grep -nE 'MASQUERADE.*10\.89\.0\.0/24|10\.89\.0\.0/24.*MASQUERADE'
```

## Done definition for future implementation
- The vpnkit container can run sing-box, OpenVPN, routing setup, and `vibe-vpn` in the selected mode under a clear supervisor.
- Real gitignored VLESS subscription input can be validated by `vibe-vpn` inside the container.
- Existing REDIRECT OpenVPN client traffic continues to pass through sing-box selected VLESS outbound, including DNS via Google DoT over `selected-native-out`.
- Switching/failover either works with a container-safe sing-box adapter or is explicitly deferred with blocker evidence.
- All evidence is redacted, reproducible by documented script commands, written to ignored per-run logs/evidence files, and contains no committed secrets.
- E2E runs are parallel-safe: no fixed container names, no fixed host port conflicts, unique compose project/run-id isolation, and deterministic cleanup.
- Successful script runs remove compose resources and locally built e2e images; failed runs keep artifacts for debugging unless explicitly overridden.
- No broad NAT bypass or duplicate sing-box process ownership is introduced.

## Planning-slice acceptance verification
- Plan file exists at `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/plan.md`.
- The plan cites concrete repo evidence from `docker-compose.yml`, `docker/vpnkit/*`, `config/sing-box/config.json.template`, `scripts/vpnkit-*`, `cmd/vibe-vpn`, `internal/*`, examples, systemd, and `docs/plans/2026-05-31-containerized-vpnkit/plan.md`.
- The plan preserves planning-only scope and changes only docs under this task package.
- The plan explicitly requires a parallel-safe script-based e2e runner with unique compose project/run-id isolation, no fixed e2e container names, no fixed host port conflicts, per-run logs under ignored `logs/`, success cleanup including image removal, failure artifact retention, and acceptance criteria for these behaviors.
- `~/code/positions` was accessible; only high-level e2e isolation/config patterns were observed.
- No secrets were copied into repo docs.

## Implementation ledger (2026-06-01)

Status: implemented observe/control-limited container e2e scaffolding in branch `pi/containerized-vpnkit-openvpn-singbox`.

Completed:
- Multi-stage `docker/vpnkit/Dockerfile` builds `/usr/local/bin/vibe-vpn` from the current Go branch and keeps OpenVPN + sing-box in the runtime image.
- `docker-compose.yml` uses repo-root Docker build context, removes fixed container names, makes host OpenVPN port configurable for the manual path, and mounts rendered gitignored vibe-vpn config/secrets plus state/log paths.
- Added sanitized `config/vibe-vpn/container-lab.yaml.template` and extended `scripts/vpnkit-render-local-configs.sh` to render `secrets/vps/rendered/vibe-vpn/config.yaml`, copy a gitignored subscription input when present, create an empty optional `extra-nodes.json`, and warn clearly when the subscription input is absent.
- Added tracked parallel-safe `scripts/vpnkit-vibe-vpn-e2e.sh` with `--run-id`, `--log-file`, `--keep-artifacts`, `--no-build`, `--cleanup-images`, and `--no-cleanup-images`. It uses unique Compose project names, generated e2e override with no host OpenVPN port, per-run logs, success cleanup including local images, and failure artifact retention by default.
- Extended evidence collection redaction and added vibe-vpn binary/doctor evidence snippets.
- Added `docs/VPNKIT_VIBE_VPN_RUNBOOK.md` and `.dockerignore` to avoid Docker build context secrets/logs.

Verification evidence:
- See `verification/local-implementation.md` for fresh command results.
- Full real OpenVPN/DNS/HTTPS/vibe-vpn subscription e2e is blocked locally by absent gitignored subscription input (`secrets/vps/rendered/vibe-vpn/sub_url`); missing-input behavior was verified.

Open limitations:
- Container-safe `apply`, switching, and daemon failover remain deferred because the current apply path uses systemd service restart. This slice intentionally delivers observe-mode e2e and documents the follow-up adapter need.
