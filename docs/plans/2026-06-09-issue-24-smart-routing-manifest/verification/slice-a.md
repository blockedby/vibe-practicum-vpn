# Slice A verification

Commands run from worktree `.worktrees/issue-24-manifest-profile-slice` on 2026-06-09.

## Static/syntax

```bash
bash -n scripts/vpnkit/vpnkit-render-profile-for-pair.sh test/containers-test.sh
```

Result: PASS (`bash_n=0`).

```bash
python3 -m py_compile scripts/vpnkit/vpnkit-manifest-validate.py
```

Result: PASS (`py_compile=0`). `scripts/jsonschema.py` was removed and is no longer compiled because the repo must not shadow the real `jsonschema` dependency.

## Remediation checks for root audit gaps

Client identity schema/example check:

```bash
python3 - <<'PY'
import yaml, json
from pathlib import Path
m=yaml.safe_load(Path('config/vpnkit-manifest.example.yaml').read_text())
c=m['clients']['host-machine']
assert c['id']=='host-machine'
assert c['displayName']
assert c['profileCommonName']=='host-machine'
assert c['clientCertIdentity']=='host-machine'
print(json.dumps({k:c[k] for k in ['id','displayName','profileCommonName','clientCertIdentity']}, sort_keys=True))
PY
```

Result: PASS:

```text
{"clientCertIdentity": "host-machine", "displayName": "Host machine OpenVPN client (public fixture)", "id": "host-machine", "profileCommonName": "host-machine"}
```

Schema required-fields check:

```bash
python3 - <<'PY'
import json
from pathlib import Path
s=json.loads(Path('config/vpnkit-manifest.schema.json').read_text())
required=s['$defs']['client']['required']
assert all(k in required for k in ['id','displayName','profileCommonName','clientCertIdentity'])
print('client_required=' + ','.join(required))
PY
```

Result: PASS:

```text
client_required=id,displayName,profileCommonName,clientCertIdentity,capabilities,profile_inputs
```

Dependency-error check with repo-local `jsonschema.py` removed:

```bash
python3 scripts/vpnkit/vpnkit-manifest-validate.py \
  --manifest config/vpnkit-manifest.example.yaml \
  --server steamdeck --client host-machine
```

Result in this environment: expected exit 2 because external `jsonschema` is not installed. Clear diagnostic:

```text
Missing Python dependency for manifest validation: jsonschema (python3 -m pip install jsonschema)
Install the missing public packages in your local/CI Python environment; do not store secrets in manifests or install from private endpoints.
```

Positive schema validation/resolver output was not rerun after removing the fake dependency because this environment lacks external `jsonschema`. With `jsonschema` installed, the resolver output path includes `serverMetadata` and `clientMetadata` with `id`, `displayName`, `profileCommonName`, and `clientCertIdentity` for rendering/matrix labeling.

## Earlier bounded fixture evidence before remediation

Before the remediation removed `scripts/jsonschema.py`, the Slice A fixture path had passed validate -> resolve -> render -> harness shape checks. Those results are stale for final acceptance until rerun in an environment with external `jsonschema` installed, but they remain useful implementation history:

- fixture renderer wrote `generated/openvpn-profiles-test/steamdeck-host-machine.ovpn`, mode `600`, with `secret_material=not_printed`.
- real mode without local bindings exited 3 with missing env diagnostics and no secret output.
- `test/containers-test.sh` selected fixture pair reported `PASS manifest:validate`, `PASS manifest:resolve-pair`, `PASS manifest:render-profile`, and `PASS client:manifest-fixture-profile-shape` with intentionally missing SSH target server checks as SKIP.

## Current git status excerpt

```text
 M .gitignore
 A docs/plans/2026-06-09-issue-24-smart-routing-manifest/plan.md
 A docs/plans/2026-06-09-issue-24-smart-routing-manifest/progress/slice-a.md
 A docs/plans/2026-06-09-issue-24-smart-routing-manifest/reports/slice-a-manifest-profile-matrix.md
 A docs/plans/2026-06-09-issue-24-smart-routing-manifest/verification/slice-a.md
 M test/containers-test.sh
?? config/vpnkit-manifest.example.yaml
?? config/vpnkit-manifest.schema.json
?? scripts/vpnkit/vpnkit-manifest-validate.py
?? scripts/vpnkit/vpnkit-render-profile-for-pair.sh
```
