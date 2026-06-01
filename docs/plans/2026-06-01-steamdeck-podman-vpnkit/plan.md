# Plan: Steam Deck Podman vpnkit deployment

## Task intake
Deploy and verify the merged containerized vpnkit runtime (OpenVPN + sing-box + vibe-vpn) on a Steam Deck reachable by SSH where Podman is available, without mutating the VPS or breaking the existing Docker e2e path. Use production Steam Deck deployment patterns from `~/code/positions` without copying secrets.

## Acceptance criteria
1. Repo contains safe, idempotent Podman scripts/runbook/evidence for deploying vpnkit to Steam Deck over SSH.
2. Scripts support build/run/stop/logs/cleanup and configurable SSH target, remote directory, image/tag, OpenVPN port, and optional LAN/Tailscale endpoints.
3. Runtime container includes OpenVPN + sing-box + vibe-vpn and uses appropriate TUN/capability/port/volume wiring for Podman.
4. Real configs/secrets remain gitignored and are not printed or committed.
5. Deployment method is documented exactly.
6. Steam Deck build/start/process health is attempted and verified if SSH is discoverable/reachable; blockers are documented exactly otherwise.
7. Tests are run on Steam Deck if reachable; local checks prove scripts and existing Go/Docker paths are not broken where feasible.
8. LAN and Tailscale connectivity checks from this host to the Steam Deck are attempted if endpoints are discoverable/configured.
9. Evidence/logs are tracked safely under the task package, with raw logs only under ignored `logs/` when needed.
10. Coherent changes are committed and pushed if useful.

## Scope and boundaries
- In scope: deployment scripts, runbook docs, task package evidence, safe remote Podman checks/deploy attempts.
- Out of scope: VPS mutation, committing real secrets, changing unrelated VPN behavior, requiring Docker Compose on Steam Deck.
- Preserve: existing Docker-based containerized vpnkit e2e behavior and current Go CLI contracts.

## Initial slice structure
One implementation slice is used because the work has one dominant ownership boundary: Steam Deck Podman deployment/runtime wiring plus evidence. The slice may use supporting discovery internally for `~/code/positions` patterns and SSH target discovery.

### Slice S1: Steam Deck Podman deploy/run/verify
Goal:
- Add safe Podman-over-SSH scripts and runbook for the merged vpnkit runtime, deploy/verify on Steam Deck if reachable, and collect redacted evidence.

Acceptance:
- AC1-AC10 above, with exact commands/evidence in `reports/slice-steamdeck-podman.md` and `verification/`.

Likely files:
- `scripts/vpnkit-steamdeck-*.sh`
- `docs/STEAMDECK_PODMAN_VPNKIT.md` or equivalent runbook
- `docs/plans/2026-06-01-steamdeck-podman-vpnkit/*`
- `.gitignore` only if needed for local logs/config dirs

Dependencies:
- Read-only discovery of `~/code/positions/scripts/steamdeck` and current repo Docker runtime.
- SSH target discovery from repo/configs/positions/SSH config; remote deploy proceeds only if target is discoverable and reachable.

Verification plan:
- Local: `bash -n` for scripts, `go test ./...`, relevant Docker e2e smoke or documented skip, secret leak scan of changed files.
- Remote if reachable: SSH `podman --version`, build, run, `podman ps/logs/exec`, `sing-box check`, `vibe-vpn doctor/test/apply` if feasible, OpenVPN/sing-box process health.
- Host connectivity: LAN and Tailscale reachability to Steam Deck, and OpenVPN/client checks where feasible.

## Execution ledger
- 2026-06-01: Root owner created branch/worktree and initial task package.
