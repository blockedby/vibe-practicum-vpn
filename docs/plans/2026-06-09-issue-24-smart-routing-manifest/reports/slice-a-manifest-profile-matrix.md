# Slice A report — manifest/schema, resolver, profile renderer, matrix integration

## Task
- Mission: remediate Slice A root-audit gaps while preserving AC1-AC4.
- Boundaries: no private endpoint reads, no live mutation, no push.
- Worktree/branch: `.worktrees/issue-24-manifest-profile-slice` / `feat/issue-24-manifest-profile-slice`.

## Context
Slice stayed whole. Remediation was handled in the slice worktree. No sub-slices were created.

## Files changed
- `.gitignore` — manifest/local binding/generated profile ignore entries from original Slice A.
- `config/vpnkit-manifest.schema.json` — public JSON Schema now requires explicit client identity fields: `id`, `displayName`, `profileCommonName`, `clientCertIdentity`.
- `config/vpnkit-manifest.example.yaml` — public `host-machine` example now uses `displayName` and includes `id`, `profileCommonName`, `clientCertIdentity` defaults.
- `scripts/vpnkit-manifest-validate.py` — imports real PyYAML/jsonschema only, fails clearly when absent, validates client `id` against manifest key, and resolved sanitized JSON includes `serverMetadata` / `clientMetadata` for labels/rendering.
- Removed `scripts/jsonschema.py` — avoids shadowing the real dependency.
- `scripts/vpnkit-render-profile-for-pair.sh`, `test/containers-test.sh` — original Slice A renderer/harness changes remain in scope.
- `docs/plans/2026-06-09-issue-24-smart-routing-manifest/verification/slice-a.md` — updated with remediation evidence.

## Spec compliance
- AC1 manifest/schema contract: partial in this environment. Schema/example files are present and remediated for explicit client identity fields; full schema-positive validation requires installing external `jsonschema`.
- AC2 validator/resolver: remediated dependency behavior. In this environment the command exits 2 with clear `jsonschema` install guidance instead of using a fake local implementation. Resolver code now emits `clientMetadata.id/displayName/profileCommonName/clientCertIdentity` when dependencies are installed.
- AC3 renderer: unchanged from original Slice A; not rerun after remediation because resolver is dependency-blocked without `jsonschema`.
- AC4 harness selected manifest path: unchanged from original Slice A; not rerun after remediation for the same dependency reason.

## Acceptance verification
- AC1:
  - Covered by: schema/example static checks and dependency-error boundary.
  - Result: partial/pass for remediated field presence; positive schema validation not run because external `jsonschema` is absent.
  - Evidence: `verification/slice-a.md` shows `client_required=id,displayName,profileCommonName,clientCertIdentity,capabilities,profile_inputs` and `host-machine` defaults.
- AC2:
  - Covered by: `python3 scripts/vpnkit-manifest-validate.py --manifest config/vpnkit-manifest.example.yaml --server steamdeck --client host-machine`.
  - Result: expected dependency error in this environment, exit 2.
  - Evidence: `Missing Python dependency for manifest validation: jsonschema (python3 -m pip install jsonschema)` plus public install guidance.
- AC3:
  - Covered by: original fixture renderer evidence before dependency-removal remediation.
  - Result: stale/limited until rerun with external `jsonschema` installed.
- AC4:
  - Covered by: original selected-pair harness fixture evidence before dependency-removal remediation.
  - Result: stale/limited until rerun with external `jsonschema` installed.

## System readiness
- Config/env/secrets: public-safe; no private endpoints read; generated profiles remain ignored.
- Runtime/deployment wiring: not applicable; no live mutation authorized.
- Dependency readiness: external `jsonschema` must be installed for positive manifest validation, resolver, renderer, and harness fixture execution. The repo no longer ships an incomplete `scripts/jsonschema.py` substitute.

## Verification run
- `bash -n scripts/vpnkit-render-profile-for-pair.sh test/containers-test.sh`: PASS.
- `python3 -m py_compile scripts/vpnkit-manifest-validate.py`: PASS.
- Client identity example check: PASS; `host-machine` has `id`, `displayName`, `profileCommonName`, `clientCertIdentity`.
- Schema required-fields check: PASS; client schema requires those fields.
- Resolver command: expected exit 2 in this environment with clear missing `jsonschema` dependency guidance.
- `find scripts -maxdepth 1 -name 'jsonschema.py' -print`: no output; fake shadow module removed.
- Renderer/harness fixture after remediation: not run because resolver intentionally stops on missing external `jsonschema`.

## Issues
### Issue R-SLICE-A-1: Root audit manifest identity gap
- Description: schema/example/resolver used `display_name` / `common_name` and did not expose explicit rendering/label metadata.
- Resolution: switched public schema/example to `displayName`; added client `id`, `profileCommonName`, `clientCertIdentity`; resolver emits sanitized metadata.

### Issue R-SLICE-A-2: Root audit fake jsonschema dependency gap
- Description: top-level `scripts/jsonschema.py` shadowed the real dependency and hid missing dependency behavior.
- Resolution: removed `scripts/jsonschema.py`; validator now attempts real imports and exits with clear public install guidance if PyYAML/jsonschema is absent.

### Issue R-SLICE-A-3: Dependency-limited local verification path documented
- Description: current environment lacks external `jsonschema`, so schema-positive validation and downstream resolver-dependent fixture checks were not rerun after removing the fake module.
- Evidence: resolver command exits 2 with clear missing dependency guidance.
- Resolution: documented that schema-positive validation requires installing `jsonschema`; retained clear dependency-error evidence as the feasible local check requested by root.

## Verdict
Status: remediation complete with explicit dependency-limited verification. Root audit gaps were addressed in files and clear dependency-error verification passes. Full schema-positive AC1-AC4 rerun requires external `jsonschema` installed; no private endpoint reads, live mutation, or push occurred.

## Next-agent brief
- Install external `jsonschema` (and PyYAML if absent) in the verification environment.
- Rerun: manifest validate/resolve, fixture renderer, selected manifest-pair harness.
- Preserve no-private-endpoint/no-live-mutation boundaries unless root explicitly authorizes real-mode checks.
