## Task package
- Task name: Sing-box test backend by default
- Task package: docs/plans/2026-05-28-singbox-test-backend
- Report path: docs/plans/2026-05-28-singbox-test-backend/reports/acceptance-auditor.md
- Acceptance plan path: docs/plans/2026-05-28-singbox-test-backend/verification/acceptance-plan.md

## Acceptance verdict
- Status: accepted
- Summary: Evidence supports sing-box as the default isolated benchmark backend under `runtime: singbox`; legacy xray remains for explicit runtime, local verification passed, and the branch is pushed with PR #8 open.

## Acceptance coverage
- AC1: default `runtime: singbox` tests/pick/daemon scheduled tests use isolated temp sing-box on `test_socks` and do not mutate production config/service
  - Evidence present: `cmd/vibe-vpn/main.go` dispatch (`tempBenchmarkBackend`, `runScheduledTest`, `testOne`) plus `cmd/vibe-vpn/cli_test.go::TestTempBenchmarkBackendDefaultsToSingBoxAndDoesNotUseProductionConfig`
  - Result: passed
  - Gap: none
- AC2: explicit `runtime: xray` remains supported for legacy isolated temp xray benchmarks
  - Evidence present: `cmd/vibe-vpn/cli_test.go::TestTempBenchmarkBackendKeepsExplicitXrayRuntime`
  - Result: passed
  - Gap: none
- AC3: CLI wording/help/docs/examples/tests say sing-box is the default benchmark backend; xray is legacy-only when runtime is xray
  - Evidence present: `cmd/vibe-vpn/main.go` help strings, `cmd/vibe-vpn/cli_test.go::TestCobraHelpMentionsSafetyAndFilters`, `README.md`, `examples/vibe-vpn-config.yaml`, `examples/vibe-vpn-smoke-config.yaml`
  - Result: passed
  - Gap: none
- AC4: stale temp cleanup/prune handles sing-box temp artifacts and preserves xray cleanup
  - Evidence present: `cleanupStaleTestSingBox`, `cleanupStaleTestXray`, `cleanupStaleTestBackends`, `cmdPrune`, `pruneTempFiles` in `cmd/vibe-vpn/main.go`; verified by full `go test ./...`
  - Result: passed
  - Gap: no dedicated cleanup-only test, but full Go test suite passed and code path is explicit
- AC5: fresh verification commands pass
  - Evidence present: `go test ./...`, `go vet ./...`, `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`, `./scripts/validate-vibe-vpn-service-assets.sh`
  - Result: passed
  - Gap: none
- AC6: branch is pushed and PR is open; no VPS deployment performed
  - Evidence present: `git ls-remote --heads origin pi/singbox-test-backend` shows pushed head `f8c2ece...`; `gh pr view 8` shows OPEN PR #8; no VPS commands were run in this audit
  - Result: passed
  - Gap: remote CI checks reported no statuses on the PR branch

## System readiness coverage
- Routes / registration: not relevant
- Services / APIs: covered where relevant; daemon/scheduled test path reuses `runTest`/`testOne` and stays local
- Config / env / secrets: covered; examples/docs updated, no new secrets or env vars added
- Permissions / access: not relevant beyond existing temp-file/process behavior
- Database / migrations: not relevant
- Frontend-backend integration: not relevant
- Runtime / deployment wiring: covered; runtime dispatch and cleanup updated, no VPS deploy performed
- Docker / containers: not relevant

## Check freshness
- Targeted checks: fresh
- Full local checks: fresh
- Remote checks / CI: not checked; `gh pr checks 8` reported no checks on `pi/singbox-test-backend`

## Required before done
- None for acceptance; optional follow-up is only to add/enable PR CI if the repo expects it.

## Files written
- docs/plans/2026-05-28-singbox-test-backend/verification/acceptance-plan.md: created
- docs/plans/2026-05-28-singbox-test-backend/reports/acceptance-auditor.md: created
