## Task
- Mission: Add nested OpenVPN acceptance to the existing Steam Deck `steamdeck-host` lab lifecycle without a separate scenario or testing root.
- Target: `test/containers-test.sh`, lab setup generation, `docker/ovpn-client-test`, Deck lab `vpnkit` container entrypoint, README/task evidence.
- Boundaries: Public-safe only; no production/default `vpnkit` mutation; no tracked/generated secrets; no real endpoint values printed.
- Done when: `up/test/down/cycle` manage nested lab material and required nested rows, with safe checks passing and live cycle green or explicitly blocked by local private environment availability.

## Context
- Slice: Steam Deck unified nested VPN acceptance
- Task package: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
- Branch: `feat/issue-24-smart-routing-manifest`
- PR: #26; Issue: #27

## Spec compliance
- Unified lifecycle remains `test/containers-test.sh --scenario steamdeck-host --action ...`: done; nested checks are wired into existing `test`/`cycle` client smoke path.
- Nested lab material generated under existing ignored tree: done; setup emits only paths/metadata for `secrets/vpnkit-labs/steamdeck-host/nested/openvpn/...`.
- Nested target/server managed by lifecycle: done; rendered lab config includes `/etc/openvpn/nested/server.conf`, and the lab-only `vpnkit` entrypoint starts it only when mounted.
- Required nested rows: done; runner records `client:nested-route-via-tun0`, `client:nested-handshake`, `client:nested-tun1`, and `client:nested-ping-peer` as FAIL-on-missing/FAIL-on-client-failure rows. `VPNKIT_STEAMDECK_NESTED_VPN_ENABLED=0` records not deploy-ready.
- Public docs/GitHub: README updated; PR #26 comment https://github.com/blockedby/vibe-practicum-vpn/pull/26#issuecomment-4668888017 and issue #27 comment https://github.com/blockedby/vibe-practicum-vpn/issues/27#issuecomment-4668888168 posted after push.

## Acceptance verification
- Static/safe checks: passed.
  - Evidence: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/verification/nested-vpn.md`.
- Generated nested material smoke: passed with temp lab dir; output redacted to temp paths and contents not printed.
- Live Steam Deck cycle: not run; `config/private-endpoints.local.env` is absent in this worktree, so no authorized non-placeholder endpoint binding was available. Final readiness is not claimed.

## Verification run
- `bash -n test/containers-test.sh scripts/vpnkit-test-lab-setup.sh scripts/vpnkit-steamdeck-client-test.sh scripts/vpnkit-steamdeck-podman.sh docker/ovpn-client-test/*.sh docker/vpnkit/entrypoint.sh`: passed.
- `python3 test/sing-box-smart-routing-proof.py`: passed.
- `go test ./...`: passed.
- `go vet ./...`: passed.
- `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: passed.
- `python3 -m py_compile scripts/*.py test/*.py`: passed.
- Sensitive tracked artifact guard: `git ls-files | grep -E '(^|/)(secrets|generated|logs)/|\.(ovpn|pem|key|crt|csr|srl)$'` returned no tracked generated secret/profile artifacts.

## Issues
### U-01: Live Deck nested cycle not run in this worktree
- Description: Private endpoint bindings are required for the live isolated Deck lab cycle, but `config/private-endpoints.local.env` is absent.
- Evidence: local check returned absent; no safe non-placeholder endpoint was available to run `test/containers-test.sh --scenario steamdeck-host --action cycle`.
- Why unresolved: external/private environment boundary.
- Needed next: Source approved local private endpoint bindings, run bounded `cycle`, confirm nested rows pass, then final `down` cleanup.

## Files changed
- `README.md`
- `docker/ovpn-client-test/entrypoint.sh`
- `docker/vpnkit/entrypoint.sh`
- `scripts/vpnkit-steamdeck-client-test.sh`
- `scripts/vpnkit-test-lab-setup.sh`
- `test/containers-test.sh`
- `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/plan.md`
- `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/progress/slice-owner.md`
- `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/verification/nested-vpn.md`

## Commits pushed
- `78f2d1b` — `test: add nested OpenVPN lab acceptance` pushed to `origin/feat/issue-24-smart-routing-manifest`.

## GitHub updates
- PR #26: https://github.com/blockedby/vibe-practicum-vpn/pull/26#issuecomment-4668888017
- Issue #27: https://github.com/blockedby/vibe-practicum-vpn/issues/27#issuecomment-4668888168

## Verdict
- Status: partial/blocked on live private environment.
- Goal state: implementation and safe verification complete; live acceptance not complete.
- Final readiness: not ready until live `steamdeck-host` cycle passes nested rows.
