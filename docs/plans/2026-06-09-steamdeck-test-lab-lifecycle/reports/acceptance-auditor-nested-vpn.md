## Task package
- Task name: Nested OpenVPN acceptance inside existing Steam Deck lifecycle
- Task package: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle`
- Report path: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/reports/acceptance-auditor-nested-vpn.md`
- Acceptance plan path: `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/verification/acceptance-plan.md`

## Acceptance verdict
- Status: blocked
- Summary: The nested OpenVPN wiring and safe local verification are evidenced, but the required fresh live Steam Deck `steamdeck-host --action cycle` proof for the nested rows is missing in this worktree.

## Acceptance coverage
- AC1: Unified runner remains `test/containers-test.sh --scenario steamdeck-host --action up|test|down|cycle`
  - Evidence present: README + harness script + verification report
  - Result: passed
  - Gap: none
- AC2: Nested lab material is generated under ignored `secrets/vpnkit-labs/steamdeck-host/nested/openvpn/...` and not tracked/printed
  - Evidence present: `scripts/vpnkit-test-lab-setup.sh` + `verification/nested-vpn.md`
  - Result: passed
  - Gap: none
- AC3: Nested target/lifecycle management is wired into the existing lab lifecycle, not a separate scenario/root
  - Evidence present: `docker/vpnkit/entrypoint.sh`, `docker/ovpn-client-test/entrypoint.sh`, `test/containers-test.sh`
  - Result: passed
  - Gap: none
- AC4: Required nested rows fail acceptance unless explicitly disabled
  - Evidence present: `test/containers-test.sh` nested row enforcement + `VPNKIT_STEAMDECK_NESTED_VPN_ENABLED=0` fail-not-ready path
  - Result: passed
  - Gap: none
- AC5: Public-safe docs/GitHub updates describe nested VPN as part of the existing lifecycle
  - Evidence present: README text plus issue/PR comment links in `reports/slice-owner-nested-vpn.md`
  - Result: passed
  - Gap: none
- AC6: Repo safety checks pass and sensitive artifact guard is clean
  - Evidence present: `verification/nested-vpn.md`
  - Result: passed
  - Gap: none
- AC7: Fresh live Steam Deck cycle evidence exists for the nested acceptance path
  - Evidence present: none in current nested task evidence; `verification/nested-vpn.md` explicitly says live cycle was not run because `config/private-endpoints.local.env` was absent
  - Result: not run
  - Gap: missing fresh bounded live cycle with nested rows on an authorized non-placeholder Deck binding

## System readiness coverage
- Routes / registration: not relevant
- Services / APIs: not relevant
- Config / env / secrets: partial; nested env/docs are wired, but the live Deck binding source needed for the cycle is absent in this worktree
- Docker / containers: covered for lab entrypoints and nested client/server startup wiring
- Permissions / access: blocked for live acceptance; Deck SSH/private endpoint access not available here
- Database / migrations: not relevant
- Frontend-backend integration: not relevant
- Runtime / deployment wiring: partially covered by scripts and entrypoints, but live nested cycle proof is missing

## Check freshness
- Targeted checks: fresh
- Full local checks: fresh
- Remote checks / CI: not checked; no fresh CI evidence was provided for the nested change

## Required before done
- Provide authorized non-placeholder Steam Deck bindings (or equivalent local private endpoint env), rerun `test/containers-test.sh --scenario steamdeck-host --action cycle`, and capture fresh nested row evidence plus final `down` cleanup.
- If live access remains unavailable, record the blocker explicitly as a private/environment boundary rather than implying readiness.

## Files written
- `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/verification/acceptance-plan.md`: created
- `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/reports/acceptance-auditor-nested-vpn.md`: created
