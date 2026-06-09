# Acceptance plan — issue #24 smart routing + manifest/profile matrix

## Scope under audit
- Repo-local manifest/schema, resolver, profile renderer, container harness, smart-routing proof, and public docs.
- Explicitly out of scope for this audit: live Deck/prod mutation, private endpoint reads, and live `vpnkit` smoke on a production target.
- Selected-pair fixture harness runs with an unreachable SSH target are acceptable for AC4 if validate -> resolve -> render -> fixture profile shape passes and server checks are `SKIP`.

## Acceptance criteria mapping
- AC1: schema/example exists, validates a public example, and keeps private/generated artifacts ignored.
- AC2: validator/resolver validates schema + semantic pair contracts and emits sanitized pair JSON.
- AC3: renderer writes pair-specific `.ovpn` with safe permissions, fixture mode, and non-secret stdout; real-mode diagnostics are clear.
- AC4: container-test manifest path runs validate -> resolve -> render -> client smoke handoff and distinguishes selected-pair prerequisite failures from planned `SKIP` rows.
- AC5: sing-box templates add narrow adblock/dev-direct policy while preserving existing full-tunnel/RU/final behavior.
- AC6: local route-decision proof covers block/direct/RU/default and remote rule-set handling limits.
- AC7: public docs explain the manifest/profile matrix and smart routing using placeholders only.
- AC8: fresh verification includes syntax/schema/unit/safe local checks; live/prod acceptance remains unclaimed.

## Fresh verification route
1. `PATH=/tmp/vpnkit-jsonschema-venv/bin:$PATH python3 scripts/vpnkit-manifest-validate.py --manifest config/vpnkit-manifest.example.yaml --server steamdeck --client host-machine`
2. `PATH=/tmp/vpnkit-jsonschema-venv/bin:$PATH scripts/vpnkit-render-profile-for-pair.sh --manifest config/vpnkit-manifest.example.yaml --server steamdeck --client host-machine --out-dir generated/openvpn-profiles-final --fixture`
3. `PATH=/tmp/vpnkit-jsonschema-venv/bin:$PATH VPNKIT_TEST_MANIFEST=config/vpnkit-manifest.example.yaml VPNKIT_TEST_MANIFEST_SERVER=steamdeck VPNKIT_TEST_MANIFEST_CLIENT=host-machine VPNKIT_TEST_MANIFEST_RENDER_MODE=fixture VPNKIT_TEST_MANIFEST_OUT_DIR=generated/openvpn-profiles-final-harness VPNKIT_TEST_SSH_TARGET=nonexistent.invalid test/containers-test.sh`
4. `python3 test/sing-box-smart-routing-proof.py`
5. `bash -n scripts/*.sh test/*.sh`
6. `python3 -m py_compile scripts/vpnkit-manifest-validate.py test/sing-box-smart-routing-proof.py`
7. `go test ./...`
8. `go vet ./...`
9. `go build -o /tmp/vibe-vpn-issue24 ./cmd/vibe-vpn`

## Current status
- Fresh repo-local verification passed in this worktree.
- The selected manifest-pair harness path passed with manifest validate/resolve/render and client fixture profile shape; server checks were `SKIP` because the SSH target was an unreachable placeholder, which is acceptable for this repo-local audit.
- Live/prod acceptance remains unclaimed by design and requires a separate operator-approved run if it is later requested.
