# Strict required health semantics plan

## Task intake
- Goal: make daemon health semantics strict after VPS smoke: all `health.required_urls` must pass. Any required URL failure sets `FailoverNeeded=true` and therefore enters the existing progressive confirmation loop.
- In scope: `internal/health` decision rule/tests; service tests proving one required failure triggers confirmation/failover and recovery requires all required passing; concise docs/runbook explanation of required vs diagnostic URLs, HTTP 3xx behavior, and TLS/network failures.
- Out of scope: VPS deployment/systemd mutation, changing diagnostic URLs into failover signals, broad refactors.
- Done state: unit tests and docs reflect strict all-required behavior; targeted Go tests pass.
- Blocking unknowns: nettest actual 3xx behavior must be checked in code before docs wording.

## Repo orientation
- Guidance: README says local checks are `go test ./...`; do not run VPS/systemd mutating commands unless intentionally operating on VPS.
- Likely areas: `internal/health/health.go`, `internal/health/health_test.go`, `internal/service/service_test.go`, `docs/FAILOVER_SERVICE_RUNBOOK.md`, possibly README/config examples comments.
- Verification commands: `go test ./internal/health ./internal/service` (required), `go test ./...` if feasible.

## Reuse discovery
- Health runner already probes required and diagnostic URLs in parallel with injectable `ProbeFunc`.
- Service `checkHealth` already triggers progressive confirmation when `health.Result.FailoverNeeded` is true.
- `nettest.Get` currently treats non-2xx as an error before returning a successful result, so current 3xx (including ya.ru 302) is not OK under DefaultProbe; diagnostic 3xx remains non-decisive.
- Existing docs/runbook already describe daemon modes and health config.

## Missing pieces
- Change health decision from "any required OK is healthy" to "every required URL must be OK".
- Rename/update health tests that currently assert one successful required URL avoids failover.
- Add service-level test showing mixed required results still drive progressive confirmation/failover.
- Docs/runbook must explicitly state diagnostics are observation-only, required URL TLS/network failures trigger confirmation, and current nettest only counts 2xx as reachability OK; 3xx is reported as diagnostic/reachability clue but not OK unless nettest behavior is later changed.

## Plan task T1 — strict health implementation/docs/tests
- Acceptance criteria:
  1. With two required URLs, one OK and one failed yields `FailoverNeeded=true`.
  2. Diagnostic URL failures, including synthetic 302/non-OK, never decide failover by themselves.
  3. Service progressive confirmation/failover is reached when any required URL keeps failing.
  4. Docs explain all-required semantics; diagnostic non-decisive semantics; current 3xx handling; TLS/network failure impact.
- Test plan: `go test ./internal/health ./internal/service`; run `go test ./...` if feasible.
- Depends on: none.
- Executor: `aad-implementer`.
- Report path: `docs/plans/2026-05-28-strict-required-health/reports/aad-implementer-strict-health.md`.

## Dependency graph
- Keep slice whole; one implementation task T1, then owner final verification/report.

## Execution ledger
- 2026-05-28: Plan created. Pre-dispatch gate satisfied: task intake, repo orientation, reuse, missing pieces, task acceptance, and dependency graph are recorded.
- 2026-05-28: Implementer completed T1 in commit `1be1ff6` after owner amend of post-commit report/progress evidence. Fresh owner verification passed: `go test ./internal/health ./internal/service` and `go test ./...`. Evidence: `verification/local.md`.
