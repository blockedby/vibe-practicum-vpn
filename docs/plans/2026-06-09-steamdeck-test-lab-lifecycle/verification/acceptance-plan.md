## Acceptance plan: nested OpenVPN inside existing Steam Deck lifecycle

### Acceptance criteria to audit
- AC1: Unified entry remains `test/containers-test.sh --scenario steamdeck-host --action up|test|down|cycle`.
- AC2: Nested OpenVPN material is generated under ignored `secrets/vpnkit-labs/steamdeck-host/nested/openvpn/...` and is not tracked or printed.
- AC3: Nested target/lifecycle management is wired into the existing lab lifecycle, not a separate scenario/root.
- AC4: Required nested rows fail acceptance unless explicitly disabled (`VPNKIT_STEAMDECK_NESTED_VPN_ENABLED=0` must mark not deploy-ready).
- AC5: Public-safe docs/GitHub updates describe nested VPN as part of the existing lifecycle.
- AC6: Repo safety checks pass (shell/static/proof/go/sensitive artifact guard).
- AC7: Live Steam Deck cycle evidence exists for the nested acceptance path, or the blocker is precisely classified and readiness is withheld.

### Evidence sources to inspect
- `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/verification/nested-vpn.md`
- `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/reports/slice-owner-nested-vpn.md`
- `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/final-report.md`
- `docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/verification/root-final-live-green.md`
- `README.md`
- `test/containers-test.sh`
- `scripts/vpnkit-test-lab-setup.sh`
- `scripts/vpnkit-steamdeck-client-test.sh`
- `docker/ovpn-client-test/entrypoint.sh`
- `docker/vpnkit/entrypoint.sh`

### Audit decision rule
- Accept only if AC1-AC6 are directly evidenced and AC7 has fresh live-cycle proof for the nested rows.
- If AC7 is missing, stale, or blocked by private Deck bindings, report not accepted / blocked with the exact missing live evidence.
