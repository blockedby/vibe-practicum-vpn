# Vercel DNS + server failover implementation plan

Execution ledger status: planning complete for the next implementation task only. This package intentionally contains public-safe docs and no scripts, DNS changes, Vercel mutations, remote-host mutations, local-secret edits, rendered configs, generated profiles, or logs.

## Source predecessor and task intake

This is the DNS/Vercel follow-on after base `moscow-tiger` deploy readiness from `docs/plans/moscow-tiger-bootstrap-deploy-failover.md`. That predecessor explicitly leaves provider-specific Vercel DNS automation for the next task after `moscow-tiger` bootstrap/deploy verification exists.

Goal for the next implementation task:
- Add public-safe automation/docs/tests for controlled failover between existing primary node `vibe-practicum` and secondary node `moscow-tiger`.
- Support read-only Vercel DNS discovery and dry-run planning first.
- Rank endpoint health and speed, then put the faster healthy node first in the failover queue.
- Apply or roll back DNS only through guarded commands with expected-current checks and explicit `--yes`.
- Coordinate server deploy/rollback state with DNS movement.
- Run smoke tests after failover and rollback.

In scope:
- Public-safe scripts, dispatcher subcommands, tests/checks, env example placeholders, and docs/runbook updates.
- Real values loaded only from `config/private-endpoints.local.env` at operator runtime.
- Dry-run/read-only Vercel discovery that can run without mutating DNS.
- Guarded mutating paths designed for future operator-approved execution.

Out of scope / do-not-touch boundaries:
- No live Vercel/DNS mutation unless the future task is explicitly invoked with `--yes` and expected-current matches.
- No mutation of remote hosts during planning; future live server deploy/rollback requires private env and local/lab gates.
- No committed real endpoints/domains/tokens, private keys, generated OpenVPN profiles, rendered configs, subscription URLs, auth files, logs, snapshots, or image exports.
- Do not weaken the local Docker lab gate for runtime-affecting changes.

Done-state for the next implementation task:
- The failover command contract, public-safe env contract, tests, docs/runbook, dry-run, guarded apply/rollback, ranking, deploy/rollback coordination, and smoke evidence exist and pass their acceptance checks.

Blocking unknowns for future owner:
- Exact Vercel CLI/API record format available to the operator account.
- Exact private failover domain and record name; must stay in `config/private-endpoints.local.env` and be redacted from tracked evidence.
- Whether base `moscow-tiger` deploy scripts are already implemented when this task starts. If not, keep server coordination as dry-run/docs hooks and stop before live deploy.

## Repo orientation and reusable surfaces

Likely implementation surfaces:
- New or extended dispatcher script such as `scripts/failover.sh`, `scripts/vercel-dns-failover.sh`, or a subcommand in a future node dispatcher.
- `config/private-endpoints.example.env` with sanitized placeholders only.
- Shell tests or fixture-driven checks for parsing, guards, redaction, ranking, and dry-run/apply command selection.
- Runbook docs under `docs/` or this task package.

Reuse targets and patterns:
- `scripts/healthcheck.sh` for public-safe health probe style.
- `scripts/status.sh` for status aggregation conventions.
- `scripts/vpnkit-render-local-configs.sh` for loading env safely and refusing unsafe output paths.
- `scripts/vpnkit-copy-vps-secrets.sh` for private-secret path boundaries and redaction expectations.
- `docs/DOCKER_SETUP.md` for default local Docker lab validation before live runtime mutation.
- `docs/plans/moscow-tiger-bootstrap-deploy-failover.md` for server deploy/rollback, stop conditions, release layout, and DNS follow-on assumptions.

Missing pieces to add in the next implementation task:
- Public-safe env contract for primary/secondary endpoints, Vercel project/team/domain/record identifiers, expected-current record, TTL expectations, health probe URLs, and optional speed probe knobs.
- Read-only Vercel DNS discovery/dry-run command.
- Endpoint health/speed ranking logic with deterministic queue ordering and tie/failure handling.
- Guarded DNS apply and rollback commands with expected-current checks and explicit `--yes`.
- Server deploy/rollback coordination hooks and stop conditions.
- Post-failover smoke commands and public-safe evidence format.
- Tests/checks and runbook documentation.

## Acceptance criteria mapped to evidence

