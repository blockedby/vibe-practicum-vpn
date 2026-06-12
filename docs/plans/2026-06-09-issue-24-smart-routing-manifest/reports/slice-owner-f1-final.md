# Slice owner final report — F1 Deck test policy + profile intents

## Task
- Mission: implement scoped issue #24 follow-up: Deck server host is test/lab, add separate test and production profile intents.
- Target: existing worktree `.worktrees/issue-24-smart-routing-manifest`, branch `feat/issue-24-smart-routing-manifest`.
- Boundaries: no live Deck/prod mutation, no `.ovpn` contents, no secrets/private endpoints/generated profiles/log commits.

## Spec compliance
- Deck test/lab semantics: done. `AGENTS.md` and `README.md` state Deck server-host use is test/lab, not production; production approval gate does not apply to Deck tests, while public-safety, Podman-only Deck runtime, and explicit live-action approval remain.
- Profile location discovery: done. Existing ignored manifest renderer output is `generated/openvpn-profiles/`; no profile contents read or reported.
- Production vs test profile definitions: done. `config/vpnkit-manifest.example.yaml` contains `steamdeck-host-machine-test` and `steamdeck-host-machine-production` with `profile.intent` values; schema requires intent.
- Selection behavior: done. Resolver/renderer support `--profile-intent`; harness defaults `VPNKIT_TEST_MANIFEST_PROFILE_INTENT=test`, production is explicit.

## Acceptance verification
- Fresh owner checks passed:
  - `bash -n scripts/vpnkit/vpnkit-render-profile-for-pair.sh test/containers-test.sh test/manifest-profile-intents-test.sh`
  - resolver checks for `--profile-intent test` and `--profile-intent production` using disposable PyYAML/jsonschema venv
  - `test/manifest-profile-intents-test.sh`
  - non-live `test/containers-test.sh` selected-pair harness showed `intent=test`, PASS=4 FAIL=0 SKIP=11
  - `git diff --check`
  - `git ls-files '*.ovpn'` returned no tracked profiles
- Evidence details: `verification/profile-intents.md`; implementer report: `reports/aad-implementer-f1-profile-intents.md`.

## Issues
- R-01: Steam Deck policy ambiguity resolved in docs/config guidance.
- R-02: Same server/client pair profile ambiguity resolved with explicit intent dimension and duplicate-intent semantic validation.
- F/U issues: none.

## Verdict
- Status: success.
- System readiness: ready for repo-local/public-safe scope; real profile generation still requires local private cert/endpoint env and should write only to ignored profile paths.
