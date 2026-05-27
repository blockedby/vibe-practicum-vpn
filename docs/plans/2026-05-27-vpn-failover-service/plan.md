# VPN failover service implementation plan/ledger

## Intake

Implement the accepted plan in `docs/vpn-failover-service-plan.md` locally on the current checkout/branch. Prepare daemon/systemd/service files, health probes, progressive retry, scheduled test loop, failover selection/apply wiring, 12h log retention, and docs/runbook/scripts. Do **not** deploy, enable, start, or mutate anything on a VPS; local tests/build are allowed.

## Root acceptance criteria

1. `vibe-vpn.service` exists and is installable for boot startup.
2. Unit has network-online ordering and `Restart=always`/`RestartSec=5` root service behavior.
3. `vibe-vpn daemon --config /etc/vibe-vpn/config.yaml|json` entrypoint starts a long-running service and handles SIGTERM/SIGINT.
4. Scheduled node test loop runs every 30m by default, optional startup test, never applies production node, logs errors without killing daemon, and preserves old `last-results.json`.
5. Health probes run through production SOCKS/VPN, default every 5s, required URLs `https://x.com/` and `https://rutracker.org/`, diagnostic URL `https://ya.ru/`, URL checks parallel/asynchronous, timeout default 5s.
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
