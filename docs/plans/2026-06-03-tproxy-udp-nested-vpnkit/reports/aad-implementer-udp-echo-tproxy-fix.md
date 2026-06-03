PI_RESULT: PASS
TASK: tproxy UDP nested vpnkit blocker fix
TASK_PACKAGE: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit
REPORT_PATH: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/aad-implementer-udp-echo-tproxy-fix.md
PROGRESS_PATH: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-udp-echo-tproxy-fix.md
COMMITS:
- 978f3dd: Fix tproxy private UDP forwarding
FILES_CHANGED:
- docker/vpnkit/setup-routing.sh: added tproxy-mode-only private UDP bypass/MASQUERADE/FORWARD wiring before the terminal generic UDP TPROXY rule; redirect mode unchanged.
- tests/vpnkit-setup-routing-test.sh: added dry-run regression coverage for tproxy private UDP bypass chains/order and redirect-mode non-installation.
- docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/plan.md: appended execution ledger entry for this fix and local verification.
- docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-udp-echo-tproxy-fix.md: progress notes.
- docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/udp-echo-tproxy-fix.md: sanitized RED/GREEN/nested verification evidence.
AC_VERIFICATION:
- AC1 no production containers touched/no secrets committed: used isolated local Docker projects only (`udp_echo_fix_red2`, `udp_echo_fix_impl`, `udp_echo_fix_nested`); cleanup check found no `udp-echo-fix*` containers or `udp_echo_fix*` networks; no live/production/Steam Deck commands used — passed.
- AC2 reduced non-DNS UDP echo path: RED reproduced timeout with client route via `tun0`, pre-fix generic UDP TPROXY counter `1 packet / 49 bytes`, and no echo arrival; GREEN with source implementation passed (`udp-echo-client success bytes=21`, echo server received probe, private UDP bypass/NAT/FORWARD counters incremented) — passed with note that the confirmed fix bypasses terminal TPROXY for private UDP before the generic TPROXY rule.
- AC3 minimal source/test/doc changes preserve redirect default: only tproxy-mode branch installs new private UDP bypass; dry-run test verifies redirect mode does not install `OVPN_TPROXY_UDP_POST`; default redirect path unchanged — passed.
- AC4 fresh targeted tests/checks pass/source changes committed: targeted tests, shell syntax, sing-box check passed; commit `978f3dd` created — passed.
- AC5 nested OpenVPN rerun: feasible isolated local rerun passed after echo (`OUTER_UP`, route to inner private endpoint via `tun0`, `INNER_UP`, tun1 `10.90.0.2/24`, inner server accepted client) — passed locally.
TESTS_RUN:
- `bash tests/vpnkit-setup-routing-test.sh`: passed.
- `bash tests/vpnkit-singbox-template-test.sh`: passed.
- Reduced RED echo harness (`udp_echo_fix_red2`, port `21403/udp`): expected failure observed before fix simulation.
- Reduced GREEN echo harness (`udp_echo_fix_impl`, port `21404/udp`): passed with source implementation only.
- Isolated local nested OpenVPN rerun (`udp_echo_fix_nested`, port `21405/udp`): passed.
QUALITY_CHECKS:
- `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh`: passed.
- `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true sing-box check -c <temp rendered tproxy config>`: passed with existing deprecation warnings only.
- `go test ./...` / Go build: not run; task touched shell routing/tests/docs only, no Go source.
QUALITY_NOTES:
- Readability/reuse: reused existing `is_truthy`, `run`, `ensure_iptables_rule`, and compatibility-bypass chain patterns; no new dependency.
- Error handling/logging: preserved shell `set -euo pipefail`; added validation for enabled-but-empty private CIDR list.
- Backend/API/data: not relevant.
- Frontend/UI: not relevant.
- DevOps/runtime: tproxy-mode routing now has explicit private UDP bypass chains; default redirect mode and existing DNS/TCP special cases are preserved; bypass can be disabled with `VPNKIT_TPROXY_PRIVATE_UDP_BYPASS_ENABLED=false` or scoped with `VPNKIT_TPROXY_PRIVATE_UDP_BYPASS_CIDRS`.
- Security: no secrets/endpoints/profile contents logged or committed; CIDR env values are passed as quoted iptables arguments.
- Concurrency/idempotency: chains are created/flushed on setup like existing compat chains; hook rules use existing idempotent helper.
- Compatibility/performance: redirect mode unchanged; public/non-private UDP remains on existing TPROXY path; private UDP bypass is bounded to configured CIDRs and UDP only.
SIDE_FINDINGS:
- Blocking: none for delegated local implementation evidence.
- Non-blocking follow-up candidates: owner/auditor should decide whether live matching-bundle rerun is still required after the local nested pass; existing sing-box DNS deprecation warnings remain pre-existing.
NOTES: The reduced debugging loop showed the original generic UDP TPROXY path is terminal in this iptables backend and does not egress for private Docker-network targets. The implemented fix routes private UDP before that terminal target, which restores reduced echo and local nested OpenVPN-over-OpenVPN while keeping non-private UDP on TPROXY.
