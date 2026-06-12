## Task package
- Task name: Issue #24 smart routing + manifest/profile matrix
- Task package: docs/plans/2026-06-09-issue-24-smart-routing-manifest
- Report path: docs/plans/2026-06-09-issue-24-smart-routing-manifest/reports/acceptance-auditor.md
- Acceptance plan path: docs/plans/2026-06-09-issue-24-smart-routing-manifest/verification/acceptance-plan.md

## Acceptance verdict
- Status: accepted with limitations
- Summary: Fresh repo-local evidence supports the manifest/profile split, smart-routing policy, and harness behavior; live Deck/prod runtime smoke was intentionally not claimed.

## Acceptance coverage
- AC1: Schema/example supports servers, clients, pairs, capabilities, local binding refs, and test/production profile intents.
  - Evidence present: `python3 scripts/vpnkit/vpnkit-manifest-validate.py --manifest config/vpnkit-manifest.example.yaml` and full schema/example inspection.
  - Result: passed.
  - Gap: none for repo-local scope.
- AC2: Validator/resolver has clear dependency errors, `--server/--client`, `--profile-intent test|production`, default `test`, duplicate intent semantic validation, and sanitized output.
  - Evidence present: disposable venv with `PyYAML` + `jsonschema`; `--profile-intent test` and `production` resolve to sanitized JSON with `[local-only]` placeholders; `manifest_valid=true` default path works; temp duplicate-intent manifest returns `ERROR: semantic validation failed`.
  - Result: passed.
  - Gap: none for repo-local scope.
- AC3: Renderer writes ignored pair-specific `.ovpn`, mode 600, no secret stdout; real mode requires private values; fixture/test mode works.
  - Evidence present: `scripts/vpnkit/vpnkit-render-profile-for-pair.sh ... --fixture` for both intents produced `generated/openvpn-profiles/steamdeck-host-machine-test.ovpn` and `...production.ovpn`, both reported `permissions=600` and `secret_material=not_printed`; `--real` without bindings failed clearly with missing-env diagnostics.
  - Result: passed.
  - Gap: real-mode success was not run because private bindings were intentionally absent.
- AC4: `test/containers-test.sh` integrates the selected manifest pair and defaults to test profile intent; production is explicit.
  - Evidence present: two fresh harness runs with `VPNKIT_TEST_SSH_TARGET=nonexistent.invalid`; default run resolved `intent=test`, explicit env run resolved `intent=production`; both passed manifest validate/resolve/render and fixture profile shape checks while server checks were `SKIP`.
  - Result: passed.
  - Gap: live server/container checks were not available from the unreachable SSH target and were not claimed.
- AC5: Smart routing policy preserves adblock block-out, dev/package direct-out, RU direct, final selected-native-out, and full-tunnel assumptions in templates.
  - Evidence present: `python3 test/sing-box-smart-routing-proof.py` PASS.
  - Result: passed.
  - Gap: none for repo-local config proof.
- AC6: No secrets/private endpoints/generated OpenVPN profiles/PEM blocks/logs are tracked or printed by tests.
  - Evidence present: `git ls-files '*.ovpn' '*.pem' '*.key' '*.crt' '*.p12' '*.log'` returned no tracked sensitive artifacts; harness log inspected with `rg` for PEM/secret patterns returned no matches; fixture renderer stdout only printed metadata.
  - Result: passed.
  - Gap: none for repo-local scope.
- AC7: Deck policy docs reflect test/lab semantics and production gating.
  - Evidence present: `AGENTS.md` and `README.md` state Steam Deck server-host use is test/lab, not production, while public-safety, Podman-only Deck use, and explicit live-action approval remain; production profile intent is explicit.
  - Result: passed.
  - Gap: none.

## System readiness coverage
- Routes / registration: covered for sing-box templates and proof script.
- Services / APIs: not relevant.
- Config / env / secrets: covered; manifest/example/env placeholders exist and validator/renderer/harness stay sanitized.
- Docker / containers: covered at repo-local harness level; live container mutation not exercised.
- Permissions / access: covered by renderer `600` output and real-mode failure on missing local bindings.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: partially covered; repo-local wiring is good, but live Deck/prod runtime smoke remains unclaimed by design.

## Check freshness
- Targeted checks: fresh.
- Full local checks: fresh.
- Remote checks / CI: not available before push.

## Required before done
- No repo-local blockers remain for merge readiness.
- If the owner wants live Deck/prod runtime acceptance, run a separate operator-approved smoke against real hosts/endpoints after loading approved private bindings.

## Files written
- docs/plans/2026-06-09-issue-24-smart-routing-manifest/verification/acceptance-plan.md: updated
- docs/plans/2026-06-09-issue-24-smart-routing-manifest/reports/acceptance-auditor.md: updated
