## Task
- Mission: Slice C docs/runbook/scripts/final readiness prep for local VPN failover service.
- Target: docs, sample configs, safe install/validation scripts, service timing evidence, acceptance reconciliation.
- Boundaries: no `ssh`, `scp`, `systemctl`, VPS deploy/start, or production xray command was run.
- Done when: docs and static assets match implemented CLI/unit/config; all 17 source-plan ACs map to test/static evidence or explicit manual waiver; fresh local verification passes.

## Context
- Thread: implement local VPN failover service from `docs/vpn-failover-service-plan.md`.
- Slice: Slice C — docs/runbook/scripts and final readiness prep.
- Task package: `docs/plans/2026-05-27-vpn-failover-service`.
- Report path: `docs/plans/2026-05-27-vpn-failover-service/reports/slice-c-docs-verification.md`.
- Worktree/branch: `/home/kcnc/code/tools/vibe-practicum-vpn`, `docs/failover-service-plan`.

## Spec compliance
- Install/start/status/logs runbook: done. Evidence: `docs/FAILOVER_SERVICE_RUNBOOK.md` covers `systemctl enable --now vibe-vpn`, status, journal, `/var/log/vibe-vpn/`, 12h retention, rollback, smoke, pre-deploy checks, and explicit no-VPS-run note.
- Config examples: done. Evidence: `examples/vibe-vpn-config.yaml`, `examples/vibe-vpn-smoke-config.yaml` match `internal/config` schema and service defaults.
- Preparatory scripts: done. Evidence: `scripts/install-vibe-vpn-service.sh` and `scripts/validate-vibe-vpn-service-assets.sh` use `set -euo pipefail`, parameterized inputs, and no SSH/SCP/systemctl start/enable.
- Manual CLI continuity: done. Evidence: runbook documents `vibe-vpn test/pick/apply/rollback` still exists.
- Service state-machine timing evidence gap: resolved. Evidence: `internal/service/service_test.go` covers persistent failure triggering failover after configured retry delays and recovery resetting without failover.

## Acceptance verification matrix
1. `vibe-vpn.service` exists: passed; `systemd/vibe-vpn.service`, validation script grep.
2. Starts at boot: passed statically; `[Install] WantedBy=multi-user.target` plus runbook `enable --now`; real enable waived.
3. Restarts on crash: passed statically; `Restart=always`, `RestartSec=5`.
4. Tests every 30m: passed; config default/tests from Slice A plus sample config `interval: 30m`.
5. Health through VPN/SOCKS: passed by implementation evidence; `health.NewRunner(c.ProductionSocks, ...)` in `internal/service` and Slice B report.
6. Normal 5s checks: passed; config default/tests and sample config `normal_interval: 5s`.
7. URL checks parallel/asynchronous: passed; `internal/health` tests/Slice A report.
8. Checks x.com/rutracker/ya.ru: passed; defaults, examples, validation script.
9. Failover uses x.com/rutracker required URLs: passed; `FailoverNeeded` only required URLs, Slice A report.
10. Progressive 1s/2s/3s confirmation: passed; config default/tests plus new `internal/service` timing tests.
11. Switch after confirmed fail: passed; `internal/service/service_test.go` and Slice B report.
12. Switch to next fast working node: passed; `internal/failover/failover_test.go`, Slice B report.
13. If new node fails, try next: passed; `internal/failover/failover_test.go`, Slice B report.
14. Exhaustion does not kill service: passed by Slice B code/report; manual daemon runtime smoke waived.
15. Logs max 12h: passed; `internal/logging` tests/Slice A report and docs/examples.
16. Logs redact VPN secrets: passed; `internal/logging` tests/Slice A report and docs warnings.
17. Install/start/logs/rollback docs: passed; `docs/FAILOVER_SERVICE_RUNBOOK.md`, README link.

## System readiness
- Services/runtime wiring: locally ready; systemd unit and daemon CLI exist, statically verified. Live VPS/systemd start/status intentionally not run.
- Config/env/secrets: ready with placeholder examples; real `/etc/vibe-vpn/sub_url` remains operator-provided secret, mode `0600` documented.
- Permissions/access: docs/scripts create root-owned directories/files; not executed locally against VPS.
- Runtime/deployment wiring: ready except manual operator smoke on target VPS.

## Verification run
- `bash -n scripts/install-vibe-vpn-service.sh`: passed.
- `bash -n scripts/validate-vibe-vpn-service-assets.sh`: passed.
- `./scripts/validate-vibe-vpn-service-assets.sh`: passed.
- `go test ./internal/service`: passed.
- `go test ./...`: passed.
- `go vet ./...`: passed.
- `go build ./cmd/vibe-vpn`: passed.
- Evidence artifact: `docs/plans/2026-05-27-vpn-failover-service/verification/slice-c-final-local.md`.

## Issues
### R-01: Docs/runbook/readiness assets completed
- Evidence: runbook, examples, scripts, validation checks.
- Resolution: Added missing docs/scripts/examples and README link.

### R-02: State-machine timing evidence gap closed
- Evidence: `internal/service/service_test.go`; targeted `go test ./internal/service` passed.
- Resolution: Added cheap local tests for progressive confirmation and recovery reset.

### U-01: Manual VPS/systemd smoke not run by explicit boundary
- Description: `systemctl enable --now vibe-vpn`, `systemctl status`, `journalctl -u vibe-vpn -f`, live xray/VPS checks were not run.
- Evidence: User forbade VPS deployment/running; verification artifact only contains local commands.
- Why unresolved: hard scope/safety boundary.
- Needed next: operator runs pre-deploy and smoke checklist from `docs/FAILOVER_SERVICE_RUNBOOK.md` on the VPS when authorized.

## Side findings
- Blocking findings folded into active work: R-02.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: success with explicit manual-smoke waiver.
- Goal state: achieved locally.
- Final readiness: PR-ready/local-ready; production readiness requires user-run VPS/systemd smoke.
