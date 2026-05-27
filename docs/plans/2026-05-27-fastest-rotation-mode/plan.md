# Plan: configurable fastest-rotation service mode

## Intake / scope

Goal: add an alternative configurable daemon service mode where scheduled node tests (default interval remains `test.interval: 30m`) can apply the fastest working non-excluded node after a successful scheduled test, while preserving the current default failover-only daemon behavior.

In scope:
- Config key for service mode, defaulting to failover-only; invalid mode rejected by validation.
- Scheduled/startup test orchestration: default mode benchmarks only; fastest-rotation mode runs production health probe before an apply decision, then applies fastest OK non-excluded result even if health is OK, unless already current.
- Preserve confirmed health failure failover behavior and manual `pick`/`apply` semantics.
- Unit tests, docs/examples/script validation updates, local verification, local commit.

Out of scope / safety boundaries:
- No deploy/upload/SSH/SCP/systemd/xray restarts or VPS mutation.
- No secrets, subscription URLs, VLESS links, tokens, generated keys/certs in docs/reports.
- Do not rebase/push/merge unless separately requested.

Done state:
- Acceptance matrix and verification evidence written under this package.
- `go test ./...`, `go vet ./...`, `go build ./cmd/vibe-vpn`, service asset validation syntax/run checks pass or exact blockers recorded.
- Coherent local commit exists and hash is reported.

Blocking unknowns: none known; implementation should follow current failover-service branch patterns.

## Repo orientation / reuse discovery

- Prior failover package: `docs/plans/2026-05-27-vpn-failover-service/`.
- Config: `internal/config/config.go`, tests in `internal/config/config_test.go`.
- Daemon scheduler: `internal/service/service.go`, tests in `internal/service/service_test.go`.
- Failover selection/current semantics: `internal/failover/failover.go` has `LoadResults`, `Candidates`, private `same`; tests in `internal/failover/failover_test.go`.
- Existing fastest OK filtering/sorting pattern: `picker.BestFiltered` and/or failover `Candidates`.
- Current node state: `state.LoadCurrent`.
- Health probe machinery: `health.NewRunner(c.ProductionSocks, c.Health.RequiredURLs, c.Health.DiagnosticURLs, c.Health.ProbeTimeout.Duration)` / `health.Runner`.
- Runtime wiring may be in `cmd/vibe-vpn/main.go` and `cmd/vibe-vpn/daemon_test.go`.
- Docs/examples: `docs/FAILOVER_SERVICE_RUNBOOK.md`, `examples/vibe-vpn-config.yaml`, smoke config if present, `scripts/validate-vibe-vpn-service-assets.sh`.

## Missing pieces

- Service mode enum/constants/default/validation and docs naming.
- Reusable helper for fastest working result and current-node comparison if existing private helpers are insufficient.
- Scheduler hook for post-successful-test rotation only in fastest-rotation mode; no apply after failed scheduled test or restored old results.
- Unit tests for default no-apply, fastest apply, already-current no-op, health probe invocation, scheduled test failure no-apply, invalid config mode.
- Docs/examples/script updates.

## Plan tasks / dependency graph

### Task 1: Config and scheduler fastest-rotation behavior

Goal:
- Make daemon service mode configurable and implement post-successful scheduled-test fastest rotation without changing default failover-only behavior.

Boundary:
- System area: Go config/service/failover helper/runtime wiring.
- Primary verification: focused Go unit tests plus full Go checks.

Existing pattern / reuse:
- `internal/config/config.go` defaults/validation style.
- `internal/service/service.go` scheduler and health runner construction.
- `internal/failover/failover.go` result loading, candidate filtering, current comparison semantics.
- `state.LoadCurrent`, `picker.NodeResult`, existing apply adapter wiring.

Missing change:
- Add config mode default and validation.
- Add scheduled rotation adapter/helper using latest successful results; load current; skip if fastest already current; probe health before apply using required+diagnostic health URLs; apply fastest even when health is OK.
- Ensure scheduled test failure path logs and never applies.

Scope / likely files:
- `internal/config/config.go`, `internal/config/config_test.go`
- `internal/service/service.go`, `internal/service/service_test.go`
- `internal/failover/failover.go`, `internal/failover/failover_test.go` if helper reuse is cheapest
- `cmd/vibe-vpn/main.go`, `cmd/vibe-vpn/daemon_test.go` if production adapter wiring needs changes

Acceptance criteria:
- AC1, AC2, AC3 Go behavior covered by tests.
- Default service mode remains failover-only; invalid mode rejected.
- Fastest-rotation runs production health probe before apply and skips already-current fastest.
- Scheduled test error never triggers apply from old results.

Test plan:
- Positive: config default; fastest mode scheduled success probes and applies fastest OK non-excluded.
- Negative: invalid mode validation; default mode does not apply; scheduled test error no apply.
- Edge: fastest equals current no apply; failover manager confirmed-failure behavior unchanged.

Dependencies:
- Depends on: none.
- Blocks: Task 2 docs; Task 3 final verification.
- Executor: `aad-implementer`.
- Report path: `docs/plans/2026-05-27-fastest-rotation-mode/reports/aad-implementer-fastest-rotation.md`.

### Task 2: Docs/examples/service asset validation

Goal:
- Document the mode/default and provide safe example configuration for fastest-rotation.

Boundary:
- System area: docs/examples/scripts.
- Primary verification: script validation and syntax checks plus full docs diff review.

Scope / likely files:
- `docs/FAILOVER_SERVICE_RUNBOOK.md`
- `examples/vibe-vpn-config.yaml`
- smoke example if present
- `scripts/validate-vibe-vpn-service-assets.sh` if it checks config/runbook assets

Acceptance criteria:
- AC4 satisfied; docs state default failover-only and fastest-rotation behavior, including health probe before apply and skip-current behavior.
- No secrets or real subscription/VLESS data.

Dependencies:
- Depends on: Task 1 mode names/API.
- Executor: same `aad-implementer` after Task 1 or owner if tiny.

### Task 3: Final verification/report/commit

Goal:
- Prove acceptance, record evidence, and commit coherent local changes.

Verification commands:
- `go test ./...`
- `go vet ./...`
- `go build ./cmd/vibe-vpn`
- `bash -n scripts/validate-vibe-vpn-service-assets.sh`
- `./scripts/validate-vibe-vpn-service-assets.sh`
- install script syntax if relevant/found

Acceptance criteria:
- AC5/AC6 satisfied with evidence in `verification/local.md` and owner/implementer reports.
- Local commit hash recorded.

Dependencies:
- Depends on: Tasks 1-2.
- Executor: slice owner after implementer report; may delegate audit if evidence is ambiguous.

## Execution ledger

- 2026-05-27: Task package created on `feature/fastest-rotation-mode`; implementation kept as one coherent task because the slice has one service-mode verification story.
- 2026-05-27: Nested `aad-implementer` dispatch was blocked by subagent depth; slice owner implemented directly inside requested checkout.
- 2026-05-27: Local verification passed: `go test ./...`, `go vet ./...`, `go build ./cmd/vibe-vpn`, `bash -n scripts/validate-vibe-vpn-service-assets.sh`, `./scripts/validate-vibe-vpn-service-assets.sh`, `bash -n scripts/install-vibe-vpn-service.sh`.
- 2026-05-27: Local commit created: `2834e3d` (`Add fastest rotation service mode`).
