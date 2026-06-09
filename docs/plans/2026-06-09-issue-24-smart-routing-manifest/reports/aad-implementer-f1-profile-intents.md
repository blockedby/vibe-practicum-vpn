PI_RESULT: PASS
TASK: Issue #24 Deck test policy + production/test profile intents (F1)
TASK_PACKAGE: docs/plans/2026-06-09-issue-24-smart-routing-manifest
REPORT_PATH: docs/plans/2026-06-09-issue-24-smart-routing-manifest/reports/aad-implementer-f1-profile-intents.md
PROGRESS_PATH: docs/plans/2026-06-09-issue-24-smart-routing-manifest/progress/aad-implementer-f1.md
COMMITS:
- 0694efd: feat: add profile intent split for manifest pairs
FILES_CHANGED:
- AGENTS.md: records Steam Deck server-host use as test/lab, not production, while preserving Podman-only and explicit live-action boundaries.
- README.md: documents test/production profile intents, Deck test/lab policy, default selected-pair intent, and explicit production intent usage.
- config/private-endpoints.example.env: adds a placeholder production OpenVPN endpoint binding name for the production profile intent.
- config/vpnkit-manifest.example.yaml: splits the selected `steamdeck`/`host-machine` pair into `test` and `production` profile intent entries.
- config/vpnkit-manifest.schema.json: requires `profile.intent` with `test`/`production` enum.
- scripts/vpnkit-manifest-validate.py: validates duplicate server/client/intent semantics and resolves sanitized JSON by `--profile-intent` (default `test`).
- scripts/vpnkit-render-profile-for-pair.sh: accepts `--profile-intent`, forwards it to the resolver, writes intent-specific filenames, and uses manifest-selected local binding refs in real mode without printing values.
- test/containers-test.sh: defaults selected manifest-pair profile intent to `test`, supports explicit `VPNKIT_TEST_MANIFEST_PROFILE_INTENT=production`, and avoids generated-profile content greps.
- test/manifest-profile-intents-test.sh: adds focused public-safe checks for resolver intents and fixture render path/mode/stdout without reading generated `.ovpn` contents.
- docs/plans/2026-06-09-issue-24-smart-routing-manifest/plan.md: records F1 implementation evidence pointer.
- docs/plans/2026-06-09-issue-24-smart-routing-manifest/progress/aad-implementer-f1.md: progress notes.
- docs/plans/2026-06-09-issue-24-smart-routing-manifest/verification/profile-intents.md: verification evidence.
AC_VERIFICATION:
- Docs state Deck server host is test/lab, not production; no production approval gate applies to Deck tests, with public-safety/Podman-only/explicit live-action boundaries preserved: AGENTS.md and README.md updated; no live mutation performed — passed.
- Manifest has separate production and test profile definitions for selected Steam Deck/host-machine pair: `steamdeck-host-machine-test` and `steamdeck-host-machine-production` in `config/vpnkit-manifest.example.yaml`; schema validation passed — passed.
- Resolver and renderer can select `--profile-intent test` and `--profile-intent production`; ambiguous pair resolution avoided: resolver filters by intent and semantic validation rejects duplicate server/client/intent definitions; fixture renderer produced metadata-only success for both intents with mode 600 — passed.
- `test/containers-test.sh` defaults selected manifest-pair profile intent to `test`; production only explicit by env: non-live harness run without `VPNKIT_TEST_MANIFEST_PROFILE_INTENT` reported `intent=test`; script docs/env use explicit `VPNKIT_TEST_MANIFEST_PROFILE_INTENT=production` for production — passed.
- No generated `.ovpn`, secrets, endpoints, logs, or profile contents are printed/committed: renderer stdout only path/intent/mode/permission/secret-not-printed; `git ls-files '*.ovpn'` returned no tracked profiles; generated fixture profiles were removed after verification — passed.
TESTS_RUN:
- RED: resolver `--profile-intent test`: failed before implementation with unrecognized argument — passed as expected red evidence.
- RED: renderer `--profile-intent test`: failed before implementation with unknown argument — passed as expected red evidence.
- RED: `test/manifest-profile-intents-test.sh`: failed before implementation on missing resolver argument — passed as expected red evidence.
- `PATH=/tmp/f1-profile-intents-venv/bin:$PATH bash -n scripts/vpnkit-render-profile-for-pair.sh test/containers-test.sh test/manifest-profile-intents-test.sh`: passed.
- `PATH=/tmp/f1-profile-intents-venv/bin:$PATH python3 scripts/vpnkit-manifest-validate.py --manifest config/vpnkit-manifest.example.yaml`: passed.
- `PATH=/tmp/f1-profile-intents-venv/bin:$PATH python3 scripts/vpnkit-manifest-validate.py --manifest config/vpnkit-manifest.example.yaml --server steamdeck --client host-machine --profile-intent test`: passed.
- `PATH=/tmp/f1-profile-intents-venv/bin:$PATH python3 scripts/vpnkit-manifest-validate.py --manifest config/vpnkit-manifest.example.yaml --server steamdeck --client host-machine --profile-intent production`: passed.
- `PATH=/tmp/f1-profile-intents-venv/bin:$PATH test/manifest-profile-intents-test.sh`: passed.
- Renderer fixture `test` and `production` intents into ignored `generated/openvpn-profiles`: passed; both reported `permissions=600` and `secret_material=not_printed`.
- Non-live harness default-intent check with `VPNKIT_TEST_SSH_TARGET=0.0.0.0` and selected manifest pair: passed manifest/profile rows with `intent=test`, total `PASS=4 FAIL=0 SKIP=11`.
QUALITY_CHECKS:
- `git diff --check`: passed.
- `git ls-files '*.ovpn'`: passed with no output/no tracked profiles.
- System Python manifest-positive checks: not used because system Python lacked `jsonschema`; disposable `/tmp/f1-profile-intents-venv` with public PyYAML/jsonschema was used instead.
QUALITY_NOTES:
- Readability/reuse: extended existing schema/resolver/renderer/harness patterns; no new dependency files or broad refactors.
- Error handling/logging: preserved clear stderr diagnostics and metadata-only renderer stdout; no secret values printed.
- Backend/API/data: not relevant; no persisted service data, migrations, or API contracts touched.
- Frontend/UI: not relevant.
- DevOps/runtime: config/env placeholders and harness docs are paired with schema/manifest/renderer behavior; Deck runtime remains Podman-only and no live mutation was performed.
- Security: no sensitive values, generated profiles, logs, or endpoint contents committed; generated fixture profiles were removed after checks; real mode reports missing env names only, not values.
- Concurrency/idempotency: renderer keeps deterministic intent-specific filenames and mode 600; harness selection remains repeatable.
- Compatibility/performance: resolver/renderer default intent is `test` to keep selected-pair fixture flow safe; production intent requires explicit CLI/env selection.
SIDE_FINDINGS:
- Blocking: none.
- Non-blocking follow-up candidates: consider adding a dedicated duplicate-intent negative fixture if future manifest test coverage expands.
PARENT_ACTION_REQUIRED:
- Action: none.
- Reason: no credentials/device/live context required for this public-safe repo-local task.
- Expected evidence: none.
- Safety bounds: no live Deck/prod mutation was required or performed.
NOTES: Generated profile location discovered as ignored `generated/openvpn-profiles/`. An initial read-only harness probe against the default `deck` target observed a non-running container, so acceptance evidence was rerun with a deliberately non-live SSH target to keep the check bounded to manifest/default-intent behavior.
