# Plan: Sing-box test backend by default

## Intake

User request: testing/benchmarking still runs via temporary xray; change `vibe-vpn` so node tests/benchmarks use native sing-box by default when runtime is singbox. Production already uses sing-box.

## Scope / constraints

In scope:
- `vibe-vpn test`, `pick`, daemon startup/scheduled tests use temporary isolated sing-box for benchmarks under default `runtime: singbox`.
- Keep explicit `runtime: xray` legacy benchmark support if practical, but xray must not be default test backend.
- Update CLI wording, doctor/prune cleanup, docs, examples, and tests to say sing-box test backend by default.
- Preserve isolated temp benchmark SOCKS on `test_socks`; do not mutate production sing-box config/service for benchmarking.
- Validate with `go test ./...`, `go vet ./...`, build, and `./scripts/validate-vibe-vpn-service-assets.sh`.

Out of scope / do-not-touch:
- No VPS deployment, SSH/SCP, or live `systemctl` production mutation.
- Do not commit secrets, full subscription links, tokens, private keys, or VPS-specific secret material.
- Do not opportunistically redesign production routing or unrelated IKEv2/OpenVPN docs.

## Ownership model

One implementation slice. Reason: the change has one acceptance story (benchmark backend dispatch and wording) across one CLI/runtime boundary; splitting code/docs would add coordination without independent acceptance value.

## Acceptance criteria

AC1. Default `runtime: singbox` tests/pick/daemon scheduled tests start isolated temporary sing-box on `test_socks`, benchmark through it, and leave production sing-box config/service untouched.
AC2. Explicit `runtime: xray` remains supported for legacy isolated temporary xray tests when practical.
AC3. CLI help/output/doctor/prune cleanup/docs/examples/tests no longer describe xray as the default test backend; they describe sing-box under singbox runtime and legacy xray only when runtime is xray.
AC4. Stale temp process/file cleanup covers new sing-box temp artifacts and preserves xray cleanup for legacy runtime where appropriate.
AC5. Fresh verification passes: `go test ./...`, `go vet ./...`, `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`, `./scripts/validate-vibe-vpn-service-assets.sh`.
AC6. Branch is committed and pushed; PR opened if feasible. No VPS deploy is performed.

## Likely files / reusable patterns

- `cmd/vibe-vpn/main.go`: CLI commands, `runTest`, `testOne`, cleanup/prune/doctor wording.
- `cmd/vibe-vpn/cli_test.go`, `daemon_test.go`, `main_test.go`: CLI/runtime behavior tests.
- `internal/singbox/singbox.go`, `internal/singbox/singbox_test.go`: existing sing-box config/outbound patterns.
- `internal/vless/vless.go`: `SingBoxOutbound(link)` conversion for native sing-box outbound.
- `internal/xray/xray.go`: legacy temp config pattern.
- `README.md`, `examples/*.yaml`, targeted docs for production test plan/runbook wording.
- `scripts/validate-vibe-vpn-service-assets.sh` and install script if wording/config assumptions surface.

## Execution task

### Task 1: Native sing-box benchmark backend dispatch

Goal:
- Benchmarks use isolated native sing-box by default for singbox runtime and xray only for explicit xray runtime.

Boundary:
- System area: Go CLI/runtime benchmark path plus docs/tests.
- Primary verification: targeted unit tests plus full repo Go checks and service validation script.

Existing pattern / reuse:
- Reuse `vless.SingBoxOutbound(link)` for native sing-box outbound.
- Reuse temp file/process pattern from `testOne`/xray path.
- Reuse `singbox.Check` or `sing-box run -c <temp>` CLI conventions without calling production service.

Acceptance criteria:
- AC1-AC6 above.

Test plan:
- Add/update tests proving default singbox runtime invokes sing-box temp backend and explicit xray invokes xray temp backend without production config mutation.
- Add/update help/prune/doctor tests for wording and cleanup artifact names.
- Run final commands in AC5.

Dependencies:
- Depends on: none.
- Blocks: root integration/final report.

Executor:
- aad-slice-owner.

## Execution ledger

- 2026-05-28: Root worktree created at `.worktrees/pi-singbox-test-backend` on branch `pi/singbox-test-backend` from `origin/main`.
- 2026-05-28: Root task package created. Delegating one implementation slice to `aad-slice-owner`.
