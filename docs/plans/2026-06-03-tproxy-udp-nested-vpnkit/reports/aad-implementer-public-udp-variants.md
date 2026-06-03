PI_RESULT: FAIL
TASK: Task 4 - Public non-DNS UDP TPROXY variants matrix
TASK_PACKAGE: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit
REPORT_PATH: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/aad-implementer-public-udp-variants.md
PROGRESS_PATH: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-public-udp-variants.md

COMMITS:
- pending at report-write time

FILES_CHANGED:
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/public-udp-variants-matrix.md`: replaced partial matrix with fresh sanitized per-variant evidence.
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/aad-implementer-public-udp-variants.md`: implementation report.
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-public-udp-variants.md`: progress ledger.
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/plan.md`: Task 4 execution ledger update.

AC_VERIFICATION:
- AC-I1: All seven variants attempted in order or marked infeasible — passed for execution coverage. Variants 1-4 ran live and failed by timeout; Variant 5 attempted twice and failed nft setup; Variant 6 marked infeasible with current tun-mode wiring reason; Variant 7 ran live and failed by timeout. Evidence: `verification/public-udp-variants-matrix.md`.
- AC-I2: Evidence distinguishes public generic UDP TPROXY from private bypass — passed for variants 1-4: route via client `tun0`, generic public TPROXY `1/51`, private bypass counters `0/0`, no echo response. Variant 7 showed generic TPROXY `0/0` after temp bypass insertion, also distinguishing paths.
- AC-I3: Robust source/config fix — no robust fix emerged. No source/test changes were made; committed changes are sanitized docs/reports only.
- AC-I4: Production containers and Steam Deck untouched — passed by safe metadata: `vpnkit` and `current-vpnkit-1` stayed running with restart count 0 and identical start times before/after. Steam Deck not contacted.
- AC-I5: Isolated resource cleanup — passed after follow-up cleanup. Server projects/temp paths and echo containers were removed; root-owned temp log directories from an invalid same-host pre-run required non-interactive sudo cleanup.
- AC-I6: No generated artifacts/secrets committed — passed for git artifacts. Safety caveat: a discarded temp client-log inspection exposed one private endpoint value in terminal output; the temp log/profile/tarball artifacts were deleted and no endpoint value is present in committed files.
- AC-I7: Final report states working/failed variants, cleanup, production untouched, recommendation — passed in matrix/report. Working variants: none. Failed variants: 1-4, 7. Setup/infeasible: 5-6. Recommendation: do not claim generic public UDP TPROXY support; follow up with validated nft TPROXY or explicit public UDP endpoint bypass design.

TESTS_RUN:
- `bash tests/vpnkit-setup-routing-test.sh`: passed.
- `bash tests/vpnkit-singbox-template-test.sh`: passed.
- `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh`: passed.
- `go test ./...`: passed.
- `git diff --check`: passed.
- `git status --short`: run before edits (clean) and after edits (only task-package docs/progress/report dirty before commit).

QUALITY_CHECKS:
- Runtime/live harness: executed temp-only with fresh high ports `23442-23455/udp` for valid matrix plus nft retry `23550/23551/udp`; no production compose projects reused.
- Cleanup check: follow-up `docker ps`/`docker network ls`/`ls /tmp/vpnkit_pubudp_v*` checks found no remaining isolated resources after cleanup.
- Static/source checks: all required commands above passed; no source files changed.

QUALITY_NOTES:
- Readability/reuse: Reused existing docker-compose/runtime layout and task-package reporting; no new abstraction committed.
- Error handling/logging: Raw logs/tcpdump/profile/config artifacts stayed temp and were deleted; committed report contains only counts/summaries.
- Backend/API/data: not relevant.
- Frontend/UI: not relevant.
- DevOps/runtime: Used isolated Docker projects/containers/ports/temp paths; production metadata was read-only; no production container lifecycle commands were run.
- Security: No secrets or endpoint values are in committed artifacts. Safety caveat recorded above for one terminal-output exposure from a discarded temp log.
- Concurrency/idempotency: Each variant used unique resource names/ports; cleanup was exact-name based.
- Compatibility/performance: No application/runtime source changed; production/default behavior unchanged.

SIDE_FINDINGS:
- Blocking: Generic public non-DNS UDP through current sing-box TPROXY remains failing/not proven. Variants 1-4 timed out after generic public TPROXY accepted one packet and private bypass stayed zero.
- Blocking: nftables TPROXY canary needs a validated nft ruleset before live probing; ad-hoc temp rules were rejected by nft syntax.
- Non-blocking follow-up candidates: Prototype an operator-configured public UDP endpoint/port bypass in a dedicated source/test slice; separately validate sing-box TUN mode only after adding a real tun inbound template and startup/readiness changes.

NOTES:
- The same-host echo topology was discarded because the echo target route selected the OpenVPN transport interface instead of outer `tun0`.
- No robust fix was implemented in this task because all feasible live comparisons failed or were setup-infeasible.
