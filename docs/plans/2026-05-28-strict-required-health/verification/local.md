# Local verification — strict required health

Fresh owner verification after implementer commit amend (`1be1ff6`).

- `go test ./internal/health ./internal/service` — PASSED
  - Evidence: packages `internal/health` and `internal/service` reported `ok`.
- `go test ./...` — PASSED
  - Evidence: all repository packages reported `ok` or `[no test files]`.

Acceptance mapping:
- All required URLs must pass; any required failure sets `FailoverNeeded=true`: covered by `internal/health` tests.
- Diagnostic URLs non-decisive: covered by `internal/health` diagnostic 302/non-OK test.
- Any required failure triggers progressive confirmation/failover path: covered by `internal/service` persistent one-required-failure test.
- Docs explain required/diagnostic/3xx/TLS-network semantics: covered by `README.md` and `docs/FAILOVER_SERVICE_RUNBOOK.md` inspection.
