# Issue #27 Steam Deck test-lab lifecycle runner plan

## Root task

Implement GitHub issue #27: a public-safe Steam Deck test/lab lifecycle runner that can prepare, deploy, verify, and tear down isolated `vpnkit` lab containers using production-like tracked templates/settings while keeping private host bindings and generated artifacts local/gitignored.

## Scope and boundaries

In scope:
- Create and document the new public-safe GitHub issue (#27) and link it to issue #24 / PR #26.
- Add a user-facing lifecycle command, preferably `test/containers-test.sh --scenario steamdeck-host --action up|test|down|cycle`, with a maintainable backend script if useful.
- Generate isolated scenario test PKI, server config, sing-box config, and host-machine client `.ovpn` under a gitignored `secrets/vpnkit-labs/<scenario>/...` layout.
- Use production-like tracked OpenVPN and sing-box templates/rule sets, preserving smart routing policy shape: adblock `block-out`, dev/package `direct-out`, RU direct, final `selected-native-out`.
- Deploy/test/down an isolated Steam Deck lab container via Podman using distinct container/image/remote-dir/port defaults.
- Make Steam Deck podman routing mode configurable and default lab to `tun`; avoid hardcoded `redirect` for full-tunnel acceptance checks.
- Parameterize config requirements so disabled `vibe-vpn` daemon paths do not require production subscription/config for lab checks.
- Keep `test/containers-test.sh` honest: explicit selected scenario prerequisite misses are clear FAIL diagnostics; scaffold/TODO checks must not count as green acceptance.
- Update public-safe docs/templates and task package evidence.

Out of scope / do-not-touch:
- Do not mutate, remove, recreate, or adopt the default/prod `vpnkit` container.
- Do not run production deploy/rollback or production endpoint mutation.
- Do not commit or print secrets, private endpoints, generated profiles, PEM/key/cert contents, rendered private configs, or sensitive logs.
- Do not store real Deck host/IP/SSH alias values in tracked files. Use `config/private-endpoints.local.env` and gitignored scenario files only.
- Do not claim production readiness from Deck lab evidence.

## Acceptance criteria

AC1 A new documented scenario lifecycle command exists for `steamdeck-host` with `up`, `test`, `down`, and `cycle` actions.
AC2 Steam Deck lab deploy uses isolated container/image/port/remote-state names and does not touch a default/prod `vpnkit` container.
AC3 Generated lab artifacts and real profiles/certs/configs are gitignored under a documented local layout; tracked docs/templates are public-safe.
AC4 Lab generation uses isolated test PKI and production-like OpenVPN/sing-box templates/rules for smart-routing behavior.
AC5 Lab `tun` mode is configurable and compatible with checks expecting `sb-tun0`.
AC6 Disabled `vibe-vpn` daemon paths do not require production subscription/config.
AC7 Missing explicit scenario prerequisites produce clear FAIL diagnostics.
AC8 The matrix distinguishes implemented PASS/FAIL checks from unsupported/not-accepted scaffolds.
AC9 Safe repo checks pass (`bash -n`, Python compile/checks, manifest/schema tests, sing-box routing proof, Go test/vet/build as relevant).
AC10 A live Deck lab cycle is run when authorized and safe; final readiness is not claimed unless the intended lifecycle cycle is green or the remaining blocker is precisely classified as environment/private data/network.
AC11 PR #26 is updated with commits and issue #27 context.

## Slice structure

Single implementation slice is cheapest: the lifecycle runner, scenario generation, Steam Deck Podman wiring, harness matrix, and docs share one user-facing command and one integration verification story. Splitting by file area would create contract churn around the command flags and scenario layout.

### Slice L1: Steam Deck test-lab lifecycle runner

Goal:
- Implement issue #27 end-to-end for one explicit `steamdeck-host` scenario lifecycle, preserving existing read-only/default harness behavior where practical.

Boundary:
- System area: shell lifecycle tooling, test harness, public-safe docs/templates, task evidence.
- Primary verification: safe repo checks plus live `test/containers-test.sh --scenario steamdeck-host --action cycle` (or documented equivalent) when private Deck bindings are available and safe.

Existing pattern / reuse:
- `test/containers-test.sh` as unified runner.
- `scripts/vpnkit-steamdeck-podman.sh` for Deck Podman sync/build/run/check/down behavior.
- `scripts/vpnkit-render-local-configs.sh` plus tracked OpenVPN/sing-box templates/rule sets for production-like rendering.
- `config/private-endpoints.example.env` / `config/private-endpoints.local.env` public/private split.
- Existing issue #24 manifest/profile docs and smart-routing proof.

Missing change:
- Add lifecycle action/scenario parsing and backend orchestration.
- Add/finish lab setup generation into `secrets/vpnkit-labs/<scenario>/...` with real test cert/profile material and no content stdout.
- Add public-safe scenario env template/docs.
- Harden isolated defaults and production-container refusal.
- Make routing mode/config requirement behavior match lab `tun` acceptance.
- Make explicit scenario prerequisite failures clear and matrix claims honest.

Likely files:
- `test/containers-test.sh`
- `scripts/vpnkit-steamdeck-podman.sh`
- New or existing backend such as `scripts/vpnkit-test-lab-setup.sh` / `scripts/vpnkit-lab.sh`
- `.gitignore`
- `config/private-endpoints.example.env`
- `README.md`, possibly `docs/DOCKER_SETUP.md`
- Task package reports/verification files

Test plan:
- `bash -n scripts/*.sh test/*.sh`
- `python3 -m py_compile scripts/*.py test/*.py` where relevant
- Manifest/schema/profile checks from issue #24 README for `steamdeck`/`host-machine` test intent
- `python3 test/sing-box-smart-routing-proof.py`
- `go test ./...`, `go vet ./...`, `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`
- `git ls-files`/`git status --ignored` checks proving no tracked `.ovpn`, PEM/key/cert/log/private artifacts
- Live Deck lab: source `config/private-endpoints.local.env` if present, then run `test/containers-test.sh --scenario steamdeck-host --action cycle` or documented equivalent without printing private values.

Evidence route:
- PASS requires safe repo checks plus a green live lifecycle cycle for intended scope.
- If live cycle cannot be green due to private environment/network/host data rather than script defects, classify the blocker precisely and do not claim full done.
- PR update evidence: pushed commit(s) and PR #26 comment/body update linking issue #27.

Dependencies:
- Depends on: current branch state from PR #26; private Deck bindings only for live verification.
- Blocks: root final verification and done-state.

Executor:
- `aad-slice-owner` with report at `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/reports/slice-owner-lifecycle.md` and progress at `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/progress/slice-owner.md`.

## Execution ledger

- 2026-06-09: New public-safe GitHub issue created: https://github.com/blockedby/vibe-practicum-vpn/issues/27.
- 2026-06-09: Root task package and implementation plan created in this directory.
- 2026-06-09: Root live cycle attempt timed out after 1800s. Follow-up remediation scope added: reject documented placeholder SSH/endpoint values for explicit `steamdeck-host`, derive SSH target from `VPNKIT_TEST_SSH_TARGET` -> `VPNKIT_STEAMDECK_SSH_TARGET` -> `VPNKIT_STEAMDECK_SSH_HOST` -> `deck` while treating placeholders as invalid for explicit scenario, require non-placeholder endpoint from `VPNKIT_TEST_ENDPOINT` or `VPNKIT_STEAMDECK_LAN_ENDPOINT`, add configurable bounded timeouts around remote deploy/verify/smoke/SSH operations, update docs/templates, and record live status without leaking private values.
- 2026-06-09: Live remediation implemented and locally verified. Evidence: `verification/live-remediation.md`; report: `reports/slice-owner-live-remediation.md`. Placeholder negative check now fails fast before deploy. Live Deck cycle not rerun because `config/private-endpoints.local.env` is absent in this worktree; U-01 remains external/private env blocker.

### Live remediation task: placeholder prerequisites and bounded remote timeouts

Goal:
- Make `test/containers-test.sh --scenario steamdeck-host --action cycle` fail fast on documented placeholder values and fail boundedly with clear diagnostics around remote operations instead of hanging for the root-level 30 minute timeout.

Boundary:
- System area: shell harness/lifecycle scripts and public-safe docs/templates.
- Primary verification: syntax checks plus placeholder-only negative scenario exits nonzero quickly with a clear redacted `FAIL`; bounded live cycle only if real non-placeholder private Deck env is available and safe.

Existing pattern / reuse:
- `test/containers-test.sh` result recording/redaction and lifecycle functions.
- `scripts/vpnkit-steamdeck-podman.sh` deploy/cleanup behavior.
- `config/private-endpoints.example.env` / `config/private-endpoints.local.env` public/private split.

Missing change:
- Add placeholder detection for target-like and endpoint-like vars (`your-*`, `*.invalid`, `192.0.2.*`, `203.0.113.*`) before logging `ssh_target`/`endpoint_set` as usable for explicit Steam Deck scenario.
- Implement SSH target precedence including `VPNKIT_STEAMDECK_SSH_HOST` fallback before `deck`, rejecting placeholder-selected values for explicit scenario.
- Wrap remote deploy/verify operations (`podman build`, `podman run`, `podman logs`, `podman exec sing-box check`, client smoke, SSH probes) in configurable timeout knobs where practical, preserving redaction and clear FAIL/SKIP diagnostics.
- Update README/env template with precedence and timeout knobs.

Acceptance criteria:
- `bash -n scripts/*.sh test/*.sh` passes.
- Placeholder Steam Deck env values exit nonzero quickly with clear `FAIL` diagnostic and do not proceed to deploy or print private values.
- Timeout knobs are documented and used by relevant remote operations.
- Live cycle is rerun only if real private values are available; otherwise remaining live acceptance is classified as `U-*` environment/private Deck data blocker.

Test plan:
- Positive/static: `bash -n scripts/*.sh test/*.sh`.
- Negative: run explicit steamdeck-host action with placeholder env values and short log path; assert nonzero, clear `FAIL`, no generated secrets/log secrets committed.
- Optional live: source gitignored private endpoints locally; if sanitized state has non-placeholder SSH target and endpoint, run bounded `test/containers-test.sh --scenario steamdeck-host --action cycle` with safe isolated names; otherwise record blocker.

Dependencies:
- Depends on prior lifecycle implementation commit `f789c4b`.
- Blocks root live acceptance retry.
- Executor: `aad-implementer` with report `reports/aad-implementer-live-remediation.md`, progress `progress/aad-implementer-live-remediation.md`, verification `verification/live-remediation.md`.