| AC | Criterion | Evidence expected |
| --- | --- | --- |
| AC1 | Tracked files remain public-safe and contain only placeholders for endpoints/domains/tokens. | Public-safety grep over changed files; `git diff --cached --check`; no private env/log/generated artifacts staged. |
| AC2 | Vercel discovery and DNS dry-run are read-only and print current state, proposed target, expected-current, TTL/metadata when available, and rollback target with redacted values. | Script tests/fixtures plus manual dry-run output sanitized in docs. |
| AC3 | Endpoint health and speed ranking selects only healthy endpoints and orders the failover queue with the faster healthy node first. | Unit/fixture tests for primary faster, secondary faster, both healthy tie, one unhealthy, both unhealthy. |
| AC4 | DNS apply requires explicit `--yes`, confirms the live current record equals expected-current before changing, and refuses on mismatch/missing env. | Negative tests for no `--yes`, missing expected-current, mismatched record, missing Vercel token/env; positive mocked apply test. |
| AC5 | DNS rollback uses the same guard model and verifies the current failed-over value before restoring the rollback target. | Negative/positive mocked rollback tests and documented rollback contract. |
| AC6 | Server deploy/rollback coordination prevents DNS failover when target server health/deploy readiness is unproven, and keeps old node available during observation. | Tests or dry-run fixtures for preflight gate failures plus runbook sequence evidence. |
| AC7 | Post-failover smoke tests cover DNS propagation, endpoint health, OpenVPN/client smoke, and rollback smoke without committing private outputs. | Script tests where practical plus documented manual evidence template with redaction rules. |
| AC8 | Final integration verification proves docs/scripts/tests are coherent and no mutation happened during planning/dry-run checks. | `git status --short`, `git diff --check`, `bash -n scripts/*.sh` for shell changes, targeted tests, and no-mutation ledger. |

## Plan task sequence

### Task 1: Env contract + read-only Vercel discovery/dry-run

Goal:
- Define the public-safe env contract and implement read-only Vercel DNS discovery/dry-run output.

Boundary:
- System area: script/env/docs.
- Primary verification: fixture or mocked CLI tests plus dry-run/manual evidence with placeholders.

Existing pattern / reuse:
- `config/private-endpoints.example.env` placeholder style.
- `scripts/vpnkit-render-local-configs.sh` env-loading/fail-closed style.

Missing change:
- Add sanitized variables such as `VPN_PUBLIC_DOMAIN=<VPN_PUBLIC_DOMAIN>`, `VPN_DNS_RECORD_NAME=<VPN_DNS_RECORD_NAME>`, `VIBE_PRACTICUM_PUBLIC_ENDPOINT=<VIBE_PRACTICUM_PUBLIC_ENDPOINT>`, `MOSCOW_TIGER_PUBLIC_ENDPOINT=<MOSCOW_TIGER_PUBLIC_ENDPOINT>`, and Vercel identifiers/tokens as placeholder-only examples.
- Implement `discover`/`plan`/`dry-run` command that reads current DNS, redacts values in tracked evidence, and never mutates.

Acceptance criteria:
- Missing env fails closed with no live DNS mutation.
- Dry-run prints current, expected, proposed target, TTL/metadata when available, and rollback target.
- No endpoint/token values are echoed in logs intended for commit.

Test plan:
- Positive: mocked Vercel record exists and matches expected-current.
- Negative: missing token/domain/record; malformed record; command invoked with apply intent but no `--yes`.
- Edge: multiple records, unsupported record type, Vercel CLI unavailable.
- Manual: operator may run read-only Vercel discovery and store only sanitized summary.

Dependencies:
- Depends on: none.
- Blocks: Tasks 3 and 5.
- Can run parallel with: Task 2 after env variable names settle.

Executor:
- `aad-implementer`.

### Task 2: Endpoint health/speed ranking and queue ordering

Goal:
- Rank `vibe-practicum` and `moscow-tiger` by health and speed so the faster healthy node is first in the failover queue.

Boundary:
- System area: script logic/tests.
- Primary verification: deterministic tests using mocked probe outputs.

Existing pattern / reuse:
- `scripts/healthcheck.sh` health probe style.
- Public/test health domains are allowed; private endpoints stay in local env.

Missing change:
- Health probes for both nodes, speed/latency timing, deterministic tie-breaker, unhealthy exclusion, and both-unhealthy stop condition.

Acceptance criteria:
- Healthy faster node sorts first whether it is primary or secondary.
- Unhealthy nodes do not become failover targets.
- Both-unhealthy state stops before DNS or server mutation.

Test plan:
- Positive: primary faster; secondary faster.
- Negative: one node fails health; both fail health.
- Edge: equal latency tie, timeout, transient probe failure, missing endpoint env.
- Manual: optional speed evidence template redacts actual endpoints.

Dependencies:
- Depends on: Task 1 env names.
- Blocks: Task 3 queue selection and Task 5 smoke docs.
- Can run parallel with: none until env names settle; then Task 1 docs/tests can proceed in parallel.

Executor:
- `aad-implementer`.

