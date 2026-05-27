# Plan: default service mode fastest-rotation

## Task intake
Goal: change the service default from `failover-only` to `fastest-rotation`, meaning startup/scheduled successful tests automatically switch to the fastest OK non-excluded node unless already current. Keep `failover-only` as an explicit supported opt-out mode.

In scope: code defaults, config examples, README/runbook/docs, validation scripts/tests that assert the default or example mode, local verification, commit and push to PR #6 branch.

Out of scope: no PR merge, no VPS deploy, no ssh/scp/systemctl production mutation.

Done-state: branch pushed with coherent commit; fresh `go test ./...`, `go vet ./...`, `go build`, and service asset validation script pass; report includes commit hash/files/tests.

Blocking unknowns: none.

## Repo orientation
- Repo root has no `AGENTS.md`; no child `AGENTS.md` found. README read.
- Current worktree/branch: `.worktrees/docs-failover-service-plan`, branch `docs/failover-service-plan`, PR #6 open.
- Service mode constants/defaults: `internal/config/config.go`.
- Config tests: `internal/config/config_test.go`.
- Scheduler behavior: `internal/service/service.go`; existing fastest rotation behavior is already implemented and gated by `service.mode`.
- Examples/docs/validation likely to update: `examples/vibe-vpn-config.yaml`, `examples/vibe-vpn-smoke-config.yaml`, `README.md`, `docs/FAILOVER_SERVICE_RUNBOOK.md`, `scripts/validate-vibe-vpn-service-assets.sh`.

## Reuse discovery
- Reuse existing `config.ServiceModeFastestRotation` and scheduled-rotation hook in `service.runTest`.
- Reuse existing validation that accepts both `failover-only` and `fastest-rotation`; only default mode changes.
- Follow existing docs wording for fastest-rotation behavior: health probe before apply, skip already current, no apply after failed scheduled test.

## Missing pieces
- `config.Default().Service.Mode` must become `ServiceModeFastestRotation`; blank `service.mode` validation/defaulting should align if config omitted.
- Tests/docs/examples/static validation must stop treating `failover-only` as the default example.
- Docs must still explain explicit `failover-only` opt-out behavior.

## Plan tasks
### Task 1: Switch default mode and aligned docs/tests
Goal: make fastest-rotation the default service mode while preserving explicit failover-only support.
Boundary: config defaults/tests plus docs/examples/validation only.
Acceptance criteria:
- Default config and omitted/blank `service.mode` resolve to `fastest-rotation`.
- Examples and README/runbook identify fastest-rotation as default and failover-only as explicit opt-out.
- Validation script checks the new expected example defaults.
- No VPS/deploy commands run.
Test plan:
- `go test ./...`
- `go vet ./...`
- `go build ./cmd/vibe-vpn`
- `./scripts/validate-vibe-vpn-service-assets.sh`
Dependencies: none.
Executor: aad-implementer.
Report: `docs/plans/2026-05-28-default-fastest-rotation/reports/aad-implementer-default-fastest-rotation.md`.

## Dependency graph
Single coherent task; no child slices. Owner will run/read final verification after implementer report, commit/push if needed, and report.

## Execution ledger
- 2026-05-28: Plan created. Pre-dispatch gate passed: goal, scope, repo orientation, reuse targets, missing pieces, acceptance/test plan, and dependency graph are recorded.
- 2026-05-28: aad-implementer completed code/docs/examples/validation updates. Local checks passed: `go test ./...`, `go vet ./...`, `go build ./cmd/vibe-vpn`, `./scripts/validate-vibe-vpn-service-assets.sh`. Evidence: `verification/local.md` and `reports/aad-implementer-default-fastest-rotation.md`.
- 2026-05-28: Implementer completed code/docs/tests and committed `ccf4a03e7367a9ee40a4c2ada190840fd118a3e1`; evidence package committed as `09113ee`.
- 2026-05-28: Slice owner ran fresh final verification; `go test ./...`, `go vet ./...`, `go build ./cmd/vibe-vpn`, and `./scripts/validate-vibe-vpn-service-assets.sh` passed. Evidence: `verification/slice-owner-final-local.md`.
