## Task package
- Task name: RU direct sing-box routing
- Task package: `docs/plans/2026-06-02-ru-direct-singbox/`
- Report path: `docs/plans/2026-06-02-ru-direct-singbox/reports/acceptance-auditor.md`
- Acceptance plan path: `docs/plans/2026-06-02-ru-direct-singbox/verification/acceptance-plan.md`

## Acceptance verdict
- Status: accepted
- Summary: Fresh local evidence covers RU direct routing, Docker lab DNS/HTTPS/literal-IP success, `go test ./...`, `git diff --check`, and the host-1194 alternate-port note; no blocker remains in the audited scope.

## Acceptance coverage
- AC1: RU direct route intact
  - Evidence present: `config/sing-box/config.json.template`, `internal/singbox/singbox_test.go`, `docs/plans/2026-06-02-ru-direct-singbox/verification/local.md`
  - Result: passed
  - Gap: none
- AC2: OpenVPN client gets `10.89.0.2/24`
  - Evidence present: fresh Docker compose client test recorded in `verification/local.md` and `slice-owner-docker-lab-debug.md`
  - Result: passed
  - Gap: none
- AC3: DNS returns `NOERROR`
  - Evidence present: same client test; `dig @8.8.8.8 example.com` returned `status: NOERROR`
  - Result: passed
  - Gap: none
- AC4: HTTPS returns `200`
  - Evidence present: same client test; `https-test http_code=200`
  - Result: passed
  - Gap: none
- AC5: Literal-IP HTTPS returns `200`
  - Evidence present: same client test; `literal-ip-test http_code=200`
  - Result: passed
  - Gap: none
- AC6: `go test ./...` passes
  - Evidence present: `verification/local.md`, `slice-owner-docker-lab-debug.md`, `final-report.md`
  - Result: passed
  - Gap: none
- AC7: `git diff --check` passes
  - Evidence present: `verification/local.md`, `slice-owner-docker-lab-debug.md`, `final-report.md`
  - Result: passed
  - Gap: none
- AC8: No VPS touched
  - Evidence present: reports explicitly state no VPS/SSH/systemctl commands were run; audit scope is local-only
  - Result: passed
  - Gap: none
- AC9: No secrets/logs/generated artifacts committed
  - Evidence present: `git status --short --branch` clean; reports state copied `secrets/` was removed after verification and no generated artifacts were committed
  - Result: passed
  - Gap: none
- AC10: Alternate Docker lab port documented due host `1194` conflict
  - Evidence present: `verification/local.md` and `slice-owner-docker-lab-debug.md` document `VPNKIT_OPENVPN_PORT=1196` because host UDP `1194` was occupied
  - Result: passed
  - Gap: none

## System readiness coverage
- Routes / registration: covered; RU direct rule-set routes and preserved DNS hijack/final routing are tested.
- Services / APIs: not relevant.
- Config / env / secrets: covered; local lab env flags are documented, and copied secrets were removed after use.
- Docker / containers: covered; compose lab start, runtime process check, and alternate host port were verified.
- Permissions / access: covered enough for this scope; local Docker/TUN runtime worked.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: covered; `docker/vpnkit/entrypoint.sh` now waits for sing-box readiness before OpenVPN starts.

## Check freshness
- Targeted checks: fresh
- Full local checks: fresh
- Remote checks / CI: not available before push

## Required before done
- None for local acceptance. If the branch is pushed, CI can be checked separately; it is not required to accept this local slice.

## Files written
- `docs/plans/2026-06-02-ru-direct-singbox/verification/acceptance-plan.md`: created
- `docs/plans/2026-06-02-ru-direct-singbox/reports/acceptance-auditor.md`: created