### Task 3: Guarded DNS apply and rollback

Goal:
- Implement mutating DNS failover/rollback commands that are impossible to run accidentally.

Boundary:
- System area: Vercel DNS script/tests.
- Primary verification: mocked CLI/API tests for guard behavior; live mutation only in future operator-approved manual run.

Existing pattern / reuse:
- Predecessor expected-current DNS cautions in `docs/plans/moscow-tiger-bootstrap-deploy-failover.md`.
- Repo public-safety rules for local env and redaction.

Missing change:
- `apply --yes` and `rollback --yes` flow that compares live current record to expected-current before writing, records rollback target, and rechecks after change.

Acceptance criteria:
- Refuses without explicit `--yes`.
- Refuses when live DNS value does not equal expected-current.
- Rollback refuses unless live value equals expected failed-over value.
- Mutating commands produce public-safe, redacted summaries.

Test plan:
- Positive: mocked apply success; mocked rollback success.
- Negative: no `--yes`, mismatch, missing expected-current, missing token, unsupported record type, Vercel CLI/API failure.
- Edge: TTL unavailable, duplicate records, propagation delay, API rate-limit.
- Manual: future live apply/rollback evidence is operator-approved and sanitized.

Dependencies:
- Depends on: Tasks 1 and 2.
- Blocks: Task 5 post-failover smoke and Task 6 final readiness.
- Can run parallel with: Task 4 after shared command contract settles.

Executor:
- `aad-implementer`.

### Task 4: Server deploy/rollback coordination contract

Goal:
- Ensure DNS failover does not outrun server readiness or rollback availability.

Boundary:
- System area: script orchestration/runbook.
- Primary verification: dry-run/tests for gate ordering and stop conditions.

Existing pattern / reuse:
- `docs/plans/moscow-tiger-bootstrap-deploy-failover.md` release layout, verify, rollback, and stop conditions.
- `scripts/status.sh` and future `moscow-tiger.sh verify/status/rollback` patterns.

Missing change:
- Coordination hooks: verify target node before DNS, keep old node unchanged, optional server rollback command/dry-run before DNS rollback, and stop on unproven deploy readiness.

Acceptance criteria:
- Failover plan refuses when target server health/deploy readiness is missing or failed.
- Rollback plan confirms old node health before DNS rollback.
- Runbook documents sequence: deploy/verify server, DNS dry-run, guarded DNS apply, smoke, observe, rollback if needed.

Test plan:
- Positive: target healthy and old node healthy.
- Negative: target unhealthy, old node unavailable for rollback, deploy status unknown.
- Edge: base `moscow-tiger` scripts absent; coordination remains documented/dry-run and stops before live mutation.
- Manual: operator-approved server coordination evidence after base implementation exists.

Dependencies:
- Depends on: predecessor base deploy readiness; can be implemented as guarded hooks if scripts exist or as dry-run contract if not.
- Blocks: Task 5 and Task 6.
- Can run parallel with: Task 3 after command contract settles.

Executor:
- `aad-implementer` or child slice owner if base server scripts are missing and this becomes a separate implementation effort.

### Task 5: Post-failover smoke/verification docs and tests

Goal:
- Define and automate where practical the smoke tests after DNS failover and rollback.

Boundary:
- System area: tests/docs/runbook.
- Primary verification: scripted dry-run/fixture smoke checks plus manual evidence template.

Existing pattern / reuse:
- `scripts/healthcheck.sh`, `scripts/status.sh`, Docker lab docs in `docs/DOCKER_SETUP.md`.

Missing change:
- Smoke checklist for DNS propagation, endpoint health, OpenVPN/client connectivity, routing health, and rollback smoke, with redaction rules.

Acceptance criteria:
- Smoke sequence runs after apply and after rollback.
- Evidence template stores only placeholders/sanitized summaries in tracked files.
- Failure paths direct operator to rollback contract and stop conditions.

Test plan:
- Positive: mocked propagation and health pass.
- Negative: DNS not propagated after TTL, OpenVPN health fails, client smoke fails.
- Edge: resolver cache lag, one probe domain unavailable, timeout handling.
- Manual: future live smoke evidence after operator-approved apply.

Dependencies:
- Depends on: Tasks 1-4.
- Blocks: Task 6 final integration.
- Can run parallel with: none.

Executor:
- `aad-implementer`.

### Task 6: Final integration and public-safety verification

Goal:
- Prove the implemented failover package is coherent, tested, and safe for public tracking.

Boundary:
- System area: whole slice integration.
- Primary verification: final local checks and acceptance matrix.

Existing pattern / reuse:
- Repo README local checks and public-safety AGENTS rules.

