## Task
- Mission: discover the merged Docker vpnkit runtime and identify Podman deployment hook points for Steam Deck without changing source code.
- Target: `docker-compose.yml`, `docker/vpnkit/*`, `docker/ovpn-client-test/*`, `config/*vpnkit*`, `scripts/vpnkit-*`, `docs/CONTAINERIZED_VPNKIT_RUNBOOK.md`.
- Boundaries: read-only; no edits; no secret values printed; preserve Docker e2e path.
- Done when: owner can see exact runtime files, commands, ports/volumes/secrets, health checks, and where a Podman wrapper should attach.
- Expected evidence: exact paths, commands, checked outputs, and reuse candidates.

## Context
- Thread: Steam Deck Podman vpnkit deployment root task.
- Slice: read-only repo discovery for current Docker vpnkit runtime and tests.
- Task name: Steam Deck Podman vpnkit deployment
- Task package: `docs/plans/2026-06-01-steamdeck-podman-vpnkit`
- Report path: `docs/plans/2026-06-01-steamdeck-podman-vpnkit/reports/explorer-vpnkit-runtime.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit`
- Branch: `pi/steamdeck-podman-vpnkit`
- Verify scope: current Docker runtime files, config/secrets expectations, tests, and Docker e2e commands to preserve.

## Project shape
- Runtime/framework/package manager: Go + Bash + Docker Compose.
- App type / subsystem: containerized VPN lab (`OpenVPN server + sing-box + vibe-vpn + test client`).
- Main entrypoints: `docker-compose.yml`, `docker/vpnkit/entrypoint.sh`, `scripts/vpnkit-vibe-vpn-e2e.sh`, `scripts/vpnkit-render-local-configs.sh`, `scripts/vpnkit-copy-vps-secrets.sh`, `docs/CONTAINERIZED_VPNKIT_RUNBOOK.md`.
- Relevant directories/files: `docker/vpnkit/`, `docker/ovpn-client-test/`, `config/openvpn/`, `config/sing-box/`, `config/vibe-vpn/`, `secrets/vps/` (gitignored), `logs/` (gitignored).
- Relevant commands/checks: `docker compose build`, `docker compose up -d vpnkit`, `docker compose --profile test run --rm ovpn-client-test`, `scripts/vpnkit-vibe-vpn-e2e.sh [--switching]`.

## Scope discovery
- Requested behavior maps to: a Steam Deck Podman wrapper around the existing vpnkit lab, not a redesign of the lab itself.
- Likely in scope: deck-specific build/run/stop/logs/cleanup scripts, SSH/Podman socket wiring, runbook, and remote evidence capture.
- Possibly in scope: a small task-package progress/report artifact and optional `task` targets.
- Out of scope: changing OpenVPN/sing-box/vibe-vpn runtime semantics, changing Docker e2e assertions, or committing secrets.

## Spec compliance
- Current Docker runtime files mapped: done.
  - Evidence: `git show 84de59b --stat --name-only` shows `docker-compose.yml`, `docker/vpnkit/*`, `docker/ovpn-client-test/*`, `config/*`, `scripts/vpnkit-*`, `docs/CONTAINERIZED_VPNKIT_RUNBOOK.md`.
- Build/run/test commands identified: done.
  - Evidence: `docs/CONTAINERIZED_VPNKIT_RUNBOOK.md:32-57` and `scripts/vpnkit-vibe-vpn-e2e.sh:145-167`.
- Podman hook point identified without breaking Docker e2e: done.
  - Evidence: current Docker runner is isolated in `scripts/vpnkit-vibe-vpn-e2e.sh`; positions Steam Deck flow uses Podman socket wrappers.

## Acceptance verification
- `bash -n scripts/vpnkit-render-local-configs.sh scripts/vpnkit-copy-vps-secrets.sh scripts/vpnkit-collect-evidence.sh scripts/vpnkit-vibe-vpn-e2e.sh docker/vpnkit/entrypoint.sh docker/vpnkit/setup-routing.sh docker/ovpn-client-test/entrypoint.sh docker/ovpn-client-test/run-tests.sh`: passed.
- `docker compose config`: passed.
- `docker compose --profile test config`: passed.
- `git show 84de59b --stat --name-only`: passed as merged-file inventory for the main runtime commit.

## Existing implementations and reuse candidates
- `docker-compose.yml:1-50`: vpnkit + test-client services, `1194/udp`, `NET_ADMIN/NET_RAW`, `/dev/net/tun`, sysctls, read-only secret mounts, state/log volumes.
- `docker/vpnkit/Dockerfile:1-19`: multi-stage build of `vibe-vpn`, installs `openvpn` + `sing-box 1.13.11`, copies entrypoint/routing scripts.
- `docker/vpnkit/entrypoint.sh:4-85`: validates configs, starts sing-box then OpenVPN, waits for `tun0`, runs routing setup, restarts sing-box on request-file changes, exits if either process dies.
- `docker/vpnkit/setup-routing.sh:4-70`: supports `redirect` (default), `tproxy`, and `tun`; no broad `MASQUERADE` path.
- `docker/ovpn-client-test/entrypoint.sh:3-15` and `run-tests.sh:3-15`: separate client namespace, waits for `10.89.0.x`, then checks `ip addr`, `ip route`, DNS, HTTPS, and literal-IP HTTPS.
- `config/vibe-vpn/container-lab.yaml.template:1-34`: container-safe vibe-vpn config with `vpnkit-supervised-sing-box`, disabled daemon mode, state/log paths, and health URLs.
- `scripts/vpnkit-render-local-configs.sh:3-72`: renders gitignored configs from `secrets/vps`, extracts `selected-native-out`, generates `test-client.ovpn`, and creates a missing-subscription note when needed.
- `scripts/vpnkit-vibe-vpn-e2e.sh:12-167`: current Docker e2e runner; unique run-id/project, redaction, secret gating, optional `--switching`, cleanup toggles, evidence capture.
- `scripts/vpnkit-collect-evidence.sh:1-35`: redacted `docker compose ps/logs`, routing, listeners, and `vibe-vpn doctor` evidence.

