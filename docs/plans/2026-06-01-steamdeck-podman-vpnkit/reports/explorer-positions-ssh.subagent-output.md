## Task
- Mission: discover Steam Deck Podman deployment patterns and safe SSH targets for positions-os without exposing secrets.
- Target: `scripts/steamdeck/*`, `docker-compose.deck.yml`, repo README/Taskfile, and local SSH config.
- Boundaries: read-only only; no remote mutations; no secret values printed.
- Done when: reusable deploy patterns, state/layout conventions, and likely SSH aliases/IPs are identified with evidence.
- Expected evidence: exact file paths, commands, and short command outputs.

## Context
- Thread: Steam Deck Podman vpnkit deployment root task
- Slice: read-only discovery for positions Steam Deck Podman production patterns and SSH target discovery
- Task name: Steam Deck Podman vpnkit deployment
- Task package: `docs/plans/2026-06-01-steamdeck-podman-vpnkit`
- Report path: `docs/plans/2026-06-01-steamdeck-podman-vpnkit/reports/explorer-positions-ssh.subagent-output.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit`
- Branch: `pi/steamdeck-podman-vpnkit`
- Verify scope: reusable scripts/patterns and safe SSH target aliases

## Project shape
- Runtime/framework/package manager: Go backend + React frontend; `task`/bash drive deployment.
- App type / subsystem: Steam Deck production deploy and host bootstrap scripts.
- Main entrypoints: `task prod-deploy`, `scripts/steamdeck/03-deploy.sh`, `scripts/steamdeck/deploy-on-deck.sh`, `task prod-status`, `task steamdeck-clean-space`.
- Relevant directories/files: `scripts/steamdeck/README.md`, `scripts/steamdeck/{build-bundle.sh,deploy-lib.sh,deploy-on-deck.sh,03-deploy.sh,04-setup-autostart.sh,05-setup-host-tailscale.sh,clean-space.sh}`, `docker-compose.deck.yml`, `Taskfile.yml`, `README.md`.
- Relevant commands/checks: `task steamdeck-regressions`, `ssh -G <alias>`, `ssh <alias> hostname`, `ssh <alias> 'tailscale ip -4'`, `ssh <alias> 'podman --version'`.

## Scope discovery
- Requested behavior maps to: build-on-PC / apply-on-Deck bundle workflow, state-dir conventions, host Tailscale bootstrap, and SSH alias selection.
- Likely in scope: deploy bundle creation, remote bundle staging, Deck-side apply/resume, runtime verification, cleanup conventions, LAN vs Tailscale target aliases.
- Possibly in scope: whether to prefer `deck` vs `positions-deck-ts` in operator docs.
- Out of scope: code changes, remote mutations, secret inspection.

## Existing implementations and reuse candidates
- `scripts/steamdeck/build-bundle.sh`: builds a bundle from `origin/main`, writes `manifest.env` + `services.txt`, and archives `images/*.tar` into `tmp/positions-bundle.*` by default.
- `scripts/steamdeck/deploy-lib.sh`: owns `DOCKER_HOST`/`CONTAINER_SOCKET` setup, image loading, deploy lock handling, bundle payload resolution, version verification, and deployed-record writing.
- `scripts/steamdeck/deploy-on-deck.sh`: applies bundles from `~/.local/state/positions-os/bundles`, extracts into `~/.local/state/positions-os/deploy-extract.*`, checks `.env` vs `.env.example`, restarts affected services, verifies backend/frontend versions, and writes `~/.local/state/positions-os/deployed.env`.
- `scripts/steamdeck/03-deploy.sh`: PC-side wrapper that resolves the Deck home, stages the bundle under `~/.local/state/positions-os/bundles`, and SSHes into Deck to call `apply-bundle`.
- `scripts/steamdeck/04-setup-autostart.sh`: installs a systemd user unit whose `ExecStart` is `deploy-on-deck.sh resume-last`.
- `scripts/steamdeck/05-setup-host-tailscale.sh`: creates `tailscale.config` (hostname `positions-deck`, `TAILSCALE_SSH=true`, routes on, DNS off) and reconciles host Tailscale state.
- `scripts/steamdeck/clean-space.sh`: dry-run-first cleanup for backups, deploy extracts, bundle archives, and optional Podman image pruning.
- `docker-compose.deck.yml`: Deck overlay disables builds, pins `image:` names to `${GIT_SHA:-latest}`, and adds explicit DNS for outbound-capable services.
- `Taskfile.yml`: `prod-deploy` uses `scripts/steamdeck/03-deploy.sh`; `prod-status`/`prod-logs`/`prod-down`/`prod-up` all assume `deck`.

## Existing patterns to follow
- Routing / navigation: not applicable.
- API / service: bundle verification hits backend `GET /api/version` and frontend `/usr/share/nginx/html/version.env`.
- Data model / schema: deployment record file is `~/.local/state/positions-os/deployed.env`.
- Config / env / permissions: `.env.example` includes `CONTAINER_SOCKET=/var/run/docker.sock` and `TS_AUTHKEY`; Deck scripts skip `CONTAINER_SOCKET` when validating missing keys.
- Deployment/runtime: rootless Podman socket path is `/run/user/$UID/podman/podman.sock`; `docker-compose.deck.yml` is the runtime overlay; systemd user service is `~/.config/systemd/user/positions.service`.
- Tests / fixtures: shell regressions cover `deploy_staging_path`, `deploy_bundle_extract_root`, `build_bundle_*`, `host_tailscale_bootstrap`, `compose_without_tailscale`, `deploy_container_socket`, `clean_space`.
- Docs/ops: `scripts/steamdeck/README.md` is the current operational source of truth for setup/deploy/recovery.

## External context checked
- None.

## Missing pieces
- No blocking missing implementation pieces identified for this discovery scope.
- No rsync-based transfer path was found; current transfer is `scp` of the tarball bundle.
- No tar exclusion pattern was found; bundle creation is a straight `tar -czf` of the bundle directory.

## Suggested plan tasks
- Reuse the existing `task prod-deploy` / `03-deploy.sh` bundle flow for production deploys.
  - Primary verification: `task steamdeck-regressions` for shell-contract coverage.
  - Dependencies: none.
- Use the current state layout (`~/.local/state/positions-os/{bundles,deploy-extract.*,deployed.env,deploy.lock}`) for any follow-on scripts.
  - Primary verification: `task prod-status` / `task prod-logs` after a deploy.
  - Dependencies: none.

## Risks and unknowns
- Blocking:
  - none identified in this discovery pass.
- Non-blocking follow-up candidates:
  - `deck` is the repo-default SSH alias, while `positions-deck-ts` is the portable Tailscale-style alias; future docs should be explicit about LAN vs VPN reachability.
  - Avoid echoing `.env`/`tailscale.config` values in future reports; only key names and file paths are safe.

## Suggested verification
- Targeted:
  - `ssh -G deck` → `hostname 192.168.50.13`, `user deck`.
  - `ssh -G steamdeck-ts` → `hostname 100.94.95.32`, `port 2222`, `user deck`.
  - `ssh deck hostname` → `steamdeck`.
  - `ssh steamdeck-ts 'tailscale ip -4'` → `100.94.95.32`.
  - `ssh deck 'podman --version'` → `podman version 5.3.2`.
- Broader/final:
  - `task steamdeck-regressions` for shell contract coverage if any Steam Deck script changes are made.
  - `task prod-deploy` followed by `task prod-status` if a full end-to-end deploy needs confirmation.
