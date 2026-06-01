## Task
- Mission: Add and verify Steam Deck Podman deploy/run support for containerized vpnkit.
- Target: `scripts/vpnkit-steamdeck-podman.sh`, `docs/STEAMDECK_PODMAN_VPNKIT.md`, task package evidence.
- Boundaries: no VPS mutation; no committed/printed secrets; preserve Docker e2e semantics; no merge to main.
- Done when: scripts/docs/evidence exist, remote Deck deploy is attempted when safe, and blockers are explicit.
- Expected evidence: local checks, remote SSH/Podman checks, deploy attempt, connectivity checks, secret scan.

## Context
- Slice: S1 Steam Deck Podman deploy/run/verify; stayed whole.
- Task package: `docs/plans/2026-06-01-steamdeck-podman-vpnkit`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit`
- Branch: `pi/steamdeck-podman-vpnkit`

## Spec compliance
- Scripts/runbook/evidence: done. Evidence: new `scripts/vpnkit-steamdeck-podman.sh`, `docs/STEAMDECK_PODMAN_VPNKIT.md`, `verification/steamdeck-podman.md`.
- build/run/stop/logs/cleanup/status/verify/deploy actions: done in compact CLI.
- Podman privilege/TUN/port/volume wiring: done in `run` action (`--privileged`, NET_ADMIN/NET_RAW, `/dev/net/tun`, sysctls, UDP port, config/state/log volumes).
- Secrets remain gitignored/not printed: done by git-archive tracked context plus tarred rendered config transfer; deploy blocked before transfer because rendered config tree absent.
- Live Steam Deck verification: partial. Read-only SSH/Podman checks passed for LAN and Tailscale aliases; container deploy blocked by absent local rendered secrets.

## Acceptance verification
- AC1-AC5: passed via tracked script/runbook and evidence.
- AC6-AC8: partial. Deck reachable; Podman/TUN present; host LAN/Tailscale ping passed; live build/start/process/client checks blocked by missing rendered inputs.
- AC9: local checks passed; Docker e2e skipped due absent required secret/config prerequisites.
- AC10: pending commit/push at report time.

## System readiness
- Config/env/secrets: blocked for live deploy until operator provides/renders `secrets/vps/rendered/*` locally.
- Permissions/access: SSH to `deck` and `steamdeck-ts -p 2222` works; `/dev/net/tun` present; Podman version 5.3.2.
- Runtime/deployment wiring: implemented; not fully runtime-proven because deploy did not reach build/run.

## Verification run
- `bash -n scripts/vpnkit-steamdeck-podman.sh`: passed.
- `docker compose config`: passed.
- `docker compose --profile test config`: passed.
- `go test ./...`: passed.
- `scripts/vpnkit-steamdeck-podman.sh --ssh-target deck check-ssh`: passed (`steamdeck`, Podman 5.3.2, UID 1000, `/dev/net/tun:present`).
- `scripts/vpnkit-steamdeck-podman.sh --ssh-target steamdeck-ts --ssh-option '-p 2222' check-ssh`: passed.
- `scripts/vpnkit-steamdeck-podman.sh --ssh-target deck --lan-endpoint 192.168.50.13 deploy`: blocked locally by `missing required rendered input: secrets/vps/rendered/openvpn/server.conf`.
- `ping 192.168.50.13` and `ping 100.94.95.32`: passed, 0% packet loss.
- Docker e2e: skipped; rendered `secrets/vps` inputs absent.

## Issues
### Issue U-01: Live container deploy blocked by missing rendered secrets
- Description: Required gitignored rendered config tree is absent locally, so script stopped before remote mutation/build/run.
- Evidence: deploy output: `missing required rendered input: secrets/vps/rendered/openvpn/server.conf`.
- Why unresolved: secret material is operator-bound and cannot be fabricated or printed/committed.
- Needed next: operator runs/authorizes secret render, then rerun `deploy`, `status`, `verify`, and OpenVPN client checks.

## Side findings
- None.

## Verdict
- Status: partial.
- Goal state: deployment support implemented and read-only Deck readiness proven; live container deploy not completed due missing local rendered secret/config inputs.
- Final readiness: ready except explicit limitation U-01.
- Summary: The branch now has safe Podman-over-SSH deploy tooling and runbook; Steam Deck is reachable with Podman/TUN, but real runtime verification requires operator-provided rendered configs.

## Next-agent brief
- Objective: complete live deploy/runtime verification after rendered configs exist.
- Target: `scripts/vpnkit-steamdeck-podman.sh deploy/status/verify/logs` against `deck` or `steamdeck-ts`.
- Boundaries: do not print/commit secrets; do not mutate VPS.
- Verification target: `podman ps/logs/exec`, `sing-box check`, `vibe-vpn doctor/test/apply` if feasible, LAN/Tailscale/OpenVPN client checks.

## Commit / push update
- Commit: `432b9db Add Steam Deck Podman vpnkit deployment tooling`
- Pushed branch: `origin/pi/steamdeck-podman-vpnkit`

## Follow-up integration fix: remote-dir normalization
- Status: resolved current-goal blocker R-02.
- Changed: `scripts/vpnkit-steamdeck-podman.sh` now keeps the default remote dir as literal `~/.local/state/vpnkit`, resolves `~`/`~/...` over SSH using the Deck user's `$HOME` before `sync`, `build`, `run`, or `deploy`, preserves absolute remote paths, and rejects unsupported relative paths. Added read-only `resolve-remote-dir` check action.
- Docs: `docs/STEAMDECK_PODMAN_VPNKIT.md` clarifies `~` resolution and absolute path behavior.
- Verification: see `verification/steamdeck-podman.md` follow-up section. `bash -n` passed; `check-ssh` still passed; read-only normalization checks resolved default to `/home/deck/.local/state/vpnkit`, `~` to `/home/deck`, absolute `/tmp/vpnkit-test` unchanged, and relative path rejected.
