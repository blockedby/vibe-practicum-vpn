# Issue #24 smart routing + manifest/profile matrix implementation plan

## Root task

Implement repository-scoped work for GitHub issue #24: smart vpnkit routing with adblock and direct developer/package infrastructure, plus the YAML manifest + JSON Schema foundation for topology/config/profile generation.

## Scope and boundaries

In scope:
- Public tracked manifest/schema example and schema for servers, clients, pairs, capabilities, profile/config inputs, and local binding references.
- Repo-local validator/resolver CLI using Python YAML + JSON Schema validation with clear dependency errors and sanitized resolved-pair JSON.
- Pair-specific OpenVPN profile rendering CLI with public-safe fixture/test mode and real-mode diagnostics that do not print secrets.
- `test/containers-test.sh` integration so selected manifest pairs validate, resolve, render, then enter the existing client smoke path.
- Smart routing/adblock/dev-direct sing-box template/rendering and local route-decision proof harnesses, preserving full-tunnel semantics and existing RU/direct/final behavior.
- Public-safe docs and this task package.

Out of scope:
- No production/Steam Deck/live mutation without explicit approval.
- Do not read `config/private-endpoints.local.env` unless a bounded verification step strictly requires it; current plan does not require it.
- No UI/control-panel changes.
- No generated profiles, rendered configs, logs, private endpoints, PEM/key material, or private values in tracked files or task reports.

## Acceptance criteria

AC1 Manifest/schema contract exists and validates a public example while keeping real/local/private/generated artifacts ignored.
AC2 Validator/resolver CLI validates schema plus semantic pair/capability/binding contracts and emits sanitized JSON for `--server steamdeck --client host-machine`.
AC3 Pair profile renderer creates pair-specific `.ovpn` artifacts under ignored output with safe permissions and no secret/profile stdout; supports public-safe fixtures/test mode and clear real-mode diagnostics.
AC4 `test/containers-test.sh` selected manifest-pair path runs validate -> resolve -> render -> existing client smoke/profile path, distinguishing selected-pair prerequisite failures from planned SKIP rows.
AC5 sing-box config/templates implement narrow adblock and dev-direct route sets/rules, preserve OpenVPN full-tunnel model, RU direct, final `selected-native-out`, MTU/MSS and existing native behavior.
AC6 Local route-decision proof tests/harness cover adblock -> block, dev/package -> direct, RU direct stays direct, ordinary foreign -> selected-native-out, and remote rule-set failure/cache behavior as feasible without live production.
AC7 Public docs/runbook explain manifest/profile matrix and smart routing safely with placeholders only.
AC8 Fresh verification includes unit/shell/schema tests, `bash -n`, and safe local tests; live/prod acceptance remains explicitly unclaimed unless later approved.

## Slice structure

Two implementation slices preserve ownership and reduce conflict:

### Slice A: manifest/schema, resolver, profile renderer, matrix integration
- Owns AC1-AC4 and manifest/profile docs.
- Likely files: `config/vpnkit-manifest.schema.json`, `config/vpnkit-manifest.example.yaml`, optional local example, `.gitignore`, `scripts/vpnkit/vpnkit-manifest-validate.py`, `scripts/vpnkit-resolve-profile-pair.sh`, `scripts/vpnkit/vpnkit-render-profile-for-pair.sh`, `test/containers-test.sh`, focused fixtures/tests/docs.
- Must not touch smart routing sing-box policy except if needed for docs cross-links.
- Report: `reports/slice-a-manifest-profile-matrix.md`.

### Slice B: smart routing/adblock/dev-direct sing-box policy and route-decision proofs
- Owns AC5-AC6 and smart-routing docs.
- Likely files: sing-box templates/rendering under `config/`, `scripts/vpnkit/vpnkit-render-local-configs.sh`, route-set files under `config/sing-box/rule-sets/`, test harness route-decision proofs, docs.
- Must preserve full-tunnel final `selected-native-out`, existing RU direct behavior, OpenVPN pushes/tun MTU/MSS, and not broaden direct routing beyond conservative dev/package list.
- Report: `reports/slice-b-smart-routing.md`.

### Integration/final verification
- Integrate slice outputs in the root worktree, resolve overlap in docs/test harness, run final verification, optionally acceptance audit, then final report.
- Report: `final-report.md`.

## Execution ledger

- 2026-06-09: Root worktree created at `.worktrees/issue-24-smart-routing-manifest` on branch `feat/issue-24-smart-routing-manifest` from `main`.
- 2026-06-09: Root package and slice plan created. Slice A and B ready for delegation.

