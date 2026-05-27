# Acceptance plan: Sing-box test backend by default

## Acceptance criteria
- AC1: `vibe-vpn test`, `pick`, and daemon startup/scheduled tests use isolated temporary native sing-box on `test_socks` by default for `runtime: singbox`, without mutating production sing-box config/service.
- AC2: explicit `runtime: xray` remains supported for legacy isolated temporary xray benchmarks when practical.
- AC3: CLI wording/help/docs/examples/tests say sing-box is the default test backend; xray is legacy-only when runtime is xray.
- AC4: stale temp cleanup/prune handles sing-box temp artifacts and preserves xray cleanup for legacy runtime.
- AC5: fresh verification commands pass.
- AC6: branch is pushed and PR is open; no VPS deployment performed.

## Verification targets
- Fresh local checks: `go test ./...`, `go vet ./...`, `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`, `./scripts/validate-vibe-vpn-service-assets.sh`.
- Evidence review: inspect `cmd/vibe-vpn/main.go`, `cmd/vibe-vpn/cli_test.go`, `README.md`, and `examples/*.yaml` for sing-box-default wording and dispatch.
- Remote status: confirm branch push and PR state; note whether CI checks are reported.

## Expected decision
- Accept only if AC1-AC6 are all covered by current evidence or explicit waiver.
