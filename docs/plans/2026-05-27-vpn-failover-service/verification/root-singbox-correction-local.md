# Root sing-box correction verification

Date: 2026-05-27
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/docs-failover-service-plan`
Branch: `docs/failover-service-plan`
Claim: current failover-service branch no longer has an xray-first production deployment path; production runtime defaults to sing-box and sing-box apply writes sing-box outbound schema.

## Fresh commands run by root owner

- `bash -n scripts/install-vibe-vpn-service.sh` — passed.
- `bash -n scripts/validate-vibe-vpn-service-assets.sh` — passed.
- `./scripts/validate-vibe-vpn-service-assets.sh` — passed: `vibe-vpn service assets passed static validation`.
- `go test ./internal/config ./internal/vless ./internal/singbox ./cmd/vibe-vpn` — passed.
- `go test ./...` — passed.
- `go vet ./...` — passed.
- `go build ./cmd/vibe-vpn` — passed; generated local `vibe-vpn` binary removed.

## Acceptance evidence

- Config defaults/examples use `runtime: singbox`, `sing_box_config: /etc/sing-box-vibe/tproxy-canary.json`, and `sing_box_service: sing-box-vibe-router`.
- `applyResult`, `cmdRollback`, `cmdStatus`, and `cmdDoctor` dispatch by configured runtime.
- `runtime: singbox` derives production outbound JSON from the selected VLESS `link` via `vless.SingBoxOutbound`, then applies through `internal/singbox`.
- Regression tests prove sing-box apply writes `type: vless`, `server`, `server_port`, `uuid`, TLS/Reality fields, and does not write xray `protocol`, `settings`, or `streamSettings` keys.
- `runtime: xray` remains explicit legacy support; isolated temporary xray benchmark behavior remains separate from production runtime.

## Safety / not run

- No VPS deploy/run/mutation was performed.
- No SSH/SCP was run.
- No production `systemctl start|enable|restart`, production apply, or production rollback was run. Tests use local temp files/fake `systemctl` only.