Missing change:
- Update plan/report artifacts, run all relevant checks, classify blockers/follow-ups, and prepare PR branch.

Acceptance criteria:
- All AC1-AC8 evidence is present or explicitly waived with risk.
- No secrets/private endpoints/generated artifacts are staged.
- DNS/remote mutation evidence, if any, is operator-approved and sanitized; otherwise no-mutation is documented.

Test plan:
- Positive: `git diff --check`, `bash -n scripts/*.sh`, targeted test suite for failover logic, public-safety grep, `git status --short`.
- Negative: public-safety check catches placeholder violations in staged docs/scripts.
- Edge: changed shell scripts with no test harness require explicit manual test evidence.
- Manual: if live apply is intentionally out of scope, record dry-run-only readiness and remaining live-run risk.

Dependencies:
- Depends on: Tasks 1-5.
- Blocks: PR finalization.
- Can run parallel with: none.

Executor:
- Slice owner with optional `aad-acceptance-auditor` for independent readiness audit.

## Dependency graph and delegation packets

Suggested execution waves for the next owner:
1. Wave A: Task 1 env/discovery. Settle command names and env contract.
2. Wave B: Task 2 ranking can start after Task 1 env names are stable.
3. Wave C: Tasks 3 and 4 can run in parallel after shared command contract and ranking outputs are known.
4. Wave D: Task 5 smoke/verification docs/tests after apply/coordination contract exists.
5. Wave E: Task 6 final integration and acceptance audit.

Suggested implementer routing packet template:
- Task name: Vercel DNS + server failover, Task `<N>`.
- Task package: `docs/plans/2026-06-02-vercel-dns-server-failover/`.
- Read first: `plan.md`, `docs/plans/moscow-tiger-bootstrap-deploy-failover.md`, `AGENTS.md`, nearest child `AGENTS.md`, and relevant scripts listed in the task.
- Boundaries: keep real endpoints/tokens/domains in `config/private-endpoints.local.env`; do not print or commit concrete private values; no live DNS or host mutation unless the task specifically reaches guarded future apply with explicit `--yes`; dry-run by default.
- Report path: `docs/plans/2026-06-02-vercel-dns-server-failover/reports/aad-implementer-task-<N>.md`.
- Progress path: `docs/plans/2026-06-02-vercel-dns-server-failover/progress/aad-implementer-task-<N>.md`.
- Expected output: files changed, acceptance evidence, verification commands/results, issue IDs, rollback/stop-condition notes.

## Stop conditions and rollback contract

Stop immediately before DNS or server mutation when:
- `config/private-endpoints.local.env` is absent or missing required values for a live operation.
- Vercel auth/project/domain/record discovery fails or returns ambiguous/multiple unsupported records.
- Live current DNS value does not match the expected-current value supplied by the operator.
- Endpoint health/ranking finds no healthy target, or the target server deploy/health state is unproven.
- `--yes` is absent for a mutating command.
- Any command would write generated profiles, rendered configs, logs, snapshots, tokens, or private endpoints into tracked paths.
- Smoke tests fail after failover and rollback target health is not proven.

Rollback contract:
- DNS rollback is a first-class guarded command, not an ad-hoc UI step: it requires explicit `--yes`, expected-current equal to the failed-over endpoint, and a known rollback target.
- Server rollback is coordinated before/with DNS rollback using the predecessor release layout: preserve current and previous releases, switch back only to a known-good target, restart/reload, and run post-rollback health.
- Keep the old active node unchanged during the observation window so rollback remains possible.
- Rollback evidence must be sanitized; do not commit resolver output containing private domains or endpoint values.

## Current planning-slice ledger

- 2026-06-02: Created task package for the next implementation task only.
- 2026-06-02: Wrote plan with predecessor linkage, boundaries, reusable surfaces, task sequence, test matrix, acceptance criteria, stop conditions, and rollback contract.
- 2026-06-02: No DNS, Vercel, remote host, local secret, rendered config, generated profile, or artifact mutation performed.

## Implementation-slice ledger update

- 2026-06-02: Implemented public-safe failover automation in `scripts/vercel-dns-failover.sh`, sanitized env contract updates in `config/private-endpoints.example.env`, shell regression tests in `tests/vercel-dns-failover-test.sh`, and runbook docs in `docs/VERCEL_DNS_FAILOVER.md` with README link.
- 2026-06-02: Verification recorded at `verification/implementation-local.md`: targeted shell tests, `bash -n scripts/*.sh`, `git diff --check`, `go test ./...`, and public-safety grep all passed.
- 2026-06-02: No live DNS/Vercel/remote-host/production-`vpnkit` mutation was run; apply/rollback evidence used dry-run/mock paths only.
