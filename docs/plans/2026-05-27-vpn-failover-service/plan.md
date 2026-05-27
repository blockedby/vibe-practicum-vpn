# VPN failover service implementation plan/ledger

## Intake

Implement the accepted plan in `docs/vpn-failover-service-plan.md` locally on the current checkout/branch. Prepare daemon/systemd/service files, health probes, progressive retry, scheduled test loop, failover selection/apply wiring, 12h log retention, and docs/runbook/scripts. Do **not** deploy, enable, start, or mutate anything on a VPS; local tests/build are allowed.

## Root acceptance criteria

1. `vibe-vpn.service` exists and is installable for boot startup.
2. Unit has network-online ordering and `Restart=always`/`RestartSec=5` root service behavior.
3. `vibe-vpn daemon --config /etc/vibe-vpn/config.yaml|json` entrypoint starts a long-running service and handles SIGTERM/SIGINT.
4. Scheduled node test loop runs every 30m by default, optional startup test, never applies production node, logs errors without killing daemon, and preserves old `last-results.json`.
5. Health probes run through production SOCKS/VPN, default every 5s, required URLs `https://x.com/` and `https://www.linkedin.com/`, diagnostic URL `https://ya.ru/`, URL checks parallel/asynchronous, timeout default 5s.
6. Failover decision uses only required URLs; diagnostic URL is reported for diagnosis.
7. Progressive failure confirmation runs after first failure with 1s, 2s, 3s delays and resets on recovery.
8. Confirmed failure selects next fast working node from latest test results after current node, applies/restarts runtime, probes again, tries subsequent nodes on failure, logs critical and stays alive if exhausted.
9. Logs are service-owned rotating files with default 12h retention, important events also reach journal-compatible stdout/stderr, and full VPN secrets/links/subscription URLs/tokens are redacted.
10. Docs/runbook/scripts cover install/start/logs/smoke/rollback and pre-deploy checks.
11. Fresh verification: `go test ./...`, `go vet ./...`, `go build ./cmd/vibe-vpn`; VPS/systemd smoke is explicitly waived/not run unless user later authorizes.

## Slicing/dependencies

Current checkout must be used, so slices run sequentially to avoid worktree conflicts.

### Slice A — foundation contracts, health, logging
- Goal: config defaults/validation for service/test/health/logging; reusable parallel health probes; service logger with redaction and 12h retention tests.
- Depends on: source plan only.
- Blocks: Slice B daemon/failover integration.
- Report: `reports/slice-a-foundation.md`.
- Verification: targeted package tests plus report.

### Slice B — daemon runtime, scheduled tests, failover, systemd
- Goal: `daemon` command, lifecycle, scheduled test loop, progressive health state machine, failover selection/apply adapters, systemd unit.
- Depends on: Slice A.
- Blocks: Slice C docs/final verification.
- Report: `reports/slice-b-runtime.md`.
- Verification: targeted runtime/failover/service tests plus build/help smoke.

### Slice C — docs/runbook/scripts and final readiness prep
- Goal: update docs/runbook and scripts/config examples; reconcile acceptance; run fresh full local verification; prepare final branch report.
- Depends on: Slice B.
- Report: `reports/slice-c-docs-verification.md`.
- Verification: `go test ./...`, `go vet ./...`, `go build ./cmd/vibe-vpn`, diff/stat evidence.

## Do-not-touch and safety boundaries

- Do not run `ssh`, `scp`, `systemctl start/enable/restart`, xray production restart, or VPS mutation commands.
- Do not commit subscription URLs, `vless://` links, auth secrets, generated certs/keys, tokens, or local environment dumps.
- Do not change unrelated CLI behavior except as needed to reuse test/apply logic safely.
- Any manual VPS/systemd checks remain user-performed pre-deploy steps documented as not run locally.

## Execution ledger

- 2026-05-27 root: task package created on current checkout; repo root `AGENTS.md` absent; README and source plan read; no relevant child `AGENTS.md` found under repo.
- 2026-05-27 Slice A: complete. Report `reports/slice-a-foundation.md`; verification `verification/slice-a-foundation.md`; targeted config/health/logging tests and `go test ./...` passed. Ready for Slice B.
- 2026-05-27 Slice B: complete locally. Report `reports/slice-b-runtime.md`; verification `verification/slice-b-runtime.md`; targeted failover/daemon tests, `go test ./...`, `go vet ./...`, build, and daemon help smoke passed. No VPS/systemd/xray production commands run.
- 2026-05-27 Slice B: complete. Report `reports/slice-b-runtime.md`; verification `verification/slice-b-runtime.md`; daemon/runtime/failover/systemd implemented; `go test ./...`, `go vet ./...`, `go build -o vibe-vpn ./cmd/vibe-vpn`, and daemon help smoke passed. VPS/systemd smoke intentionally not run.
- 2026-05-27 Slice C gate: plan has intake, repo orientation, reuse targets, missing docs/scripts/final-evidence pieces, task boundaries, dependencies, and verification commands. Slice C stays whole; one aad-implementer will update docs/scripts/evidence, then owner will run fresh final verification and final report. Manual VPS/systemd smoke remains explicitly out of scope unless user authorizes.
- 2026-05-27 Slice C: complete locally. Added failover service runbook, examples, safe install/static validation scripts, README link, and targeted service timing tests. Final verification artifact `verification/slice-c-final-local.md` records passing script syntax/static checks, `go test ./internal/service`, `go test ./...`, `go vet ./...`, and `go build ./cmd/vibe-vpn`. Acceptance matrix for all 17 source-plan criteria is in `reports/slice-c-docs-verification.md`. Manual VPS/systemd smoke remains U-01 waiver due to explicit user boundary.
- 2026-05-27 Acceptance audit: `reports/acceptance-auditor.md` accepted local implementation with explicit VPS/systemd smoke limitation.
- 2026-05-27 Root final verification: `verification/root-final-local.md`; static scripts, `go test ./...`, `go vet ./...`, and `go build ./cmd/vibe-vpn` passed. Final report written to `final-report.md`. Root done-state: local implementation achieved; production readiness requires user-authorized VPS smoke.

