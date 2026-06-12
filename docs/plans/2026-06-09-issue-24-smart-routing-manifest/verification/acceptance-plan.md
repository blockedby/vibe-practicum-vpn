# Acceptance plan — issue #24 smart routing + manifest/profile matrix

## Audit target
Independent readiness audit of branch `feat/issue-24-smart-routing-manifest` in worktree `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`.

## Acceptance criteria under review
- Manifest/schema supports servers, clients, pairs, capabilities, local binding refs, and test/production profile intents.
- Validator/resolver CLI has clear dependency errors, `--server/--client`, `--profile-intent test|production`, default `test`, duplicate intent semantic validation, and sanitized output.
- Profile renderer writes to ignored generated/openvpn-profiles or equivalent, mode 600, no secret stdout; real mode requires private values; fixture/test mode works.
- `test/containers-test.sh` integrates selected manifest pair and defaults to test profile intent; production is explicit.
- Smart routing policy preserves adblock block-out, dev/package direct-out, RU direct, final selected-native-out, and full-tunnel assumptions in templates.
- Repo-local safety: no secrets/private endpoints/generated OpenVPN profiles/PEM blocks/logs are tracked or printed by tests.
- Documentation reflects Steam Deck test/lab host policy versus production gate.

## Fresh verification route
1. `git status --short`
2. `git diff --check main...HEAD`
3. `git ls-files '*.ovpn'`
4. `bash -n scripts/vpnkit/vpnkit-render-profile-for-pair.sh test/containers-test.sh test/manifest-profile-intents-test.sh`
5. `python3 -m py_compile scripts/vpnkit/vpnkit-manifest-validate.py test/sing-box-smart-routing-proof.py`
6. Disposable venv with public `PyYAML` + `jsonschema`, then run manifest validation for `--profile-intent test` and `production`
7. Renderer fixture check for selected pair, mode 600, and no secret stdout
8. `VPNKIT_TEST_MANIFEST=... VPNKIT_TEST_MANIFEST_SERVER=... VPNKIT_TEST_MANIFEST_CLIENT=... VPNKIT_TEST_MANIFEST_RENDER_MODE=fixture VPNKIT_TEST_SSH_TARGET=nonexistent.invalid test/containers-test.sh`
9. `python3 test/sing-box-smart-routing-proof.py`
10. `go test ./...`, `go vet ./...`, `go build -o /tmp/vibe-vpn-issue24 ./cmd/vibe-vpn`

## Evidence policy
- Do not read `config/private-endpoints.local.env`.
- Do not mutate live/prod/Deck.
- Treat unreachable SSH targets as acceptable for repo-local harness evidence if validate -> resolve -> render -> fixture handoff still passes and server checks are SKIP.
