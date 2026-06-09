## Task package
- Task name: Issue #24 smart routing + manifest/profile matrix
- Task package: docs/plans/2026-06-09-issue-24-smart-routing-manifest
- Report path: docs/plans/2026-06-09-issue-24-smart-routing-manifest/reports/acceptance-auditor.md
- Acceptance plan path: docs/plans/2026-06-09-issue-24-smart-routing-manifest/verification/acceptance-plan.md

## Acceptance verdict
- Status: accepted with limitations
- Summary: Repo-local manifest/profile, smart-routing, and harness acceptance is fresh and passing; live/prod `vpnkit` mutation and live SSH/container smoke remain intentionally unclaimed.

## Acceptance coverage
- AC1: schema/example exists, validates a public example, and keeps private/generated artifacts ignored.
  - Evidence present: fresh `PATH=/tmp/vpnkit-jsonschema-venv/bin:$PATH python3 scripts/vpnkit-manifest-validate.py --manifest config/vpnkit-manifest.example.yaml --server steamdeck --client host-machine` PASS; tracked schema/example/ignore wiring.
  - Result: passed.
  - Gap: none for repo-local scope.
- AC2: validator/resolver validates schema + semantic pair contracts and emits sanitized pair JSON.
  - Evidence present: same validator run PASS, emitting sanitized JSON with `[local-only]` placeholders and `clientMetadata` including `id/displayName/profileCommonName/clientCertIdentity`; negative check `no pair found` for unknown client.
  - Result: passed.
  - Gap: none for repo-local scope.
- AC3: renderer writes pair-specific `.ovpn` with safe permissions, fixture mode, and non-secret stdout; real-mode diagnostics are clear.
  - Evidence present: fresh `PATH=/tmp/vpnkit-jsonschema-venv/bin:$PATH scripts/vpnkit-render-profile-for-pair.sh --manifest config/vpnkit-manifest.example.yaml --server steamdeck --client host-machine --out-dir generated/openvpn-profiles-final --fixture` PASS; output reported `profile_written`, `mode fixture`, permissions `600`, `secret_material=not_printed`.
  - Result: passed.
  - Gap: none for repo-local scope; live/profile import behavior not claimed.
- AC4: container-test manifest path runs validate -> resolve -> render -> client smoke handoff and distinguishes selected-pair prerequisite failures from planned `SKIP` rows.
  - Evidence present: fresh `PATH=/tmp/vpnkit-jsonschema-venv/bin:$PATH VPNKIT_TEST_MANIFEST=config/vpnkit-manifest.example.yaml VPNKIT_TEST_MANIFEST_SERVER=steamdeck VPNKIT_TEST_MANIFEST_CLIENT=host-machine VPNKIT_TEST_MANIFEST_RENDER_MODE=fixture VPNKIT_TEST_MANIFEST_OUT_DIR=generated/openvpn-profiles-final-harness VPNKIT_TEST_SSH_TARGET=nonexistent.invalid test/containers-test.sh` PASS overall.
  - Result: passed with limitation.
  - Gap: server checks were `SKIP` because the SSH target was an unreachable placeholder; live `vpnkit` smoke is intentionally not claimed in this audit.
- AC5: sing-box templates add narrow adblock/dev-direct policy while preserving existing full-tunnel/RU/final behavior.
  - Evidence present: `python3 test/sing-box-smart-routing-proof.py` PASS; dummy `VPNKIT_ROUTING_MODE=tun scripts/vpnkit-render-local-configs.sh` render probe PASS with smart route sets and copied local rule-set files.
  - Result: passed.
  - Gap: none for repo-local scope.
- AC6: local route-decision proof covers block/direct/RU/default and remote rule-set handling limits.
  - Evidence present: `python3 test/sing-box-smart-routing-proof.py` PASS.
  - Result: passed with limitation.
  - Gap: remote download/cache/failure handling is config-level proof only, not a live sing-box runtime probe.
- AC7: public docs explain the manifest/profile matrix and smart routing using placeholders only.
  - Evidence present: `README.md`, `config/vpnkit-manifest.example.yaml`, and repo-local placeholder/ignore wiring.
  - Result: passed.
  - Gap: none.
- AC8: fresh verification includes syntax/schema/unit/safe local checks; live/prod acceptance remains unclaimed.
  - Evidence present: `bash -n scripts/*.sh test/*.sh`, `python3 -m py_compile scripts/vpnkit-manifest-validate.py test/sing-box-smart-routing-proof.py`, `go test ./...`, `go vet ./...`, `go build -o /tmp/vibe-vpn-issue24 ./cmd/vibe-vpn`.
  - Result: passed.
  - Gap: none for repo-local scope.

## System readiness coverage
- Routes / registration: covered for sing-box template routing order and proof harness.
- Services / APIs: not relevant.
- Config / env / secrets: covered; public manifest/example/ignore wiring is present, and the fresh validator run proves the dependency path with `jsonschema` installed in a disposable venv.
- Docker / containers: covered at repo-local harness level; live container mutation is out of scope and not claimed.
- Permissions / access: covered by fixture renderer permissions `600` and no private endpoint access.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: covered only for repo-local manifest/render/harness flow; live deployment/runtime acceptance remains unclaimed.

## Check freshness
- Targeted checks: fresh.
- Full local checks: fresh.
- Remote checks / CI: not available before push.

## Required before done
- None for repo-local acceptance.
- If live/prod acceptance is later requested, rerun operator-approved live smoke against a real `vpnkit` target and private endpoint inputs.

## Files written
- docs/plans/2026-06-09-issue-24-smart-routing-manifest/verification/acceptance-plan.md: updated
- docs/plans/2026-06-09-issue-24-smart-routing-manifest/reports/acceptance-auditor.md: updated
