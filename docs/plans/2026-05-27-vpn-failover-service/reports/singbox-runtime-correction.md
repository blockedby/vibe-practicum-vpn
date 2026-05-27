## Task
- Mission: Correct current failover service branch from xray-first production runtime to sing-box production runtime.
- Target: `cmd/vibe-vpn`, `internal/config`, new `internal/singbox`, examples, README/runbook/static validation.
- Boundaries: No VPS deploy/run/mutation; no production service restart; keep xray only where explicit legacy or isolated benchmark behavior remains.
- Done when: Production apply/rollback/status/doctor/failover use configured runtime with sing-box default, docs/examples/scripts point operators at sing-box, and fresh local verification passes.
- Expected evidence: Changed files plus local tests/build/static script checks.

## Context
- Thread: Urgent correction before VPS update; production runtime is sing-box, not xray.
- Slice: sing-box runtime correction for failover service PR.
- Task package: `docs/plans/2026-05-27-vpn-failover-service`.
- Report path: `docs/plans/2026-05-27-vpn-failover-service/reports/singbox-runtime-correction.md`.
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/docs-failover-service-plan`.
- Branch: `docs/failover-service-plan`.

## Spec compliance
- Runtime selector/default: done. `internal/config.Config` now has `runtime`, `sing_box_bin`, `sing_box_config`, `sing_box_service`; defaults/examples use `runtime: singbox` and `sing-box-vibe-router`.
- Production apply/rollback/status/doctor/failover: done. `applyResult`, `cmdRollback`, `cmdStatus`, and `cmdDoctor` dispatch by runtime; daemon failover reuses `applyResult`.
- Sing-box adapter: done. `internal/singbox` applies to sing-box JSON outbounds, preserves outbound tag, creates `sing-box-*` backups, restarts configured sing-box service, and has a unit test with stubbed systemctl.
- Temporary xray benchmark behavior: done. CLI/docs/examples continue to label temp xray as isolated benchmark-only; production `pick/apply/rollback` wording now says configured runtime / sing-box default.
- Docs/scripts/examples: done. README, runbook rollback, config examples, and static validation now point to sing-box production service/config.
- Secrets/VPS safety: done. No secrets added; no VPS mutation commands run.

## Acceptance verification
- AC1 production paths no longer hard-wired to xray: passed via code inspection and `go test ./...`; dispatch now uses `normalizedRuntime` and `internal/singbox` for default runtime.
- AC2 explicit runtime selector/default/validation: passed via config validation tests and examples/static validation.
- AC3 temporary benchmark behavior safe/accurate: passed via README/examples/CLI wording; xray remains described as isolated temporary benchmark only unless `runtime: xray` is explicit.
- AC4 systemd/install/static/docs no longer direct production xray path: passed via grep/static validation; runbook rollback now checks `sing-box-vibe-router`.
- AC5 reuse sing-box patterns: passed; uses repo service/config names (`sing-box-vibe-router`, `/etc/sing-box-vibe/tproxy-canary.json`) and `sing-box check` convention in doctor/static docs.
- AC6 no secrets/VPS commands: passed; no secrets committed, no ssh/scp/systemctl production mutation run.
- AC7 fresh local verification: passed; see verification artifact.

## System readiness
- Routes / registration: not relevant.
- Services / APIs: done locally; production service name now configurable and defaults to `sing-box-vibe-router`.
- Config / env / secrets: done; examples contain no secrets and select sing-box.
- Permissions / access: operator-only VPS checks remain documented, not run.
- Runtime / deployment wiring: ready except user-authorized VPS smoke/deploy is still required before production update.

## Verification run
- Local / targeted checks:
  - `go test ./internal/config ./cmd/vibe-vpn ./internal/singbox`: passed during iteration.
  - `./scripts/validate-vibe-vpn-service-assets.sh`: passed.
- Local / full checks:
  - `go test ./...`: passed.
  - `go vet ./...`: passed.
  - `go build ./cmd/vibe-vpn`: passed.
- Remote checks / CI: not available before push.

## Issues
### Issue R-01: xray-first production runtime path
- Description: Current branch defaulted production apply/rollback/status/doctor to xray.
- Evidence: prior `Config.Default`, `applyResult`, `cmdRollback`, `cmdStatus`, `cmdDoctor` used xray fields/service directly.
- Resolution: Added explicit runtime selector with sing-box default and runtime-specific dispatch.

### Issue R-02: operator docs pointed rollback/status at xray
- Description: README/runbook told operator to inspect production xray during rollback.
- Resolution: Updated to sing-box service/config and clarified temp xray benchmark-only behavior.

## Side findings
- Blocking findings folded into active work: R-01, R-02.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: success.
- Goal state: achieved locally.
- Final readiness: ready except explicit limitation: production VPS deploy/smoke not run by request.
- Summary: Branch is now sing-box-default for failover service production runtime with xray retained only as explicit legacy runtime or isolated benchmark support.
