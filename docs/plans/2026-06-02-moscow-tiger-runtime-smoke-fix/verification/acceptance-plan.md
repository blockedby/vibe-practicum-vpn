# Acceptance plan — Moscow tiger OpenVPN MTU/MSS cleanup/finalization

## Audit target
- Source fix: persist `tun-mtu 1400` + `mssfix 1360` in tracked OpenVPN render source.
- Public-safe docs/tests/evidence updates for the moscow-tiger MTU/MSS fix.
- Source-based deploy/render on `moscow-tiger`.
- Fresh baseline host Docker smoke and explicit 2ip smoke after source-based deploy.
- Public-safety / repo-check verification.

## Evidence to inspect
- `config/openvpn/server.tpl`
- `internal/config/openvpn_template_test.go`
- `docs/DOCKER_SETUP.md`
- `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/verification/runtime-smoke.md`
- `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/reports/slice-owner-runtime-diagnosis-fix.md`
- `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/final-report.md`
- `git status --short`
- local check output cited in the reports (`go test ./...`, `go test ./internal/config`, `bash -n scripts/*.sh`, render grep)

## Decision rules
- Accept only if source persistence, public-safe docs/tests, source-based live deploy, baseline smoke, 2ip smoke, and repo/public-safety checks are all evidenced or explicitly waived.
- If live deploy/smokes are blocked by endpoint/access issues, mark the task blocked/not ready and name the exact gate.
