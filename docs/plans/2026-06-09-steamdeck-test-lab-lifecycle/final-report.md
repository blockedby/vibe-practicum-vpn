## Task
- Mission: Correct issue #27 / PR #26 Steam Deck lab lifecycle to make nested OpenVPN acceptance part of the existing `steamdeck-host` runner, not a separate testing silo.
- Target: `feat/issue-24-smart-routing-manifest`, existing `test/containers-test.sh --scenario steamdeck-host --action up|test|down|cycle` lifecycle.
- Boundaries: No default/prod `vpnkit` mutation; no private endpoint/profile/key/cert/rendered config/log disclosure; generated nested material remains ignored under the existing Steam Deck lab secret tree.
- Done when: Nested OpenVPN setup and required acceptance rows are implemented in the unified lifecycle, public docs/GitHub are corrected, safe checks pass, and live Deck cycle is green or honestly blocked.

## Context
- GitHub issue: https://github.com/blockedby/vibe-practicum-vpn/issues/27
- Related PR: https://github.com/blockedby/vibe-practicum-vpn/pull/26
- Related issue: #24
- Task package: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle`
- Slice report: `reports/slice-owner-nested-vpn.md`
- Root verification: `verification/root-integration.md`
- Acceptance audit: `reports/acceptance-auditor-nested-vpn.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-24-smart-routing-manifest`
- Branch: `feat/issue-24-smart-routing-manifest`

## Spec compliance
- Requirement: Keep the unified runner/scenario.
  - Status: done.
  - Evidence: nested acceptance is wired into `test/containers-test.sh --scenario steamdeck-host --action ...`; no new user-facing scenario/root was introduced.
- Requirement: Generate nested lab material under existing ignored Steam Deck lab structure.
  - Status: done.
  - Evidence: `scripts/vpnkit-test-lab-setup.sh` generates nested OpenVPN server/client material under `secrets/vpnkit-labs/steamdeck-host/nested/openvpn/...`; temp smoke verified generation without printing contents.
- Requirement: Manage nested target/checks through existing lifecycle.
  - Status: done.
  - Evidence: `docker/vpnkit/entrypoint.sh`, `docker/ovpn-client-test/entrypoint.sh`, `scripts/vpnkit-steamdeck-client-test.sh`, and `test/containers-test.sh` integrate nested server/client behavior into the existing lab container/client smoke flow.
- Requirement: Nested acceptance rows are required.
  - Status: done for harness behavior.
  - Evidence: required rows include `client:nested-route-via-tun0`, `client:nested-handshake`, `client:nested-tun1`, and `client:nested-ping-peer`; explicit disable via `VPNKIT_STEAMDECK_NESTED_VPN_ENABLED=0` reports not deploy-ready.
- Requirement: Public-safe docs/GitHub updates.
  - Status: done.
  - Evidence: README/task package updated; slice posted public-safe PR #26 and issue #27 comments.
- Requirement: Live Deck cycle green including nested rows.
  - Status: blocked/not run.
  - Evidence: `config/private-endpoints.local.env` is absent in this worktree, so no authorized non-placeholder Deck binding was available. Do not claim deploy readiness.

## Acceptance verification
- Unified lifecycle:
  - Covered by: code/docs review plus slice report.
  - Result: passed.
  - Evidence: `reports/slice-owner-nested-vpn.md` and `verification/root-integration.md`.
- Nested generated material public safety:
  - Covered by: setup smoke and tracked artifact guard.
  - Result: passed.
  - Evidence: `verification/nested-vpn.md`; `verification/root-integration.md` guard passed.
- Nested route/handshake/tun/ping live behavior:
  - Covered by: harness implementation only; live proof missing.
  - Result: not run.
  - Evidence: acceptance audit AC7 blocks readiness until live `cycle` runs with nested rows.
- Repo checks:
  - Covered by: fresh root verification.
  - Result: passed.
  - Evidence: `bash -n`, Python compile/proof, `go test ./...`, `go vet ./...`, `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`, sensitive artifact guard all passed in `verification/root-integration.md`.

## System readiness
- Routes / registration: not applicable.
- Services / APIs: not applicable.
- Config / env / secrets: partial; lab nested config is wired and generated under ignored paths, but live private endpoint binding is unavailable here.
- Permissions / access: blocked for live Deck acceptance in this worktree.
- Database / migrations: not applicable.
- Runtime / deployment wiring: implementation is wired for lab lifecycle; deploy readiness remains blocked until live nested cycle passes.

## Verification run
- Local / targeted checks:
  - `bash -n test/containers-test.sh scripts/vpnkit-test-lab-setup.sh scripts/vpnkit-steamdeck-client-test.sh scripts/vpnkit-steamdeck-podman.sh docker/ovpn-client-test/*.sh docker/vpnkit/entrypoint.sh`: passed.
  - `python3 -m py_compile scripts/*.py test/*.py`: passed.
  - `python3 test/sing-box-smart-routing-proof.py`: passed.
- Local / full checks:
  - `go test ./...`: passed.
  - `go vet ./...`: passed.
  - `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: passed.
  - Sensitive tracked artifact guard: passed/no matches.
- Remote/live checks:
  - `test/containers-test.sh --scenario steamdeck-host --action cycle`: not run; missing gitignored private endpoint env in this worktree.
  - Final cleanup `down`: not run for the same reason; no live lab was started by this root integration pass.

## Issues
### Issue U-01: Live nested Deck cycle evidence missing
- Description: The corrected nested acceptance is implemented and statically verified, but the required live isolated Deck `cycle` with nested rows was not run.
- Evidence: `verification/root-integration.md` reports private env unreadable; acceptance auditor marks AC7 not run.
- Why unresolved: private/environment access boundary, not a code path the agent can safely invent or print.
- Needed next: On an authorized machine/worktree with `config/private-endpoints.local.env`, run `test/containers-test.sh --scenario steamdeck-host --action cycle`, verify nested rows pass, then run/confirm final cleanup `down`.

## Side findings
- Blocking findings folded into active work: nested acceptance missing from the unified lifecycle was folded into this implementation.
- Non-blocking findings tracked separately: none added.

## Verdict
- Status: partial / blocked on live environment.
- Goal state: implementation and safe local verification achieved; required live deploy-readiness proof not achieved.
- Final readiness: not deploy-ready until live `steamdeck-host` cycle is green with nested rows.
- Summary: The PR now encodes nested VPN as required existing-lifecycle acceptance, but root completion is blocked by missing authorized live Deck bindings in this worktree.
