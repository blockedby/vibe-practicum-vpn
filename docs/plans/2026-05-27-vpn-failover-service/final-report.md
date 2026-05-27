## Task
- Mission: Urgently correct the failover-service PR so production runtime is sing-box, not xray.
- Target: current worktree/branch `docs-failover-service-plan` / `docs/failover-service-plan`.
- Boundaries: no VPS deploy/run/mutation; no SSH/SCP; no production `systemctl` service mutation; preserve isolated xray benchmarking only where safe.
- Done when: config/runtime/apply/rollback/status/doctor/docs/scripts default to sing-box production, do not write xray schema into sing-box config, and local verification passes.

## Context
- Task package: `docs/plans/2026-05-27-vpn-failover-service`.
- Prior implementation reports: `reports/slice-a-foundation.md`, `reports/slice-b-runtime.md`, `reports/slice-c-docs-verification.md`.
- Correction reports: `reports/singbox-runtime-correction.md`, `reports/singbox-outbound-format-fix.md`.
- Root verification: `verification/root-singbox-correction-local.md`.

## Slice structure used
- One correction slice for xray-to-sing-box runtime selection/docs/scripts, then one focused blocker fix for sing-box outbound format.
- Reason: one urgent acceptance story across config/runtime/docs; the second pass was required because integration found xray/V2Ray outbound JSON could be written into sing-box config.

## Spec compliance / acceptance verification
- Production runtime selector/default: done. `internal/config` defaults to `runtime: singbox`, `/etc/sing-box-vibe/tproxy-canary.json`, and `sing-box-vibe-router`; validation rejects unsupported/incomplete runtime config.
- Production apply/failover: done. `runtime: singbox` uses `vless.SingBoxOutbound(selected.Link)` plus `internal/singbox.Apply`; regression tests prove no xray `protocol/settings/streamSettings` keys leak into sing-box config.
- Rollback/status/doctor: done. Commands dispatch by configured runtime; sing-box is default, xray is explicit legacy only.
- Temporary benchmarking: done. Isolated benchmark tests may still use temporary xray on `test_socks`; docs distinguish this from production sing-box runtime.
- Docs/scripts/examples: done. README, runbook rollback/status, config examples, and static validation point at sing-box production.
- Safety: done. No secrets added; no VPS deploy/run/mutation performed.

## Verification run
- `bash -n scripts/install-vibe-vpn-service.sh`: passed.
- `bash -n scripts/validate-vibe-vpn-service-assets.sh`: passed.
- `./scripts/validate-vibe-vpn-service-assets.sh`: passed.
- `go test ./internal/config ./internal/vless ./internal/singbox ./cmd/vibe-vpn`: passed.
- `go test ./...`: passed.
- `go vet ./...`: passed.
- `go build ./cmd/vibe-vpn`: passed.

## System readiness
- Local branch is ready for review/PR update with sing-box production runtime defaults.
- Production readiness still requires operator-authorized VPS deploy/smoke using the updated runbook.
- Secrets remain external (`/etc/vibe-vpn/sub_url`, optional extra nodes); examples contain placeholders/paths only.

## Issues
### R-01: xray-first production runtime path
- Resolution: added explicit runtime selection and sing-box defaults/adapters/docs.

### R-02: xray outbound schema could be written into sing-box config
- Resolution: sing-box production apply now converts the selected VLESS link into sing-box outbound schema before modifying sing-box config; tests cover Reality/TLS/WS/gRPC-supported parser features.

### U-01: Live VPS/systemd smoke not run
- Evidence: user explicitly forbade VPS deploy/run.
- Needed next: when authorized, operator should install/update on VPS and run `vibe-vpn doctor`, `vibe-vpn test`, `systemd-analyze verify`, service enable/status/journal checks, and a controlled rollback check if needed.

## Verdict
- Status: success with explicit live-smoke limitation.
- Goal state: locally achieved.
- Final readiness: branch is safe for review/update toward sing-box production; not yet production-deployed or VPS-smoked.

## 2026-05-27 production runtime correction addendum

A read-only production check confirmed the active production router is native sing-box:

- `sing-box-vibe-router.service`: enabled and active, running `/usr/bin/sing-box run -c /etc/sing-box-vibe/tproxy-canary.json`.
- `/etc/sing-box-vibe/tproxy-canary.json`: route final is `selected-native-out`, an outbound of type `vless`.
- `xray.service`: disabled for boot but still active as a legacy SOCKS listener; this PR must not target it by default.

Correction applied locally:

- default `runtime: singbox`;
- default `sing_box_config: /etc/sing-box-vibe/tproxy-canary.json`;
- default `sing_box_service: sing-box-vibe-router`;
- default `production_socks: 127.0.0.1:2080` so health probes use the production sing-box SOCKS path;
- `xray_bin` remains for isolated benchmark tests only unless `runtime: xray` is explicitly configured.

Evidence: `verification/production-singbox-readonly.md`.
