# Plan: OpenVPN push DNS prod deploy support

## Task intake
- Goal: make `scripts/vpnkit/vpnkit-prod-deploy.sh deploy` ensure production TUN/full-tunnel OpenVPN pushes a public DNS literal before build/recreate.
- In scope: remote deploy flow only; edit/sync existing `secrets/vps/rendered/openvpn/server.conf`; default pushed DNS `1.1.1.1`; env override `VPNKIT_OPENVPN_PUSH_DNS`; IPv4 validation; safe logs; tests in `test/prod-deploy-helper-test.sh` for order/default/override/invalid pre-build failure.
- Out of scope: live host actions, source PKI generation, full OpenVPN render, changing public endpoint values or generated secrets.
- Done state: committed changes on `fix/adblock-routes` with fresh `bash -n`, `test/prod-deploy-helper-test.sh`, and `git diff --check` passing.
- Blocking unknowns: none.

## Repo orientation
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/fix-adblock-routes`.
- Local guidance: public-safety rules; no live host mutation; deploy helper is canonical; output must be redacted/secret-safe.
- Likely files: `scripts/vpnkit/vpnkit-prod-deploy.sh`, `test/prod-deploy-helper-test.sh`, this task package.
- Verification commands: `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`; `test/prod-deploy-helper-test.sh`; `git diff --check`.

## Reuse discovery
- Remote deploy path already calls `render_local_configs` then `activate_image`, with sing-box-only fallback that avoids source PKI.
- Tests already mock ssh/docker/git/renderer and assert redaction/order around `local_config_render`, `compose_build`, and failure before activation.
- Existing logs use key=value summaries, avoid raw config, and redact IPs/secrets in local output.

## Missing pieces
- Remote helper function to validate `VPNKIT_OPENVPN_PUSH_DNS` as IPv4 (default `1.1.1.1`).
- Remote helper function to update only `secrets/vps/rendered/openvpn/server.conf`, preserving other content and failing if missing/unverifiable.
- Deploy ordering between render/fallback and `activate_image`.
- Plan/dry-run steps updated to mention push DNS sync.
- Mock fixture and tests for default, override, invalid value before build/up.

## Plan tasks

### Task 1: Production deploy syncs pushed OpenVPN DNS before activation
Goal:
- Deploy flow validates and writes the desired pushed DNS in existing rendered OpenVPN server config after render/fallback and before compose build/up.
Boundary:
- System area: production deploy helper/runtime wiring.
- Primary verification: helper shell tests with mocked remote deploy.
Existing pattern / reuse:
- Follow `render_local_configs`, `activate_image`, mock remote test patterns in `test/prod-deploy-helper-test.sh`.
Missing change:
- Add IPv4 validation and update/verify function; insert into deploy flow; update tests.
Scope / likely files:
- `scripts/vpnkit/vpnkit-prod-deploy.sh`
- `test/prod-deploy-helper-test.sh`
Acceptance criteria:
- Default deploy writes/verifies `push "dhcp-option DNS 1.1.1.1"` in `secrets/vps/rendered/openvpn/server.conf` before compose build/up and logs only `openvpn_push_dns=updated`-style summary.
- Env override `VPNKIT_OPENVPN_PUSH_DNS=<valid IPv4>` is accepted and written.
- Invalid override fails before compose build/up.
- Missing or non-updatable/unverified config fails before compose build/up.
- Existing render fallback still does not require source PKI.
Evidence route:
- Existing automated checks first: `test/prod-deploy-helper-test.sh` plus syntax/diff checks.
- Add/extend test coverage for criteria.
- Access/runtime needed: local shell only; no live hosts.
- Outcome boundary: proves helper ordering and content behavior under mocks, not live production DNS behavior.
Test plan:
- Positive: default and override mocked deploys; order assertions around render/fallback, `openvpn_push_dns=updated`, `compose_build`.
- Negative: invalid `VPNKIT_OPENVPN_PUSH_DNS` mocked deploy fails with no `compose_build`/`compose_up`; missing config may be covered if cheap.
Dependencies:
- Depends on: none.
- Blocks: final verification.
- Can run parallel with: none.
Executor:
- aad-implementer.

## Dependency graph
- Single implementation task; keep slice whole. No sub-slices.

## Execution ledger
- 2026-06-13: plan created; ready for aad-implementer dispatch.

## Final acceptance verification
- `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh` — PASS (fresh owner verification 2026-06-13).
- `test/prod-deploy-helper-test.sh` — PASS (fresh owner verification 2026-06-13).
- `git diff --check` — PASS (fresh owner verification 2026-06-13).

## Final done-state
- Slice stayed whole with one `aad-implementer` task.
- Implementation commits:
  - `daa5fd493998eb9b69fb66053ea46e08264b5106 fix(vpnkit): sync OpenVPN push DNS before prod activation`
  - `4a9dc7b docs: record OpenVPN push DNS implementation evidence`
- Spec compliance: complete for local deploy helper behavior. The deploy flow syncs existing rendered OpenVPN `server.conf` after render/fallback and before compose build/up, defaults to `1.1.1.1`, accepts valid `VPNKIT_OPENVPN_PUSH_DNS`, validates IPv4, fails before activation on invalid/missing config, and logs summary status only.
- System readiness: local helper/mocked remote evidence only; no live hosts touched by request.
- Open blockers/follow-ups: none for this slice.
