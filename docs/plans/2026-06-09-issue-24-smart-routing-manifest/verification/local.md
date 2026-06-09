# Local verification — issue #24 smart routing + manifest/profile matrix

Date: 2026-06-09
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
Branch: `feat/issue-24-smart-routing-manifest`

## Dependency setup for schema-positive checks

- Created disposable venv outside the repo: `/tmp/vpnkit-jsonschema-venv`.
- Installed public packages: `PyYAML`, `jsonschema`.
- No private endpoint file was read.

## Commands and results

- `PATH=/tmp/vpnkit-jsonschema-venv/bin:$PATH python3 scripts/vpnkit-manifest-validate.py --manifest config/vpnkit-manifest.example.yaml --server steamdeck --client host-machine` — PASS; emitted sanitized JSON only, with `[local-only]` placeholders and `clientMetadata.id/displayName/profileCommonName/clientCertIdentity`.
- `PATH=/tmp/vpnkit-jsonschema-venv/bin:$PATH scripts/vpnkit-render-profile-for-pair.sh --manifest config/vpnkit-manifest.example.yaml --server steamdeck --client host-machine --out-dir generated/openvpn-profiles-final2 --fixture` — PASS; printed only `profile_written`, `mode=fixture`, `permissions=600`, `secret_material=not_printed`.
- `PATH=/tmp/vpnkit-jsonschema-venv/bin:$PATH VPNKIT_TEST_MANIFEST=config/vpnkit-manifest.example.yaml VPNKIT_TEST_MANIFEST_SERVER=steamdeck VPNKIT_TEST_MANIFEST_CLIENT=host-machine VPNKIT_TEST_MANIFEST_RENDER_MODE=fixture VPNKIT_TEST_MANIFEST_OUT_DIR=generated/openvpn-profiles-final2-harness VPNKIT_TEST_SSH_TARGET=nonexistent.invalid test/containers-test.sh` — PASS overall; manifest validate/resolve/render and fixture profile shape PASS; server checks SKIP because the placeholder SSH target is intentionally unreachable.
- `python3 test/sing-box-smart-routing-proof.py` — PASS: `PASS sing-box smart routing proof: adblock/dev-direct/RU/default decisions and template invariants`.
- `bash -n scripts/*.sh test/*.sh` — PASS.
- `python3 -m py_compile scripts/vpnkit-manifest-validate.py test/sing-box-smart-routing-proof.py` — PASS.
- System-python missing-dependency check: `python3 scripts/vpnkit-manifest-validate.py --manifest config/vpnkit-manifest.example.yaml` — expected FAIL/PASS diagnostic; printed clear missing `jsonschema` install guidance.
- Unknown client negative check with venv — expected FAIL/PASS diagnostic: `no pair found`.
- Real renderer without local bindings — expected FAIL/PASS diagnostic: `real mode cannot render without local bindings`.
- Temp dummy `VPNKIT_ROUTING_MODE=tun scripts/vpnkit-render-local-configs.sh` render probe — PASS; rendered sing-box config included smart route sets and copied local rule-set files. Warning about missing `vibe-vpn` subscription input was expected for dummy secrets.
- `go test ./...` — PASS.
- `go vet ./...` — PASS.
- `go build -o /tmp/vibe-vpn-issue24 ./cmd/vibe-vpn` — PASS.

## Limits

- Live Deck/prod mutation and real SSH/container smoke were not run and are not claimed.
- Remote rule-set download/cache/failure behavior is proven at config-shape level only, not as a live sing-box runtime network probe.
- Generated fixture profiles/logs are under ignored `generated/` and `logs/` paths and are not committed.
