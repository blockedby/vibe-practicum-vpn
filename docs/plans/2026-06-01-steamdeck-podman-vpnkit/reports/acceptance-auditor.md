## Task package
- Task name: Steam Deck Podman vpnkit deployment
- Task package: docs/plans/2026-06-01-steamdeck-podman-vpnkit
- Report path: docs/plans/2026-06-01-steamdeck-podman-vpnkit/reports/acceptance-auditor.md
- Acceptance plan path: docs/plans/2026-06-01-steamdeck-podman-vpnkit/verification/acceptance-plan.md

## Acceptance verdict
- Status: accepted with limitations
- Summary: The branch has safe Podman-over-SSH deploy tooling, documented runtime wiring, and fresh local/remote readiness evidence; the only blocker to full live verification is missing operator-rendered configs, so deploy/build/run were intentionally stopped before remote mutation.

## Acceptance coverage
- AC1: Steam Deck Podman scripts/runbook/evidence exist and are safe/idempotent enough.
  - Evidence present: `scripts/vpnkit-steamdeck-podman.sh`, `docs/STEAMDECK_PODMAN_VPNKIT.md`, `verification/steamdeck-podman.md`, `verification/root-final.md`
  - Result: passed
  - Gap: none
- AC2: Runtime wiring includes OpenVPN + sing-box + vibe-vpn and Podman privileges/TUN/port/volumes.
  - Evidence present: `docker/vpnkit/Dockerfile`, `docker-compose.yml`, `scripts/vpnkit-steamdeck-podman.sh`, `docs/STEAMDECK_PODMAN_VPNKIT.md`, `verification/root-final.md`
  - Result: passed
  - Gap: none
- AC3: Real secrets are not committed/printed; missing rendered configs blocker is handled correctly.
  - Evidence present: `.gitignore`, redaction logic in `scripts/vpnkit-steamdeck-podman.sh`, blocked deploy in `verification/steamdeck-podman.md` and `verification/root-final.md`
  - Result: passed
  - Gap: none
- AC4: Steam Deck SSH/readiness checks, LAN/Tailscale connectivity, local checks, and deploy attempt evidence are sufficient.
  - Evidence present: `check-ssh` on `deck` and `steamdeck-ts`, `ping 192.168.50.13`, `ping 100.94.95.32`, `bash -n`, `docker compose config`, `docker compose --profile test config`, `go test ./...`, deploy attempt in `verification/root-final.md`
  - Result: partial
  - Gap: live build/run/process health did not execute because the required rendered config tree is absent locally
- AC5: Docker e2e is preserved or any skip is justified.
  - Evidence present: `scripts/vpnkit-vibe-vpn-e2e.sh` unchanged in source scope; `docker compose config`, `docker compose --profile test config`, and the explicit skip in `verification/steamdeck-podman.md` / `verification/root-final.md`
  - Result: passed with limitation
  - Gap: full e2e was skipped because rendered `secrets/vps` inputs were unavailable

## System readiness coverage
- Routes / registration: not relevant
- Services / APIs: covered
- Config / env / secrets: blocked for full live verification until rendered `secrets/vps/rendered/*` inputs are present locally; secret handling itself is documented and redacted
- Docker / containers: covered
- Permissions / access: covered
- Database / migrations: not relevant
- Frontend-backend integration: not relevant
- Runtime / deployment wiring: partially covered; wiring is documented and composed, but live container execution was not reached

## Check freshness
- Targeted checks: fresh
- Full local checks: fresh
- Remote checks / CI: not checked (no PR/CI evidence provided)

## Required before done
- Provide/render the required gitignored config tree locally (`secrets/vps/rendered/openvpn/server.conf`, `secrets/vps/rendered/sing-box/config.json`, `secrets/vps/rendered/vibe-vpn/config.yaml`, `secrets/vps/rendered/vibe-vpn/sub_url`) and rerun `deploy`, `status`, and `verify` if full live runtime proof is required.

## Files written
- docs/plans/2026-06-01-steamdeck-podman-vpnkit/verification/acceptance-plan.md: created
- docs/plans/2026-06-01-steamdeck-podman-vpnkit/reports/acceptance-auditor.md: created
