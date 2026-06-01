# Root run: Steam Deck Podman vpnkit deployment

## Task
- Mission: Implement Steam Deck Podman deployment tooling for the merged containerized vpnkit runtime (OpenVPN + sing-box + vibe-vpn) and verify it over LAN/Tailscale SSH where safe.
- Scope: scripts, runbook, task package evidence, live Podman deploy verification against Steam Deck aliases `deck` and `steamdeck-ts`, plus LAN/Tailscale OpenVPN client e2e from this host.
- Boundaries: no VPS mutation, no committed/printed secrets, preserve existing Docker e2e path.
- Worktree / branch: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit` / `pi/steamdeck-podman-vpnkit`.

## Plan and slice structure
- Plan path: `docs/plans/2026-06-01-steamdeck-podman-vpnkit/plan.md`.
- Structure used: one implementation slice (`S1 Steam Deck Podman deploy/run/verify`) because the work had one dominant ownership boundary: Podman-over-SSH runtime deployment and evidence.
- Supporting discovery: `~/code/positions/scripts/steamdeck` patterns plus current vpnkit Docker runtime mapping.
- Initial acceptance audit: `docs/plans/2026-06-01-steamdeck-podman-vpnkit/reports/acceptance-auditor.md` accepted the tooling with limitations while rendered secrets were absent. After rendered secrets were copied into this worktree, live deploy/client verification passed; see `verification/live-deploy-2026-06-01.md`.

## Changed files
- `scripts/vpnkit-steamdeck-podman.sh` — executable Podman-over-SSH CLI with `check-ssh`, `resolve-remote-dir`, `sync`, `build`, `run`, `deploy`, `status`, `verify`, `logs`, `stop`, `cleanup`, and optional `--log-file` redacted file logging.
- `scripts/vpnkit-steamdeck-client-test.sh` — host-side OpenVPN client e2e helper for LAN/Tailscale Deck endpoints.
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
- Steam Deck live deployment: passed.
  - Evidence: `verification/live-deploy-2026-06-01.md`; Podman built `localhost/vpnkit:steamdeck`, container `vpnkit` started, OpenVPN/sing-box/vibe-vpn verified.
- Host-to-Deck LAN OpenVPN e2e: passed.
  - Evidence: client helper connected to `192.168.50.13:1194`, received `10.89.0.2`, DNS/HTTPS/literal-IP HTTPS passed.
- Host-to-Deck Tailscale OpenVPN e2e: passed.
  - Evidence: client helper connected to `100.94.95.32:1194`, received `10.89.0.2`, DNS/HTTPS/literal-IP HTTPS passed.
- Deck-side `vibe-vpn test` and `apply best`: passed.
  - Evidence: real subscription test found one OK node, `apply best` wrote backup and supervisor restarted sing-box; post-apply LAN/Tailscale client e2e passed.
- Local Docker e2e preservation: passed at config/static level.
  - Evidence: `docker compose config` and `docker compose --profile test config` passed; Steam Deck client e2e used the same OpenVPN test container.

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
- `scripts/vpnkit-steamdeck-podman.sh --ssh-target deck --lan-endpoint 192.168.50.13 deploy` — initially blocked until rendered secrets were copied into the worktree; after that, live deploy passed.
- `scripts/vpnkit-steamdeck-client-test.sh --endpoint 192.168.50.13` — passed LAN client e2e.
- `scripts/vpnkit-steamdeck-client-test.sh --endpoint 100.94.95.32` — passed Tailscale client e2e.
- Deck-side `vibe-vpn test` + `vibe-vpn apply best` + post-apply client checks — passed.

## Steam Deck deployment status
- SSH target discovery: succeeded.
  - LAN alias: `deck`.
  - Tailscale alias: `steamdeck-ts` with `--ssh-option '-p 2222'`.
- Deck readiness: succeeded for read-only checks; Podman 5.3.2 and `/dev/net/tun` are present.
- Container build/start: passed with Podman on Deck.
- OpenVPN/sing-box/vibe-vpn process health: passed.

## LAN and Tailscale results
- LAN: `192.168.50.13` reachable by ping and SSH alias `deck`; 0% packet loss in root verification.
- Tailscale: `100.94.95.32` reachable by ping and SSH alias `steamdeck-ts -p 2222`; 0% packet loss in root verification.
- OpenVPN client connectivity: passed over both LAN and Tailscale endpoints, including DNS/HTTPS/literal-IP HTTPS through the Deck-hosted OpenVPN -> sing-box -> VLESS path.

## System readiness and risks
- Runtime wiring is ready and live-proven with real gitignored rendered secrets.
- Required local rendered inputs are still not committed; future deploy retries must provide/render `secrets/vps/rendered/openvpn/server.conf`, `secrets/vps/rendered/sing-box/config.json`, `secrets/vps/rendered/vibe-vpn/config.yaml`, and `secrets/vps/rendered/vibe-vpn/sub_url` locally.
- No VPS mutation was performed.
- Existing Docker e2e script was not changed.

## Final verdict
- Status: success.
- Done-state achieved: tracked Steam Deck Podman deployment tooling, runbook, SSH target discovery, live Podman build/start, Deck health checks, Deck-side `vibe-vpn test/apply`, LAN OpenVPN client e2e, Tailscale OpenVPN client e2e, and post-apply LAN/Tailscale e2e.
- The `vpnkit` container is intentionally left running on the Steam Deck for follow-up use.
