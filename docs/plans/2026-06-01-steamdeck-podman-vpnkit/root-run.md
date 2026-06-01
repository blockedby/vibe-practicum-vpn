# Root run: Steam Deck Podman vpnkit deployment

## Task
- Mission: Implement Steam Deck Podman deployment tooling for the merged containerized vpnkit runtime (OpenVPN + sing-box + vibe-vpn) and verify it over LAN/Tailscale SSH where safe.
- Scope: scripts, runbook, task package evidence, read-only and blocked deploy verification against Steam Deck aliases `deck` and `steamdeck-ts`.
- Boundaries: no VPS mutation, no committed/printed secrets, preserve existing Docker e2e path.
- Worktree / branch: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit` / `pi/steamdeck-podman-vpnkit`.

## Plan and slice structure
- Plan path: `docs/plans/2026-06-01-steamdeck-podman-vpnkit/plan.md`.
- Structure used: one implementation slice (`S1 Steam Deck Podman deploy/run/verify`) because the work had one dominant ownership boundary: Podman-over-SSH runtime deployment and evidence.
- Supporting discovery: `~/code/positions/scripts/steamdeck` patterns plus current vpnkit Docker runtime mapping.
- Acceptance audit: `docs/plans/2026-06-01-steamdeck-podman-vpnkit/reports/acceptance-auditor.md` accepted with limitations.

## Changed files
- `scripts/vpnkit-steamdeck-podman.sh` — executable Podman-over-SSH CLI with `check-ssh`, `resolve-remote-dir`, `sync`, `build`, `run`, `deploy`, `status`, `verify`, `logs`, `stop`, `cleanup`.
- `docs/STEAMDECK_PODMAN_VPNKIT.md` — runbook with prerequisites, LAN/Tailscale examples, runtime wiring, and verification checklist.
- `docs/plans/2026-06-01-steamdeck-podman-vpnkit/**` — plan, reports, audit, and verification evidence.

## Commits / push
- Branch pushed: `origin/pi/steamdeck-podman-vpnkit`.
- Commits integrated at root-report time:
  - `c946ab1 Add Steam Deck Podman vpnkit task plan`
  - `432b9db Add Steam Deck Podman vpnkit deployment tooling`
  - `a55e028 Update Steam Deck Podman report ref`
  - `1744a64 Fix Steam Deck remote dir expansion`
  - `ae9c671 Record remote dir fix report`
  - `71a3778 Add Steam Deck Podman verification report`
- Note: a later metadata-only commit may update this report file after this commit list is written; use `git log origin/main..origin/pi/steamdeck-podman-vpnkit` for the exact branch tip.

## Acceptance verification
- Scripts/runbook/evidence exist: passed.
  - Evidence: `scripts/vpnkit-steamdeck-podman.sh`, `docs/STEAMDECK_PODMAN_VPNKIT.md`, task package reports.
- Build/run/stop/logs/cleanup/status/verify actions: passed.
  - Evidence: script usage and action dispatch.
- Podman runtime wiring: passed at script/config level.
  - Evidence: `run` uses `--privileged`, `NET_ADMIN`, `NET_RAW`, `/dev/net/tun`, OpenVPN `1194/udp` mapping, sysctls, read-only config volumes, and writable state/log volumes.
- Secrets safe: passed.
  - Evidence: tracked context sent with `git archive`; rendered configs required from gitignored `secrets/vps/rendered`; logs are redacted; deploy stopped before transfer when rendered secrets were absent.
- Steam Deck live deployment: partial / blocked.
  - Evidence: Deck SSH/Podman/TUN checks passed, but deploy stopped with `missing required rendered input: secrets/vps/rendered/openvpn/server.conf` before remote sync/build/run.
- Local Docker e2e preservation: passed with limitation.
  - Evidence: `docker compose config` and `docker compose --profile test config` passed; full Docker e2e skipped because same gitignored rendered inputs were absent.

## Commands run and redacted evidence
Detailed evidence is in `verification/steamdeck-podman.md` and `verification/root-final.md`. Root-final checks run freshly:

- `bash -n scripts/vpnkit-steamdeck-podman.sh` — passed.
- `docker compose config` — passed.
- `docker compose --profile test config` — passed.
- `go test ./...` — passed.
- `scripts/vpnkit-steamdeck-podman.sh --ssh-target deck check-ssh` — passed: `steamdeck`, `podman version 5.3.2`, UID `1000`, `/dev/net/tun:present`.
- `scripts/vpnkit-steamdeck-podman.sh --ssh-target steamdeck-ts --ssh-option '-p 2222' check-ssh` — passed with same Podman/TUN evidence.
- `scripts/vpnkit-steamdeck-podman.sh --ssh-target deck resolve-remote-dir` — passed: `/home/deck/.local/state/vpnkit`.
- `ping -c 2 -W 2 192.168.50.13` — passed, 0% packet loss.
- `ping -c 2 -W 2 100.94.95.32` — passed, 0% packet loss.
- `scripts/vpnkit-steamdeck-podman.sh --ssh-target deck --lan-endpoint 192.168.50.13 deploy` — expected blocked: `missing required rendered input: secrets/vps/rendered/openvpn/server.conf`.

## Steam Deck deployment status
- SSH target discovery: succeeded.
  - LAN alias: `deck`.
  - Tailscale alias: `steamdeck-ts` with `--ssh-option '-p 2222'`.
- Deck readiness: succeeded for read-only checks; Podman 5.3.2 and `/dev/net/tun` are present.
- Container build/start: not reached. The script correctly refused to deploy without required gitignored rendered configs.
- OpenVPN/sing-box/vibe-vpn process health: not run because the container was not built/started.

## LAN and Tailscale results
- LAN: `192.168.50.13` reachable by ping and SSH alias `deck`; 0% packet loss in root verification.
- Tailscale: `100.94.95.32` reachable by ping and SSH alias `steamdeck-ts -p 2222`; 0% packet loss in root verification.
- OpenVPN client connectivity: not tested because live container deploy was blocked before build/run by missing rendered configs.

## System readiness and risks
- Runtime wiring is ready for operator-provided secrets and live deploy retry.
- Config/env/secrets remain the only blocker to full runtime proof: `secrets/vps/rendered/openvpn/server.conf`, `secrets/vps/rendered/sing-box/config.json`, `secrets/vps/rendered/vibe-vpn/config.yaml`, and `secrets/vps/rendered/vibe-vpn/sub_url` must exist locally.
- No VPS mutation was performed.
- Existing Docker e2e script was not changed.

## Final verdict
- Status: partial, accepted with explicit limitation.
- Done-state achieved: tracked Steam Deck Podman deployment tooling, runbook, SSH target discovery, local checks, Deck readiness checks, and LAN/Tailscale reachability.
- Blocker to full goal: missing gitignored rendered configs/secrets prevented actual Deck image build/start and inside-container health checks.
- Next step: render/provide the required local secret config tree, then rerun `scripts/vpnkit-steamdeck-podman.sh --ssh-target deck --lan-endpoint 192.168.50.13 deploy`, followed by `status`, `verify`, and OpenVPN client connectivity checks.
