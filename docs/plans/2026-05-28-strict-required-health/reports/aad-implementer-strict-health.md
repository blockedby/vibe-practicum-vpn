PI_RESULT: PASS
TASK: T1 — strict health implementation/docs/tests
TASK_PACKAGE: docs/plans/2026-05-28-strict-required-health
REPORT_PATH: docs/plans/2026-05-28-strict-required-health/reports/aad-implementer-strict-health.md
PROGRESS_PATH: docs/plans/2026-05-28-strict-required-health/progress/aad-implementer-strict-health.md
COMMITS:
- 604658b: Implement strict required health semantics
FILES_CHANGED:
- internal/health/health.go: changed failover decision to require every required probe to be OK; any required non-OK sets FailoverNeeded.
- internal/health/health_test.go: updated runner tests for any-required-failure behavior and diagnostic synthetic 302/non-OK non-decisive behavior.
- internal/service/service_test.go: added service-level progressive confirmation/failover coverage when one required URL keeps failing while another passes.
- docs/FAILOVER_SERVICE_RUNBOOK.md: documented all-required semantics, diagnostic non-decisive semantics, current 3xx handling, and TLS/network failure impact.
- README.md: added concise health behavior summary for required/diagnostic URLs and current probe status handling.
- docs/plans/2026-05-28-strict-required-health/progress/aad-implementer-strict-health.md: recorded implementation progress and verification evidence.
AC_VERIFICATION:
- AC1 two required URLs, one OK and one failed yields FailoverNeeded=true: `TestRunnerFailoverNeedsEveryRequiredURL`; RED failed before production change, then passed in `go test ./internal/health ./internal/service` — passed.
- AC2 diagnostic failures, including synthetic 302/non-OK, never decide failover by themselves: `TestRunnerParallelAndDiagnosticNotDecisive` returns diagnostic StatusCode 302/OK false while required URLs pass and asserts FailoverNeeded=false — passed.
- AC3 service progressive confirmation/failover is reached when any required URL keeps failing: `TestCheckHealthProgressiveConfirmationTriggersFailoverAfterOnePersistentRequiredFailure` expects initial + 3 confirmation batches and one failover call with one persistent required failure — passed.
- AC4 docs explain all-required semantics, diagnostic non-decisive semantics, current 3xx handling, TLS/network failure impact: runbook and README updated with those statements — passed by documentation inspection.
TESTS_RUN:
- `go test ./internal/health ./internal/service` before production change: failed as expected for RED (`TestRunnerFailoverNeedsEveryRequiredURL`; service one-required-failure confirmation test only made initial probe batch).
- `go test ./internal/health ./internal/service`: passed.
- `go test ./...`: passed.
QUALITY_CHECKS:
- `gofmt -w internal/health/health.go internal/health/health_test.go internal/service/service_test.go`: passed/applied formatting.
- `git diff --check`: passed.
QUALITY_NOTES:
- Readability/reuse: reused existing `health.Runner` parallel probe pattern and service `checkHealth` progressive confirmation flow; no new abstraction needed.
- Error handling/logging: preserved existing probe errors/result shape and service logging behavior.
- Backend/API/data: config contract and public data shapes unchanged; only health decision semantics changed within existing runner/service layers.
- Frontend/UI: not relevant.
- DevOps/runtime: docs only; no deployment, systemd, SSH/SCP, or runtime config mutation performed.
- Security: no secrets touched or logged; no auth/validation weakening.
- Concurrency/idempotency: retained existing parallel probe synchronization and failover confirmation retry behavior; no new writes or migrations.
- Compatibility/performance: same number of probes as before; stricter decision behavior is the intended compatibility-impacting semantic change.
SIDE_FINDINGS:
- Blocking: none.
- Non-blocking follow-up candidates: if `nettest.Get` later changes redirect handling, update health docs/tests to match the new 3xx contract.
NOTES: Implementation evidence only; owner/auditor retains acceptance decision.
