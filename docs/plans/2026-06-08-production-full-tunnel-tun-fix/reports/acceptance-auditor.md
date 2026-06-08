## Task
- Mission: Audit the completed urgent production full-tunnel TUN fix for acceptance readiness.
- Target: `docs/plans/2026-06-08-production-full-tunnel-tun-fix/` evidence plus the tracked TUN source/runtime wiring.
- Boundaries: no source edits; public-safe evidence only; flag any secret/private endpoint leakage.
- Done when: each root requirement has fresh evidence or an explicit waiver, and the rollout/profile checks are proven.
- Expected evidence: source durability, both-server TUN runtime, safe rollback/mutation refs, failover DNS reachability, and domain/endpoint profile checks including ICMP.

## Context
- Task package: `docs/plans/2026-06-08-production-full-tunnel-tun-fix`
- Report path: `docs/plans/2026-06-08-production-full-tunnel-tun-fix/reports/acceptance-auditor.md`
- Acceptance plan path: `docs/plans/2026-06-08-production-full-tunnel-tun-fix/verification/acceptance-plan.md`
- Repo state: `main` at `db81bc0` (root final verification commit)

## Spec compliance
- Durable source support: done. Tracked TUN template/renderer/routing test/docs exist and were checked fresh.
- Both production servers in TUN mode: done. `vibe-practicum` and `moscow-tiger` both report `routing_mode=tun`, `openvpn=up`, `singbox=up`, `sb_tun0=up`, policy rule and route table OK.
- Safe mutation / rollback refs: done. Evidence records preserved `.env`, rollback image/env refs, derived `OVPN_CIDR` from rendered config, cleared stale persisted sing-box config, and recreated only `vpnkit`.
- Failover DNS / endpoints: done. Evidence shows 2 distinct A records and both endpoints reachable.
- Failover profile checks: done. Domain, endpoint1, and endpoint2 all passed OpenVPN, tun0 routing, DNS, HTTPS, literal-IP HTTPS, and ping 1.1.1.1 / 8.8.8.8.
- Secret leakage review: done. No private endpoint values or secrets were found in the provided reports; only redacted placeholders (`<IP>`) and public-safe paths/labels.

## Acceptance verification
- AC1: Durable repo/source support for TUN/full-tunnel production mode
  - Covered by: `verification/source-local.md`; tracked files `config/sing-box/config.tun.json.template`, `scripts/vpnkit-render-local-configs.sh`, `docker/vpnkit/setup-routing.sh`, `tests/vpnkit-production-routing-wiring-test.sh`, `docs/DOCKER_SETUP.md`
  - Result: passed
- AC2: `VPNKIT_ROUTING_MODE=tun` deployed on `vibe-practicum` and `moscow-tiger`
  - Covered by: `verification/production-runtime.out`
  - Result: passed
- AC3: safe mutation, `OVPN_CIDR` derivation, rollback refs, stale config cleanup, recreate only vpnkit
  - Covered by: `reports/full-tunnel-fix-slice.md` and `final-report.md`
  - Result: passed
- AC4: per-server runtime checks pass
  - Covered by: `verification/production-runtime.out`
  - Result: passed
- AC5: failover DNS has both A records and both endpoints reachable
  - Covered by: `verification/failover-dns.md`
  - Result: passed
- AC6: `phone.ovpn` domain/endpoint1/endpoint2 checks, route via `tun0`, DNS, HTTPS, literal-IP HTTPS, ping 1.1.1.1/8.8.8.8
  - Covered by: `verification/root-final-profile-rerun.out`, plus `profile-domain.out`, `profile-endpoint1.out`, `profile-endpoint2.out`
  - Result: passed
- AC7: ping failures classified and fixed before done
  - Covered by: `reports/full-tunnel-fix-slice.md` and `final-report.md`
  - Result: passed
- AC8: final report completeness
  - Covered by: `final-report.md`
  - Result: passed

## System readiness
- Routes / registration: not relevant.
- Services / APIs: covered by runtime checks on both production servers.
- Config / env / secrets: covered; `.env` preserved and `OVPN_CIDR` handled safely.
- Permissions / access: covered implicitly by SSH/container/runtime checks; no access regression evidence.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: covered; TUN mode, sing-box, OpenVPN, policy routing, and stale config cleanup verified.

## Verification run
- Targeted checks: fresh
  - `bash -n scripts/*.sh docker/vpnkit/*.sh tests/*.sh`
  - `tests/vpnkit-production-routing-wiring-test.sh`
  - `go test ./...`
- Full local checks: fresh enough for this slice
  - Production runtime verification on both servers
  - Failover DNS verification
  - Root final profile rerun for domain, endpoint1, endpoint2
- Remote checks / CI: not checked; PR status rollup was empty / no CI status evidence was available in the provided reports.

## Issues
- R-01: Initial ICMP failure after first TUN rollout was caused by mismatched production `OVPN_CIDR`; it was corrected and re-verified successfully.
- No unresolved `F-*` or `U-*` issues remain for the requested acceptance target.

## Side findings
- Non-blocking caveat: `duplicate_redirect_warning=yes` appears in profile output, but all required route/DNS/HTTPS/ICMP checks still pass.
- Secret/private endpoint leakage: none found in the provided reports.

## Verdict
- Status: success
- Goal state: fully achieved
- Final readiness: ready
- Summary: The urgent production full-tunnel TUN fix is acceptable; every stated acceptance criterion is backed by fresh, public-safe evidence.