## Urgent correction: production runtime is sing-box, not xray

### Intake
User clarified production runtime for the current VPS update is `sing-box` (repo service evidence: `sing-box-vibe-router` and configs under `configs/sing-box/`). Stop xray-first production deployment path in this branch. Do not deploy/run/mutate VPS.

### Repo orientation / reuse discovery
- Existing failover code currently imports `internal/xray` and config fields `xray_bin`/`xray_config`; CLI apply/rollback/status/doctor are xray-first.
- Existing sing-box production assets live under `configs/sing-box/` and scripts/docs use service name `sing-box-vibe-router`, config dir `/etc/sing-box-vibe`, and binary `sing-box` with `sing-box check -c <config>`.
- Temporary benchmark tests currently use isolated temporary xray configs/processes; this can remain only if docs/messages explicitly distinguish isolated benchmarking from production runtime.
- Safety boundaries: no ssh/scp/systemctl start|enable|restart against production; local tests/build/static script checks only.

### Missing pieces for correction
- Explicit runtime selector and validation for production runtime, defaulting docs/examples to sing-box.
- Runtime adapter paths for production apply/rollback/status/doctor so production commands are not hard-wired to xray.
- Docs/scripts/systemd/examples updated to sing-box deployment path and no production xray rollback/restart instructions for failover service.
- Fresh verification evidence specific to runtime correction.

### Task D: sing-box production runtime correction
Goal:
- Make daemon/failover/apply/rollback/status/doctor/config/docs/scripts safe for sing-box production runtime while preserving isolated xray benchmark behavior only where clearly labeled.
Boundary:
- System area: Go CLI/config/failover runtime adapter plus examples/docs/scripts for failover service.
- Primary verification: targeted config/runtime tests, static script validation, `go test ./...`, `go vet ./...`, `go build ./cmd/vibe-vpn`.
Existing pattern / reuse:
- Reuse adjacent `internal/xray` apply/rollback shape, `internal/config` validation, `cmd/vibe-vpn` command wiring, `configs/sing-box/*.json`, scripts that call `sing-box check -c`, service name `sing-box-vibe-router`.
Missing change:
- Runtime selector (`singbox` default for examples/docs; xray supported only explicitly if retained), sing-box adapter/config validation, docs/script messaging that production path targets sing-box and temp xray is benchmark-only.
Scope / likely files:
- `internal/config/config.go`, `cmd/vibe-vpn/main.go`, `internal/service/service.go`, `internal/failover/failover.go`, new/reused runtime package(s), examples, scripts/install/validate, `systemd/vibe-vpn.service`, `docs/FAILOVER_SERVICE_RUNBOOK.md`, `README.md`, task package reports/verification.
Acceptance criteria:
- User criteria 1-7 from routing request.
- No VPS commands run and no secrets/live VPS values committed.
Test plan:
- Positive: targeted tests for runtime config validation and sing-box adapter command construction with stubs; static scripts; full Go test/vet/build.
- Negative: unsupported runtime/incomplete sing-box config rejected; xray production path only works with explicit `runtime: xray` if retained.
- Manual: VPS deploy/systemd runtime smoke remains not run; operator must do authorized pre-deploy on VPS later.
Dependencies:
- Depends on: existing Slice A-C implementation.
- Blocks: final branch readiness.
- Can run parallel with: none; keep whole due cross-cutting overlap.
Executor:
- aad-implementer.
Status: pending.
Report: `reports/singbox-runtime-correction.md`.
Verification: `verification/singbox-runtime-correction-local.md`.

