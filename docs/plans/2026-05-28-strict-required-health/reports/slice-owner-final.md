## Task
- Mission: Urgent strict required health semantics fix after VPS smoke.
- Target: health runner decision rule, service confirmation tests, and operator docs.
- Boundaries: local worktree only; no VPS deployment/systemd/SSH/SCP.
- Done when: any required URL failure causes failover-needed/progressive confirmation; diagnostics remain non-decisive; docs explain 3xx and TLS/network failures; tests pass.

## Context
- Slice: stayed whole under one slice owner with one `aad-implementer` task.
- Task package: `docs/plans/2026-05-28-strict-required-health`.
- Worktree/branch: `docs-failover-service-plan`.
- Commit: `1be1ff6` (`Implement strict required health semantics`).

## Spec compliance
- All required URLs must pass: done in `internal/health/health.go`; tests cover one-required-failure and all-required-success cases.
- Any required failure triggers confirmation/failover: done via existing service path; `internal/service` test covers one required URL failing persistently while another passes.
- Diagnostic URLs non-decisive: done; health test covers diagnostic 302/non-OK while required URLs pass.
- 3xx/TLS/network docs: done; README/runbook state current `nettest.Get` only accepts 2xx, so redirects are not OK today; TLS/network/proxy failures on required URLs enter confirmation.

## Acceptance verification
- `go test ./internal/health ./internal/service`: passed.
- `go test ./...`: passed.
- Evidence file: `docs/plans/2026-05-28-strict-required-health/verification/local.md`.

## Issues
- R-01: Previous semantics allowed daemon healthy when any required URL passed. Resolved by requiring every required probe to be OK.
- Follow-ups: none required. If `nettest` redirect handling changes later, update tests/docs accordingly.

## Verdict
- Final slice done-state: complete and locally verified.
- System readiness: code/docs/tests ready for parent review; not deployed to VPS by request.
