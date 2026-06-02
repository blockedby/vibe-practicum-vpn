# Acceptance plan: RU direct sing-box Docker lab regression

## Audit target
- Confirm final readiness for the RU-direct sing-box change and Docker lab DNS/HTTPS regression.

## Acceptance criteria
1. RU direct route intact in sing-box template and regression coverage.
2. OpenVPN client gets `10.89.0.2/24` in local Docker lab.
3. DNS over tunnel returns `NOERROR`.
4. HTTPS over tunnel returns `200`.
5. Literal-IP HTTPS over tunnel returns `200`.
6. `go test ./...` passes.
7. `git diff --check` passes.
8. No VPS touched.
9. No secrets/logs/generated artifacts committed.
10. Alternate Docker lab host port is documented because local UDP `1194` is occupied.

## Evidence sources to inspect
- `docs/plans/2026-06-02-ru-direct-singbox/verification/local.md`
- `docs/plans/2026-06-02-ru-direct-singbox/reports/slice-owner-docker-lab-debug.md`
- `docs/plans/2026-06-02-ru-direct-singbox/final-report.md`
- `config/sing-box/config.json.template`
- `internal/singbox/singbox_test.go`
- `docker/vpnkit/entrypoint.sh`

## Audit decision focus
- Accept only if all criteria are covered by fresh evidence or explicit waiver.
- Record any stale, missing, or contradictory evidence as a blocker or limitation.