## Slice B execution detail — smart routing/adblock/dev-direct

Status: running in child worktree `.worktrees/issue-24-smart-routing-slice` on branch `feat/issue-24-smart-routing-slice`.

### Task B1: sing-box smart-routing policy and route-decision proof harness

Goal:
- Implement narrow adblock and conservative developer/package infrastructure direct routing in sing-box templates/rendering with local, repo-safe route-decision proofs.

Boundary:
- System area: sing-box templates/config rendering and local test harness only.
- Primary verification: repo-local shell/Python tests that parse rendered/template configs and prove expected rule order/decisions without live production mutation.

Existing pattern / reuse:
- Reuse `config/sing-box/config.json.template`, `config/sing-box/config.tun.json.template`, `scripts/vpnkit/vpnkit-render-local-configs.sh`, existing RU `rule_set` route structure, existing `block-out`, `direct-out`, and final `selected-native-out` outbounds.
- Preserve OpenVPN server template `redirect-gateway`, `tun-mtu 1400`, and `mssfix 1360` by not editing them unless verification demands it.

Missing change:
- Add dedicated local rule-set files/templates for adblock and dev/package domains, not huge inline lists.
- Wire templates so adblock resolves to `block-out`, dev/package infrastructure resolves to `direct-out`, RU rule sets still resolve to `direct-out`, and ordinary foreign domains fall through to `selected-native-out`.
- Add deterministic local route-decision proof tests for sample domains and rule-set metadata/download/cache failure behavior feasible without network/live services.

Scope / likely files:
- `config/sing-box/` templates and rule-set files.
- `scripts/vpnkit/vpnkit-render-local-configs.sh` only if rendering must copy/include rule sets.
- `test/` or `scripts/` local proof harness/tests.
- `docs/` smart-routing notes only if needed for AC7 cross-reference; do not touch Slice A manifest/profile CLIs.

Acceptance criteria:
- AC5: templates implement narrow adblock + dev-direct rules, keep full-tunnel final `selected-native-out`, RU direct behavior, DNS hijack/sniff order, existing native behavior, and do not change OpenVPN MTU/MSS/pushes.
- AC6: local proof covers adblock sample domains -> `block-out`; dev/package sample domains -> `direct-out`; RU direct remains direct; ordinary foreign traffic -> `selected-native-out`; remote rule-set download/caching/failure behavior is covered by config-level proof or documented limited claim.

Evidence route:
- Existing automated checks first: `bash -n scripts/*.sh`; JSON/template parse or focused proof harness added by this task; any existing repo tests relevant to changed scripts.
- Bounded acceptance probe: local tests only; no live Deck/prod mutation and no private endpoint file reads.
- Access/runtime needed: Python/shell only; no secrets.
- Outcome boundary: PASS proves tracked template/render/test policy shape and deterministic route decisions for fixtures; it does not prove live sing-box download/runtime behavior in production.

Test plan:
- Positive: prove adblock/dev/RU/foreign sample decisions and JSON/template structure.
- Negative/edge: prove unknown foreign defaults to final selected native; prove remote RU rule sets have direct download detour and cache/failure-safe metadata where sing-box supports it, or record limited claim.
- Shell: `bash -n scripts/*.sh test/*.sh` for touched/new shell files.

Dependencies:
- Depends on: root Slice B dispatch only.
- Blocks: root integration/final verification.
- Can run parallel with: Slice A as long as manifest/profile CLIs are not touched.

Executor:
- `aad-implementer` with progress at `progress/aad-implementer-b1.md` and report at `reports/aad-implementer-b1-smart-routing.md`.

## Root integration ledger

- 2026-06-09: Slice B was integrated by cherry-picking local commit `4825d00` into root branch as `345d91b`.
- 2026-06-09: Slice A changes were copied into the root worktree after remediation for explicit client identity fields and real `jsonschema` dependency behavior.
- 2026-06-09: Root tightened the dev-direct rule set to include the conservative issue #24 candidate domains and updated route-decision proof samples.
- 2026-06-09: Root changed fixture profile material to non-PEM placeholder strings to avoid committing any key/certificate-shaped material while keeping OpenVPN profile section shape for harness handoff.
- 2026-06-09: README runbook added for manifest/profile matrix and smart-routing local proof commands.
- 2026-06-09: Final local verification recorded in `verification/local.md`; acceptance auditor updated verdict to accepted with limitations for repo-local scope.

## Final integrated status

