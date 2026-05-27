# Sing-box outbound format fix local verification

Date: 2026-05-27
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/docs-failover-service-plan`
Branch: `docs/failover-service-plan`
Safety: local-only checks; no VPS deploy/run/mutation and no production service restarts.

## Targeted checks

- `go test ./internal/vless ./cmd/vibe-vpn` — passed.
  - Covers VLESS link to sing-box outbound conversion for Reality, TLS, WS, and gRPC.
  - Covers `applyResult` for `runtime: singbox`, using a fake local `systemctl`, writing a sing-box config with `type: vless`, `server`, `server_port`, `uuid`, TLS/Reality fields, preserved `xray-socks-out` tag, and no xray `protocol`/`settings`/`streamSettings` keys.

## Full local checks

- `go test ./...` — passed.
- `go vet ./...` — passed.
- `go build ./cmd/vibe-vpn` — passed. Generated local `vibe-vpn` binary was removed after the check.

## Waivers / not run

- VPS deploy, production apply/rollback/status commands, and production `systemctl` service mutation were not run per safety boundary.
