# sing-box runtime correction local verification

Claim: failover service production runtime paths are corrected to sing-box by default, with xray retained only for explicit legacy runtime or isolated temporary benchmarking.

## Fresh commands run

- `bash -n scripts/install-vibe-vpn-service.sh` — passed.
- `bash -n scripts/validate-vibe-vpn-service-assets.sh` — passed.
- `./scripts/validate-vibe-vpn-service-assets.sh` — passed: `vibe-vpn service assets passed static validation`.
- `go test ./...` — passed, including `internal/singbox` and changed CLI/config tests.
- `go vet ./...` — passed.
- `go build ./cmd/vibe-vpn` — passed.

## Static evidence

- `grep -R "production xray\|Rollback production xray\|restart xray\|systemctl status xray\|Applied to production xray" -n README.md docs/FAILOVER_SERVICE_RUNBOOK.md scripts/install-vibe-vpn-service.sh scripts/validate-vibe-vpn-service-assets.sh systemd/vibe-vpn.service cmd internal examples || true` returns only legacy `internal/xray` package messages and example comments that are behind explicit `runtime: xray`/temporary benchmark wording; failover docs/scripts/examples no longer instruct production xray rollback/status.

## Safety

- No ssh/scp commands run.
- No systemctl start/enable/restart run by owner. Tests stub runtime restarts; static docs include operator commands only.
- No VPS deploy/run/mutation performed.
