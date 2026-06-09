# Profile intent verification — F1

Date: 2026-06-09
Worktree: `.worktrees/issue-24-smart-routing-manifest`

## Safe path/name discovery

- Ignored generated profile location discovered from `.gitignore` and renderer defaults: `generated/openvpn-profiles/`.
- Generated fixture profile filenames used during checks: `steamdeck-host-machine-test.ovpn` and `steamdeck-host-machine-production.ovpn`.
- No generated `.ovpn` contents were printed or committed. Fixture `.ovpn` files created during checks were removed after verification.

## RED evidence

- `python3 scripts/vpnkit-manifest-validate.py --manifest config/vpnkit-manifest.example.yaml --server steamdeck --client host-machine --profile-intent test` initially failed with `unrecognized arguments: --profile-intent test`.
- `scripts/vpnkit-render-profile-for-pair.sh ... --profile-intent test ...` initially failed with `unknown argument: --profile-intent`.
- Newly added `test/manifest-profile-intents-test.sh` initially failed on the missing resolver argument.

## GREEN / behavior checks

All positive manifest checks used a disposable public-dependency venv:

```bash
python3 -m venv /tmp/f1-profile-intents-venv
/tmp/f1-profile-intents-venv/bin/python -m pip install --quiet PyYAML jsonschema
export PATH=/tmp/f1-profile-intents-venv/bin:$PATH
```

Commands run:

```bash
bash -n scripts/vpnkit-render-profile-for-pair.sh test/containers-test.sh test/manifest-profile-intents-test.sh
python3 scripts/vpnkit-manifest-validate.py --manifest config/vpnkit-manifest.example.yaml
python3 scripts/vpnkit-manifest-validate.py --manifest config/vpnkit-manifest.example.yaml --server steamdeck --client host-machine --profile-intent test
python3 scripts/vpnkit-manifest-validate.py --manifest config/vpnkit-manifest.example.yaml --server steamdeck --client host-machine --profile-intent production
test/manifest-profile-intents-test.sh
```

Result: passed. Resolver JSON had `profileIntent=test` for `steamdeck-host-machine-test` and `profileIntent=production` for `steamdeck-host-machine-production`.

Renderer fixture checks:

```text
profile_written=generated/openvpn-profiles/steamdeck-host-machine-test.ovpn
profile_intent=test
mode=fixture
permissions=600
secret_material=not_printed

profile_written=generated/openvpn-profiles/steamdeck-host-machine-production.ovpn
profile_intent=production
mode=fixture
permissions=600
secret_material=not_printed
```

Harness selected-pair default-intent check used a deliberately non-live SSH target to avoid Deck/prod mutation:

```bash
VPNKIT_TEST_SSH_TARGET=0.0.0.0 \
VPNKIT_TEST_MANIFEST=config/vpnkit-manifest.example.yaml \
VPNKIT_TEST_MANIFEST_SERVER=steamdeck \
VPNKIT_TEST_MANIFEST_CLIENT=host-machine \
VPNKIT_TEST_MANIFEST_RENDER_MODE=fixture \
VPNKIT_CONTAINERS_TEST_LOG=/tmp/f1-containers-test-nolive.log \
test/containers-test.sh
```

Relevant result lines:

```text
PASS manifest:validate - manifest schema/semantics passed
PASS manifest:resolve-pair - resolved steamdeck/host-machine intent=test to sanitized JSON
profile_intent=test
PASS manifest:render-profile - profile rendered for selected pair intent=test
PASS client:manifest-fixture-profile-shape - fixture profile exists with mode 600 for OpenVPN client smoke handoff; contents not printed
Totals: PASS=4 FAIL=0 SKIP=11
```

## Quality/public-safety checks

```bash
bash -n scripts/vpnkit-render-profile-for-pair.sh test/containers-test.sh test/manifest-profile-intents-test.sh
git diff --check
git ls-files '*.ovpn'
```

Result: passed; `git ls-files '*.ovpn'` returned no tracked `.ovpn` files.
