PI_RESULT: PASS
TASK: Task 6 - TUN canary staged validation and recommendation (partial local-only continuation)
TASK_PACKAGE: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit
REPORT_PATH: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/aad-implementer-tun-canary-validation.md
PROGRESS_PATH: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-tun-canary-validation.md
COMMITS:
- pending: commit not created yet at report-write time
FILES_CHANGED:
- docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/tun-canary-result-matrix.md: sanitized local Docker lab matrix and not-run live/nested entries.
- docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-tun-canary-validation.md: progress notes for optional local validation and cleanup.
AC_VERIFICATION:
- Local Docker lab baseline in TUN mode: isolated Compose project `vpnkit_tun_canary_lab_21510` on `21510/udp`; OpenVPN client connected, UDP DNS returned `NOERROR`, HTTPS hostname returned `200`, literal-IP HTTPS returned `200` — passed.
- Local TUN runtime evidence: `sb-tun0` had `172.19.0.1/30`, policy rule `from 10.89.0.0/24 lookup 101`, table 101 default via `172.19.0.2 dev sb-tun0`, RX/TX packet counters incremented, and redirect/tproxy capture chains were absent — passed.
- Local public non-DNS UDP echo: not run in this continuation; only UDP DNS baseline was proven — not run.
- Live same-host/different-host/nested validation: not run; no live-host mutation attempted — not run.
- Cleanup: `docker compose -p vpnkit_tun_canary_lab_21510 down -v --remove-orphans`; final checks found no matching containers/networks — passed.
- Production untouched: no production containers, live hosts, or Steam Deck were mutated — passed.
TESTS_RUN:
- `scripts/vpnkit-render-local-configs.sh`: failed before local lab because gitignored source PKI files under `secrets/vps/openvpn/pki/` were missing; existing gitignored rendered OpenVPN/client configs were present.
- Gitignored tun config creation from existing rendered selected outbound plus `sing-box check -c secrets/vps/rendered/sing-box/config.tun.json` with deprecation env flags: passed with warnings only; config contents not printed.
- `docker compose -p vpnkit_tun_canary_lab_21510 up -d --build vpnkit`: passed.
- TUN readiness probe with `docker compose -p vpnkit_tun_canary_lab_21510 exec -T vpnkit ...`: passed.
- `docker compose -p vpnkit_tun_canary_lab_21510 --profile test run --rm ovpn-client-test`: passed baseline DNS/HTTPS/literal-IP checks.
- Capture-chain absence probes inside vpnkit container: passed.
- `docker compose -p vpnkit_tun_canary_lab_21510 down -v --remove-orphans` plus leftover checks: passed.
QUALITY_CHECKS:
- Local container startup/smoke: passed for isolated TUN-mode lab.
- Cleanup check: passed; no matching isolated containers/networks remained.
QUALITY_NOTES:
- Readability/reuse: validation reused existing Docker Compose lab and ovpn-client-test smoke path.
- Error handling/logging: did not print raw logs beyond client-test sanitized/public output; no secret config contents printed.
- Backend/API/data: not relevant.
- Frontend/UI: not relevant.
- DevOps/runtime: local TUN mode startup, readiness, routing policy, and absence of redirect/tproxy capture chains were directly observed.
- Security: generated `config.tun.json` stayed gitignored; no profiles/secrets/private endpoints/rendered config contents committed or printed.
- Concurrency/idempotency: unique Compose project/port avoided existing resources; cleanup removed resources.
- Compatibility/performance: validation only touched isolated Docker resources; no production mutation.
SIDE_FINDINGS:
- Blocking: full render from source is blocked locally by missing gitignored PKI source files, though existing rendered OpenVPN/client configs were enough for local lab.
- Non-blocking follow-up candidates: complete Task 6 live same-host/different-host/nested validation and public non-DNS UDP echo with owner-approved isolated resources.
NOTES: Partial Task 6 local canary evidence is positive. This is not a full staged-validation acceptance claim because public non-DNS UDP echo, live, and nested stages were not run.
