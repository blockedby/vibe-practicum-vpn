# Acceptance audit plan

Scope: final acceptance audit of the local implementation for `docs/vpn-failover-service-plan.md` section 10 plus user-request constraints.

Checklist:
- Map all 17 source-plan acceptance criteria to implementation evidence.
- Confirm daemon/systemd/runtime wiring exists locally and is statically verified.
- Confirm config/health/logging contracts, scheduled test loop, progressive confirmation, failover selection/apply, and docs/runbook coverage.
- Confirm local verification evidence is fresh: `go test ./...`, `go vet ./...`, `go build ./cmd/vibe-vpn`, targeted package tests, and static unit/script validation.
- Treat VPS/systemd smoke as an explicit limitation/waiver because the user forbade live mutation commands.
- Record any remaining blockers separately from non-blocking limitations.
