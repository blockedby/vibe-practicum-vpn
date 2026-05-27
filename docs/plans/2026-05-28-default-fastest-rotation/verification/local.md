# Local verification: default fastest-rotation

Date: 2026-05-28
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/docs-failover-service-plan`
Branch: `docs/failover-service-plan`

## Red/green evidence

- RED: `go test ./internal/config` failed before production config changes. Failures showed `Default()` and omitted `service.mode` returned `failover-only`, and blank `service.mode` returned empty instead of `fastest-rotation`.
- GREEN: `gofmt -w internal/config/config.go internal/config/config_test.go && go test ./internal/config` passed after updating config defaulting.
- RED: after changing `scripts/validate-vibe-vpn-service-assets.sh` expectations to `mode: fastest-rotation`, `./scripts/validate-vibe-vpn-service-assets.sh` exited 1 against the old example configs.
- GREEN: `./scripts/validate-vibe-vpn-service-assets.sh` passed after examples/docs updates.
- Focused regression: `gofmt -w internal/config/config_test.go internal/service/service_test.go && go test ./internal/config ./internal/service` passed after renaming stale failover-only/default test wording.

## Requested verification commands

- `go test ./...` — passed.
- `go vet ./...` — passed.
- `go build ./cmd/vibe-vpn` — passed.
- `./scripts/validate-vibe-vpn-service-assets.sh` — passed (`vibe-vpn service assets passed static validation`).

## Acceptance mapping

- Default config and omitted/blank `service.mode` resolve to `fastest-rotation`: covered by `internal/config/config_test.go` and `go test ./...`.
- Explicit `failover-only` remains supported: covered by `TestLoadExplicitFailoverOnlyServiceModeSupported`, renamed service scheduled-test failover-only no-rotation test, and `go test ./...`.
- Examples/docs state fastest-rotation default and failover-only opt-out: covered by diff review of `examples/`, `README.md`, `docs/FAILOVER_SERVICE_RUNBOOK.md`, plus service asset validation.
- Validation script checks new expected example defaults: covered by `./scripts/validate-vibe-vpn-service-assets.sh`.
- No VPS/deploy/ssh/scp/systemctl production mutation commands were run.
