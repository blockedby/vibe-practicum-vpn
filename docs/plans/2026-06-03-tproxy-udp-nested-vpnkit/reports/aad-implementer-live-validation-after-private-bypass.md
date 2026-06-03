PI_RESULT: PASS
TASK: Live isolated validation after private UDP bypass fix
TASK_PACKAGE: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit
REPORT_PATH: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/aad-implementer-live-validation-after-private-bypass.md
PROGRESS_PATH: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-live-validation-after-private-bypass.md
COMMITS:
- pending: report/progress/verification artifacts not yet committed
FILES_CHANGED:
- docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/live-validation-after-private-bypass.md: sanitized live validation evidence, pass/fail matrix, cleanup status, and public/private UDP distinction.
- docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/aad-implementer-live-validation-after-private-bypass.md: implementation report.
- docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-live-validation-after-private-bypass.md: progress notes.
AC_VERIFICATION:
- Unique fresh names/ports/networks/volumes/temp paths: used fresh `21470/udp`, `21471/udp`, `21472/udp`, `21473/udp`, `21475/udp`, `21478/udp`, and `21479/udp` with isolated project/container/network/temp names listed in the verification artifact — passed.
- No production mutation / no Steam Deck / no secrets or raw logs: only safe production `docker inspect` metadata was captured; production `vpnkit` stayed `status=running restart=0` with the same start time before/mid/after; no endpoint/profile/PKI/rendered config/raw log content printed or committed — passed.
- Stage 1 baseline on vibe-practicum: isolated server/client passed OpenVPN, UDP DNS `NOERROR`, HTTPS hostname `200`, and literal-IP HTTPS `200` on `21470/udp`; focused true nested run repeated baseline on `21478/udp` — passed.
- Stage 1 nested private OpenVPN: focused same-host client isolated from the inner Docker network connected to outer `21478/udp`; route to inner endpoint was via `tun0`; inner OpenVPN reached `tun1`; private UDP bypass counters incremented — passed.
- Stage 2 baseline on moscow-tiger: isolated moscow client connected to vibe-practicum isolated outer `21470/udp`; OpenVPN, UDP DNS `NOERROR`, HTTPS hostname `200`, and literal-IP HTTPS `200` passed — passed.
- Stage 2 nested private OpenVPN: moscow client route to inner endpoint was via `tun0`; inner OpenVPN reached `tun1`; private UDP bypass counters incremented — passed.
- Reduced public non-DNS UDP echo: isolated echo process on moscow-tiger `21475/udp`; same-host vibe client route to echo endpoint was via outer `tun0`; echo timed out while the generic non-private UDP TPROXY counter incremented `1` packet / `44` bytes and private bypass counters stayed zero — attempted, failed for public UDP TPROXY egress, distinction recorded.
- Cleanup all isolated resources: final checks reported `vibe_final_leftovers=no` and `moscow_final_leftovers=no`; nothing retained — passed.
TESTS_RUN:
- Live full baseline/nested wrapper with projects `vpnkit_live_bypass_outer_21470` and `vpnkit_live_bypass_inner_21471`: passed Stage 1 baseline, Stage 2 baseline, Stage 2 nested, cleanup; same-host Stage 1 nested `tun1` came up but was superseded by the focused true nested route proof.
- Reduced public UDP echo wrapper with project `vpnkit_public_echo_outer_21473` and echo port `21475/udp`: public echo timed out with route via `tun0` and public UDP TPROXY counter increment; cleanup passed.
- Focused Stage 1 true nested wrapper with projects `vpnkit_stage1_nested_outer_21478` and `vpnkit_stage1_nested_inner_21479`: passed route-to-inner via `tun0`, inner `tun1`, counters, and cleanup.
QUALITY_CHECKS:
- `git diff --check`: passed.
- Formatter/lint/typecheck/build: not run; no production code, tests, templates, or config source files were modified in this delegated task.
QUALITY_NOTES:
- Readability/reuse: reused existing Docker Compose `vpnkit` and `docker/ovpn-client-test` patterns; no repo source abstraction added.
- Error handling/logging: kept raw OpenVPN/sing-box logs remote/temp only and removed them during cleanup; persisted only sanitized markers/counters.
- Backend/API/data: not relevant.
- Frontend/UI: not relevant.
- DevOps/runtime: validation used isolated high ports, projects, networks, volumes, images, temp dirs, and exact cleanup; production metadata was read-only and unchanged.
- Security: private env sourced without printing values; no secrets, profiles, PKI, rendered configs, endpoint values, or raw logs committed.
- Concurrency/idempotency: fresh names avoided existing runtime resources; cleanup commands were scoped to exact generated names and paths.
- Compatibility/performance: no source compatibility/performance changes; live validation shows private nested UDP path passes while public/non-private UDP TPROXY egress remains a behavior gap.
SIDE_FINDINGS:
- Blocking: none for executing the delegated validation and cleanup.
- Non-blocking follow-up candidates: investigate public/non-private UDP TPROXY egress; the reduced public echo check shows timeout with a generic UDP TPROXY counter increment, distinct from the passing private UDP bypass path.
NOTES: Validation evidence is operational evidence, not an acceptance verdict. The key distinction is now explicit: private nested OpenVPN-over-OpenVPN passes live on isolated resources, but public non-DNS UDP through generic TPROXY did not echo successfully.