## Existing patterns to follow
- Routing / navigation: not applicable.
- Components / UI: not applicable.
- API / service: keep lifecycle in shell wrappers; preserve `docker compose` as the lab interface.
- Config / env / secrets: keep real material in gitignored `secrets/vps/...`; rendered files are generated, not committed.
- Tests / fixtures: reuse the separate `ovpn-client-test` namespace and the runbook/e2e runner’s redacted evidence style.
- Runtime / deployment wiring: follow Steam Deck patterns from `positions`: `DOCKER_HOST=unix:///run/user/$UID/podman/podman.sock`, `docker-compose`/`docker compose` against Podman, and `up -d --wait` deploy semantics.

## External context checked
- Source: `/home/kcnc/code/positions/scripts/steamdeck/README.md`, `deploy-lib.sh`, `deploy-on-deck.sh`, `build-bundle.sh`
  - Type: connected
  - Relationship evidence: user explicitly requested Steam Deck patterns from `~/code/positions`; repo scripts already implement Podman-on-Deck deployment.
  - Question: how Steam Deck deploys attach to Podman without rewriting the app runtime.
  - Finding: Deck flow sets `DOCKER_HOST` to the user Podman socket, auto-starts `podman.socket` when available, and uses `docker-compose ... up -d --wait` on the target; `build-bundle.sh`/`deploy-on-deck.sh` treat Podman as the container backend but keep compose-based service control.
  - Ref: local repo paths above.

## Missing pieces
- UI/page/route: none.
- API/service: no Steam Deck vpnkit wrapper scripts yet (`build/run/stop/logs/cleanup` over SSH/Podman).
- Data/model/schema: none.
- Integration/wiring: no Podman-specific vpnkit entrypoints, no SSH target/remote-dir/image-tag flags, no Deck-side task or wrapper.
- Tests: no regression tests for a Podman wrapper, no live Deck smoke/evidence.
- Docs/ops: no dedicated Steam Deck Podman vpnkit runbook yet; current runbook is Docker-centric.
- Other project-specific pieces: no explicit optional LAN/Tailscale endpoint handling for vpnkit deployment.

## Suggested plan tasks
- Add a small Steam Deck Podman wrapper layer (likely under `scripts/vpnkit-*`): build, run, stop, logs, cleanup, and remote SSH target/dir/image/tag flags.
  - Primary verification: `bash -n` on new wrappers; dry-run command traces.
  - Dependencies: none.
- Add a Steam Deck Podman runbook that preserves the current Docker e2e path and documents which commands use Podman vs Docker.
  - Primary verification: docs review against existing runner/runbook.
  - Dependencies: wrapper shape.
- If a Deck target is reachable, run a live Podman smoke with redacted evidence; otherwise record the exact missing access/target.
  - Primary verification: SSH `podman --version`, compose build/up, logs, client probe.
  - Dependencies: reachable Steam Deck and local secrets.

## Risks and unknowns
- Blocking:
  - Steam Deck Podman may be rootless or otherwise unable to honor `privileged`, `/dev/net/tun`, or iptables/sysctl behavior as declared; the target runtime model is unverified.
  - No reachable SSH/Podman target was discovered in this repo evidence.
- Non-blocking follow-up candidates:
  - `VPNKIT_ROUTING_MODE=tproxy` remains diagnostic only; default Docker lab uses `redirect`.
  - `scripts/vpnkit-vibe-vpn-e2e.sh` should stay Docker-only so existing e2e semantics and cleanup remain stable.

## Suggested verification
- Targeted:
  - `bash -n scripts/vpnkit-*.sh docker/vpnkit/*.sh docker/ovpn-client-test/*.sh`
  - `docker compose config`
  - `docker compose --profile test config`
- Broader/final:
  - `scripts/vpnkit-render-local-configs.sh && scripts/vpnkit-vibe-vpn-e2e.sh --switching` when gitignored secrets exist.
  - On Deck, `ssh <deck> 'podman --version'` followed by a Podman-backed compose smoke if the target is reachable.
  - `scripts/vpnkit-collect-evidence.sh` for redacted runtime evidence.

## Verdict
- Status: success for discovery.
- Goal state: current Docker vpnkit runtime and Docker e2e path are mapped; Podman hook points are identified.
- Final readiness: ready for owner planning / implementation.
- Summary: the repo already contains a complete Docker lab plus redacted e2e/evidence scripts; the missing work is a separate Steam Deck Podman wrapper and its live validation, not changes to the Docker lab itself.