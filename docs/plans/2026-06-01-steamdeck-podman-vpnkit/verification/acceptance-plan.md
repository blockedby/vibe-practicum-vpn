# Acceptance plan: Steam Deck Podman vpnkit deployment

## Acceptance criteria to verify
1. Steam Deck Podman scripts/runbook/evidence exist and are safe/idempotent enough.
2. Runtime wiring includes OpenVPN + sing-box + vibe-vpn and Podman privileges/TUN/port/volumes.
3. Real secrets are not committed/printed; missing rendered configs blocker is handled correctly.
4. Steam Deck SSH/readiness checks, LAN/Tailscale connectivity, local checks, and deploy-attempt evidence are sufficient.
5. Docker e2e is preserved or any skip is justified.
6. Final verdict: full / partial / blocked, with blockers listed.

## Evidence map
- Local verification: `verification/steamdeck-podman.md`
- Root verification summary: `verification/root-final.md`
- Task implementation report: `reports/slice-steamdeck-podman.md`
- Runbook: `docs/STEAMDECK_PODMAN_VPNKIT.md`
- Script: `scripts/vpnkit-steamdeck-podman.sh`
- Docker e2e script: `scripts/vpnkit-vibe-vpn-e2e.sh`
- Compose/runtime wiring: `docker-compose.yml`, `docker/vpnkit/Dockerfile`
- Secret ignore rules: `.gitignore`

## Fresh checks expected for acceptance
- `bash -n scripts/vpnkit-steamdeck-podman.sh`
- `docker compose config`
- `docker compose --profile test config`
- `go test ./...`
- `scripts/vpnkit-steamdeck-podman.sh --ssh-target deck check-ssh`
- `scripts/vpnkit-steamdeck-podman.sh --ssh-target steamdeck-ts --ssh-option '-p 2222' check-ssh`
- `ping 192.168.50.13`
- `ping 100.94.95.32`
- `scripts/vpnkit-steamdeck-podman.sh --ssh-target deck --lan-endpoint 192.168.50.13 deploy` (expected to stop if rendered secrets are absent)
- Secret-safety review of tracked diffs / log output
- Docker e2e skip justification if rendered secrets are unavailable

## Current audit stance
- The work appears partially accepted on paper: scripts/docs and read-only Deck readiness are evidenced, but live deploy/build/run verification is still blocked by missing gitignored rendered configs.
- Acceptance decision will hinge on whether the secret/config blocker is treated as an explicit limitation rather than unresolved implementation work.