### Task D execution result
Status: done locally.
- Implemented runtime selector with sing-box production defaults and validation.
- Added `internal/singbox` production adapter and tests; production apply/rollback/status/doctor now dispatch by configured runtime.
- Updated README/runbook/examples/static validation to sing-box production path; xray remains only explicit legacy runtime or isolated temporary benchmark behavior.
- Report: `reports/singbox-runtime-correction.md`.
- Verification: `verification/singbox-runtime-correction-local.md`.
- Fresh checks passed: `bash -n scripts/install-vibe-vpn-service.sh`, `bash -n scripts/validate-vibe-vpn-service-assets.sh`, `./scripts/validate-vibe-vpn-service-assets.sh`, `go test ./...`, `go vet ./...`, `go build ./cmd/vibe-vpn`.
- Safety: no VPS deploy/run/mutation; no ssh/scp/systemctl production mutation commands run.

## Current-goal blocker: sing-box outbound format correction

### Intake
Root integration found that `internal/singbox.Apply` is currently called with `picker.NodeResult.Outbound`, which is produced by `internal/vless.Parse` in Xray/V2Ray schema (`protocol`, `settings.vnext`, `streamSettings`). Production sing-box config `outbounds` expects sing-box schema (`type`, `tag`, `server`, `server_port`, etc.). Fix production sing-box apply/failover to derive a sing-box VLESS outbound from the selected node/link while preserving isolated xray benchmark behavior.

### Repo orientation / reuse discovery
- `internal/vless.Parse` already parses VLESS links into `vless.Node` and xray-style `Node.Outbound`; keep this for xray runtime and temp benchmark path.
- `picker.NodeResult` persists `Link` and xray-style `Outbound`; production sing-box must use `Link` (or parsed node fields/query) instead of `Outbound`.
- `cmd/vibe-vpn.applyResult` dispatches xray vs singbox and currently passes `b.Outbound` to both runtimes.
- `internal/singbox.Apply` replaces the selected sing-box outbound and preserves existing `proxy`/`xray-socks-out` tag when generated outbound omits tag.
- Existing tests in `internal/vless`, `internal/singbox`, and `cmd/vibe-vpn` can be extended for converter/applyResult behavior.

### Missing pieces
- Converter from realistic supported VLESS link features into sing-box VLESS outbound JSON: TCP baseline, TLS, Reality, WS, and gRPC where parser supports them.
- Runtime dispatch change so xray production/runtime paths continue using xray outbound schema, while sing-box production uses converter from stored link.
- Tests proving sing-box config never receives xray keys and preserves tag.
- Focused report and verification artifact for this blocker.

### Task E: sing-box outbound format fix
Goal:
- Make production sing-box apply/failover write valid sing-box outbound schema derived from the selected node/link, without changing isolated xray benchmark behavior.
Boundary:
- System area: VLESS/sing-box runtime conversion plus CLI apply dispatch tests/docs package.
- Primary verification: targeted converter/apply tests plus full Go test/vet/build.
Existing pattern / reuse:
- Reuse `internal/vless.Parse` query/field extraction where possible; follow `internal/singbox.Apply` tag preservation and existing xray runtime dispatch.
Missing change:
- Add converter and change `applyResult` so `runtime: xray` uses `b.Outbound`, `runtime: singbox` derives sing-box outbound from `b.Link` (or parsed node) before `singbox.Apply`.
Scope / likely files:
- `internal/vless/vless.go` and tests or `internal/singbox/singbox.go` and tests; `cmd/vibe-vpn/main.go` and CLI tests; reports/verification docs.
Acceptance criteria:
- User AC1-AC6 from routing request.
Test plan:
- Positive: sing-box apply with realistic VLESS/Reality link writes `type: vless`, `server`, `server_port`, `uuid`, TLS/Reality fields, preserves tag, and omits xray keys.
- Positive: converter covers TCP/TLS/Reality/WS/gRPC supported parser features.
- Negative/regression: xray runtime and temp benchmark paths still use existing xray outbound schema.
- Full: `go test ./...`, `go vet ./...`, `go build ./cmd/vibe-vpn` if feasible.
Dependencies:
- Depends on: Task D runtime selector work.
- Blocks: final branch acceptance.
- Can run parallel with: none; keep whole due shared dispatch/converter surface.
Executor:
- aad-implementer.
Status: ready for implementation.
Report: `reports/singbox-outbound-format-fix.md`.
Verification: `verification/singbox-outbound-format-fix-local.md`.

### Task E execution result
Status: done locally.
- Added `vless.SingBoxOutbound` converter for parser-supported VLESS TCP/TLS/Reality/WS/gRPC links.
- Changed `applyResult` so `runtime: xray` still passes `NodeResult.Outbound` to `xray.Apply`, while `runtime: singbox` derives a sing-box outbound from `NodeResult.Link` before `singbox.Apply`.
- Added regression tests proving sing-box apply writes `type: vless`, `server`, `server_port`, `uuid`, TLS/Reality fields, preserves existing `xray-socks-out` tag, and omits xray `protocol`/`settings`/`streamSettings` keys.
- Report: `reports/singbox-outbound-format-fix.md`.
- Verification: `verification/singbox-outbound-format-fix-local.md`.
- Fresh checks passed: `go test ./internal/vless ./cmd/vibe-vpn`, `go test ./...`, `go vet ./...`, `go build ./cmd/vibe-vpn`.
- Safety: no VPS deploy/run/mutation; no production service restarts.