- Slice A (AC1-AC4): complete for repo-local scope. Positive manifest/schema/resolve/render/harness checks pass in a disposable venv with public PyYAML/jsonschema installed; system Python without `jsonschema` fails with clear dependency guidance as required.
- Slice B (AC5-AC6): complete for repo-local scope. Smart route policy is wired into both sing-box templates, rule sets are copied during render, and route-decision proof passes.
- Docs/runbook (AC7): complete in `README.md` and task package.
- Verification (AC8): complete for repo-local scope; live/prod acceptance remains unclaimed and requires explicit operator approval/private inputs.

## Follow-up ledger — Deck test policy and production/test profile intents

Status: complete for repo-local/public-safe scope in the existing root worktree.

### Task F1: Deck test-scope semantics and profile intent split

Goal:
- Record the user's policy clarification that a Steam Deck server host is a test/lab environment, not production, so production approval gates do not apply to Deck test-host use.
- Add manifest/profile definitions and CLI/test selection behavior for distinct `test` and `production` profile intents for the same server/client pair, with test as the default harness intent and production explicit.

Scope / do-not-touch boundaries:
- In scope: public-safe repo docs/runbook, manifest schema/example, manifest validator/resolver, profile renderer, container test harness, task package evidence.
- Out of scope: live Deck mutation, production mutation, reading/printing `.ovpn` contents, committing generated profiles/logs/private endpoint values. Steam Deck runtime remains Podman-only when a live Deck is intentionally used.

Repo orientation / reuse:
- Existing tracked public manifest: `config/vpnkit-manifest.example.yaml`.
- Existing schema: `config/vpnkit-manifest.schema.json`.
- Existing resolver: `scripts/vpnkit/vpnkit-manifest-validate.py` emits sanitized pair JSON.
- Existing renderer: `scripts/vpnkit/vpnkit-render-profile-for-pair.sh`, default output `generated/openvpn-profiles`.
- Existing selected-pair harness: `test/containers-test.sh` with `VPNKIT_TEST_MANIFEST_*` variables.
- Existing ignored generated profile location: `generated/openvpn-profiles/` from `.gitignore`; real ad-hoc scripts may also use operator-supplied ignored paths, but manifest renderer defaults here and should remain secret-safe.

Missing pieces:
- Policy docs must distinguish Deck test/lab from production while preserving public-safety and no-live-mutation boundaries.
- Manifest schema/example need a profile intent dimension (`test` default, `production` explicit) without committing real profiles.
- Resolver/renderer/harness need intent selection so the same server/client pair can resolve production vs test profile definitions; selected-pair tests default to `test`.

Acceptance criteria:
- Docs state Deck server host is test/lab, not production; no production approval gate applies to Deck tests, but public-safety, Podman-only Deck runtime, and explicit live-action boundaries remain.
- Manifest has separate production and test profile definitions for the selected Steam Deck/host-machine pair, or equivalent intent-discriminated entries.
- Resolver and renderer can select `--profile-intent test` and `--profile-intent production`; ambiguous pair resolution is avoided.
- `test/containers-test.sh` defaults selected manifest-pair profile intent to `test`; production is only used when explicitly requested by env.
- No generated `.ovpn`, secrets, endpoints, logs, or profile contents are printed/committed.

Test plan:
- `bash -n scripts/vpnkit/vpnkit-render-profile-for-pair.sh test/containers-test.sh`
- Manifest schema/semantic validation for the example.
- Resolver positive checks for `--profile-intent test` and `--profile-intent production` returning sanitized JSON with distinct intents.
- Renderer fixture check for test intent into ignored `generated/openvpn-profiles` with mode `600` and no secret stdout.
- Harness check with selected manifest pair and default intent proves it chooses `test`; no live endpoint mutation.

Dependencies:
- Depends on: existing issue #24 root branch state.
- Blocks: final follow-up report.
- Executor: `aad-implementer` (single scoped task); owner verifies and reports.

Implementation evidence:
- 2026-06-09: F1 added `test` and `production` profile intents for the selected `steamdeck`/`host-machine` manifest pair, resolver/renderer `--profile-intent` selection, harness default `VPNKIT_TEST_MANIFEST_PROFILE_INTENT=test`, and Deck test/lab docs semantics. See `verification/profile-intents.md` and `reports/aad-implementer-f1-profile-intents.md`.
- 2026-06-09: Owner reran targeted verification: shell syntax, resolver `test`/`production`, `test/manifest-profile-intents-test.sh`, non-live selected-pair harness defaulting to `intent=test`, `git diff --check`, and `git ls-files '*.ovpn'`. Final follow-up report: `reports/slice-owner-f1-final.md`.
