## Task
- Mission: Fix the current-goal blocker where production sing-box apply/failover could write xray/V2Ray outbound schema into a sing-box config.
- Target: `internal/vless`, `cmd/vibe-vpn.applyResult`, and related tests.
- Boundaries: No route-policy refactor; xray legacy runtime and isolated temporary xray benchmark behavior preserved; no VPS or production service mutation.
- Done when: Sing-box production apply derives sing-box VLESS outbound JSON from the selected stored link and tests prove no xray schema leaks into sing-box config.
- Expected evidence: Targeted tests, full Go checks, and this report/verification artifact.

## Context
- Thread: urgent sing-box correction after root integration blocker.
- Slice: sing-box outbound format fix.
- Task package: `docs/plans/2026-05-27-vpn-failover-service`.
- Report path: `docs/plans/2026-05-27-vpn-failover-service/reports/singbox-outbound-format-fix.md`.
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/docs-failover-service-plan`.
- Branch: `docs/failover-service-plan`.
- Verify scope: local tests/build/static only.

## Spec compliance
- AC1: Sing-box production apply path does not write xray schema.
  - Status: done.
  - Evidence: `applyResult` now calls `vless.SingBoxOutbound(b.Link)` for `runtime: singbox`; `TestApplyResultSingBoxDerivesOutboundFromLink` fails if `protocol`, `settings`, or `streamSettings` appear in the sing-box config.
- AC2: Supported VLESS link features convert to sing-box schema and tag is preserved.
  - Status: done for parser-supported TCP, TLS, Reality, WS, and gRPC.
  - Evidence: `vless.SingBoxOutbound` emits `type`, `server`, `server_port`, `uuid`, `flow`, `tls`, `tls.reality`, and `transport` fields; existing `singbox.Apply` preserves `proxy`/`xray-socks-out` when generated outbound has no tag.
- AC3: Xray runtime and temporary xray benchmark path keep xray schema.
  - Status: done.
  - Evidence: `runtime: xray` branch still passes `b.Outbound` to `xray.Apply`; `runTest` still builds temporary xray configs from `n.Outbound`; existing xray-path CLI tests pass.
- AC4: Realistic VLESS/Reality sing-box apply test.
  - Status: done.
  - Evidence: `TestApplyResultSingBoxDerivesOutboundFromLink` uses a VLESS Reality link and asserts sing-box config fields plus xray-key absence.
- AC5: Docs/report note benchmark results still include xray outbound.
  - Status: done.
  - Evidence: this report notes `Node.Outbound` remains xray/V2Ray for benchmarks and explicit xray runtime; production sing-box derives from stored `Link`.
- AC6: Fresh verification.
  - Status: done.
  - Evidence: `verification/singbox-outbound-format-fix-local.md`.

## Acceptance verification
- Targeted converter/apply tests:
  - Covered by: `go test ./internal/vless ./cmd/vibe-vpn`.
  - Result: passed.
  - Evidence: local command completed successfully.
- Full regression checks:
  - Covered by: `go test ./...`, `go vet ./...`, `go build ./cmd/vibe-vpn`.
  - Result: passed.
  - Evidence: `verification/singbox-outbound-format-fix-local.md`.

## System readiness
- Routes / registration: not relevant.
- Services / APIs: production sing-box apply wiring corrected locally; no service mutation run.
- Config / env / secrets: no secrets touched.
- Permissions / access: not changed.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: local code path ready; VPS smoke remains intentionally not run.

## Verification run
- Local / targeted checks:
  - `go test ./internal/vless ./cmd/vibe-vpn`: passed.
- Local / full checks:
  - `go test ./...`: passed.
  - `go vet ./...`: passed.
  - `go build ./cmd/vibe-vpn`: passed; generated binary removed.
- Remote checks / CI:
  - Status: not checked in this slice.
  - Evidence: local worktree only.

## Issues
### Issue R-01: Sing-box apply used xray outbound schema
- Description: `applyResult` previously passed `picker.NodeResult.Outbound` to `singbox.Apply`; that outbound is xray/V2Ray schema from `internal/vless.Parse`.
- Evidence: root blocker plus prior code path.
- Resolution: Added `vless.SingBoxOutbound(link)` and changed sing-box runtime apply to convert from `NodeResult.Link`; added regression tests.
- Depends on: none.

## Side findings
- Blocking findings folded into active work: R-01.
- Non-blocking findings tracked separately: none.
- Limitation: converter supports the VLESS features currently parsed by repo code: TCP baseline, TLS, Reality, WS, and gRPC. Other transports/security modes return explicit unsupported errors instead of writing malformed sing-box config.

## Verdict
- Status: success.
- Goal state: fully achieved locally.
- Final readiness: ready for parent/root acceptance subject to existing VPS smoke boundary.
- Summary: Production sing-box apply/failover now derives sing-box VLESS outbound JSON from the stored selected link; xray benchmark/runtime behavior remains isolated and unchanged.
