# Apply adapter slice owner report

## Task
Implement a container-safe apply/failover switching adapter for `vibe-vpn` in the vpnkit container while preserving VPS systemd defaults and REDIRECT lab behavior.

## Ownership model
- Slice stayed whole; no sub-slices.
- Implementation was done directly because nested implementer delegation was unavailable in this execution context. Plan and progress were written under the task package before implementation.

## Changed files
- `internal/config/config.go` — added sing-box restart adapter config fields, defaulting to systemd and validating request-file mode.
- `internal/singbox/singbox.go` / `internal/singbox/singbox_test.go` — added `RestartConfig`, request-file adapter, safe request creation, candidate validation for request-file mode, rollback/apply variants, and tests.
- `cmd/vibe-vpn/main.go` — wires config into sing-box apply/rollback.
- `docker/vpnkit/entrypoint.sh` — supervises sing-box from writable config, handles restart request file, and keeps entrypoint as sole long-lived sing-box owner.
- `docker-compose.yml` — adds writable sing-box state volume.
- `config/vibe-vpn/container-lab.yaml.template` — selects writable active config and request-file adapter.
- `scripts/vpnkit-vibe-vpn-e2e.sh` — adds `--switching` to apply best and repeat client probes.
- Task package docs/progress/verification files.

## Verification evidence
See `verification/apply-adapter.md`.

Passed:
- `go test ./...`
- `go vet ./...`
- `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`
- Shell syntax checks for modified scripts.
- `docker compose config`
- Real e2e baseline before switching: doctor, test, sing-box check, OpenVPN client IP, DNS, HTTPS, literal-IP all passed.
- Real apply request: `apply best` updated state/config and requested supervisor restart; post-apply config check passed.

Not accepted:
- Post-switch OpenVPN client DNS/HTTPS did not pass with the available real winning node. Evidence indicates selected outbound server hostname resolution loops/timeouts after apply.

## Issues
- R-1: Production default remains systemd; Go tests pass.
- R-2: Container request-file adapter and supervisor-owned restart path implemented; `vibe-vpn` does not own long-lived sing-box.
- R-3: Existing REDIRECT path still passes before switching; no broad MASQUERADE added.
- U-1: Full switched data path remains unresolved for the available real node because selected outbound hostname resolution loops in sing-box after apply. Needs current-goal follow-up if root requires working switching now; likely fix is to add/verify safe direct/domain resolver behavior for proxy server DNS without bypassing client DNS-over-selected-out acceptance.

## Verdict
**partial**. The container-safe apply adapter mechanism is implemented and useful, but the slice does not meet the final `working switching` acceptance until post-switch client DNS/HTTPS passes.
