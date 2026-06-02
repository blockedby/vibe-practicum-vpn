# Plan: RU direct sing-box routing

## Task intake
- Goal: update Docker/vpnkit sing-box routing so Russian IP ranges and Russian geosite domains route `direct-out` instead of `selected-native-out` proxy.
- In scope: tracked Docker/vpnkit sing-box config template, minimal regression coverage, fresh local verification feasible in repo.
- Out of scope: VPS deploy/mutation, secrets/generated rendered configs, broad routing refactors.
- Done-state: template contains RU IP/geosite direct rules without breaking existing DNS hijack/default proxy behavior; tests/checks pass; local Docker lab acceptance attempted per AGENTS.
- Blocking unknowns: whether local Docker daemon/secrets are available for full vpnkit runtime acceptance.

## Repo orientation
- Project shape: Go CLI/daemon plus Docker vpnkit runtime assets.
- Local guidance: root `AGENTS.md` requires local Docker lab acceptance for vpnkit runtime/routing/sing-box changes and forbids VPS mutation/secrets commits.
- Likely files: `config/sing-box/config.json.template`; possible regression test under Go test suite.
- Verification commands: `go test ./...`; `scripts/vpnkit-render-local-configs.sh`; `docker compose ... ovpn-client-test` if Docker/secrets available; `sing-box check` if binary/image available.

## Reuse discovery
- Existing template has DNS hijack rules first, final `selected-native-out`, and existing `direct-out` outbound.
- `scripts/vpnkit-render-local-configs.sh` renders the template by replacing `{{SELECTED_NATIVE_OUT_JSON}}` with selected outbound JSON.
- Existing Docker lab runbook in `AGENTS.md` defines acceptance workflow and expected client test output.

## Missing pieces
- Add a sing-box route rule matching `geoip:ru` and `geosite:ru` to `direct-out` before default final proxy.
- Add a lightweight regression that parses the template and asserts RU direct routing plus preserved DNS hijack/default proxy behavior.

## Plan tasks

### Task 1: RU direct routing in Docker sing-box template
Goal:
- Make RU IP and RU geosite traffic bypass proxy via `direct-out` in the Docker/vpnkit sing-box template.
Boundary:
- System area: Docker/vpnkit sing-box config template and regression test.
- Primary verification: targeted test/JSON validation plus broad Go tests.
Existing pattern / reuse:
- Reuse `direct-out` existing outbound and current route rule ordering in `config/sing-box/config.json.template`.
Missing change:
- Add minimal route rule `{ "geoip": "ru", "geosite": "ru", "outbound": "direct-out" }` or equivalent valid sing-box route syntax.
Scope / likely files:
- `config/sing-box/config.json.template`
- test file near existing Go tests or scripts.
Acceptance criteria:
- Template still parses after replacing selected outbound placeholder with valid JSON.
- RU IP and RU geosite traffic have an explicit route to `direct-out`.
- DNS hijack rules remain before normal routing and final remains `selected-native-out`.
- No secrets/generated artifacts are committed.
Test plan:
- Positive: targeted regression test for template JSON/routing invariants; `go test ./...`.
- Manual/runtime: render local config and run Docker lab OpenVPN client regression if Docker/secrets are available.
Dependencies:
- Depends on: none.
- Blocks: final verification/report.
- Can run parallel with: none.
Executor:
- aad-implementer.

## Dependency graph
- Task 1 -> final owner verification and report.

## Execution ledger
- 2026-06-02: Worktree and task package created; ready for implementer dispatch.
- 2026-06-02: aad-implementer completed Task 1 implementation: added RU direct remote rule-set routes in `config/sing-box/config.json.template` and regression coverage in `internal/singbox/singbox_test.go`.
- 2026-06-02: Verification evidence recorded in `verification/local.md`: targeted regression passed, `go test ./...` passed, temp `sing-box check` passed with documented compatibility env for pre-existing deprecation gates; Docker lab waived because `secrets/` is absent and secrets are out of scope.
- 2026-06-02: Implementer completed Task 1 in commits `3d4534d`, `6f6a3e2`, `ccef739`; targeted tests, full Go tests, diff check, and sing-box check passed per report.
- 2026-06-02: Owner reran targeted/full Go verification and render. Docker lab was attempted locally only: build/start succeeded on retry, OpenVPN client connected, but full client DNS/HTTPS regression did not pass (`dig @8.8.8.8` timed out). No VPS touched; secrets/logs removed from worktree.

## Final done-state
- Spec compliance: template and regression coverage implement explicit RU IP/geosite direct routing while preserving DNS hijack ordering and default proxy final.
- Acceptance verification: automated config invariants and Go tests pass; sing-box check passed under existing deprecation compatibility env vars; local Docker lab is partial because client DNS regression timed out after successful build/start/OpenVPN connection.
- System readiness: branch is ready for code review with a runtime caveat; do not deploy until Docker lab DNS/HTTPS regression is green or the pre-existing lab/runtime issue is resolved.
- Open issues: U-01 Docker lab client DNS/HTTPS acceptance did not pass in this environment.
