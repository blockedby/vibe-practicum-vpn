PI_RESULT: FAIL
TASK: matching-bundle nested TPROXY/UDP validation
TASK_PACKAGE: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit
REPORT_PATH: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/aad-implementer-matching-bundle-nested.md
PROGRESS_PATH: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-matching-bundle-nested.md
COMMITS:
- 88130ea: docs: record matching-bundle nested tproxy validation
FILES_CHANGED:
- docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/inner-nested-matching-bundle.md: sanitized runtime validation evidence
- docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/aad-implementer-matching-bundle-nested.md: implementation/validation report
- docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-matching-bundle-nested.md: progress notes
AC_VERIFICATION:
- Matching local bundle only: used the delegated gitignored `server.conf`, `pki/*`, `config.tproxy.json`, and `test-client.ovpn`; did not print secret contents; rewrote only temp profile `remote` lines — passed.
- Isolated outer+inner servers on vibe-practicum: started `vpnkit_match_outer_21342` on `21342/udp` and `vpnkit_match_inner_21343` on `21343/udp` on shared network `vpnkit_match_net_21342_21343`; OpenVPN initialized and tproxy listeners were present — passed after adding empty temp `ccd` directories required by the matching server config.
- moscow-tiger nested client: outer tunnel reached `OUTER_UP`; `ip route get <inner-container-ip>` showed `dev tun0`; inner client timed out and `tun1` never appeared — failed.
- Failure-path evidence: outer `OVPN_TO_SINGBOX` non-DNS UDP TPROXY counter increased to `15 packets / 1230 bytes`; DNS/TCP special-case counters stayed zero; outer-to-inner and inner `udp/1194` tcpdump captures had no packet lines; inner server showed no accepted client — failed for TPROXY forwarding to the inner OpenVPN server.
- Production untouched: `vpnkit` safe metadata remained `status=running restart=0 started=2026-06-02T13:47:35.235471647Z` before and after cleanup — passed.
- Cleanup: removed isolated moscow client container/image/temp path and vibe-practicum projects/containers/volumes/images/network/temp path; post-cleanup checks found no matching resources — passed.
TESTS_RUN:
- `git status --short`: passed pre-edit; only provided verification artifact was untracked/in-scope.
- Sanitized bundle preflight grep/checks: passed; no secret contents printed.
- `ssh vibe-practicum 'docker --version; docker compose version'`: passed.
- `ssh moscow-tiger 'docker --version; docker compose version'`: passed.
- Isolated runtime harness described in `verification/inner-nested-matching-bundle.md`: failed at inner OpenVPN `tun1` establishment.
QUALITY_CHECKS:
- Formatter/lint/typecheck/build: not run; no production code, tests, templates, or config source files were modified.
- Runtime isolation/cleanup check: passed; isolated resources removed and production metadata unchanged.
QUALITY_NOTES:
- Readability/reuse: reused existing Docker Compose service shape and `docker/ovpn-client-test` image pattern for the temporary harness; no reusable source abstraction added.
- Error handling/logging: captured only sanitized runtime excerpts and counters; did not persist raw logs or profiles.
- Backend/API/data: not relevant.
- Frontend/UI: not relevant.
- DevOps/runtime: used fresh ports `21342/udp` and `21343/udp`, unique projects/containers/network/temp paths, and no production mutation; empty temp `ccd` directories were needed because the matching server config requires the directory.
- Security: no secrets, PKI contents, profiles, auth values, or private endpoint values were committed or printed; remote/profile values were sanitized in evidence.
- Concurrency/idempotency: isolated names avoided existing production resources; cleanup commands were scoped to those names and paths only.
- Compatibility/performance: no source compatibility/performance changes; runtime evidence shows the current TPROXY/UDP path still fails for the nested OpenVPN forwarding case.
SIDE_FINDINGS:
- Blocking: none external; the decisive task result is a product/runtime failure: non-DNS UDP reaches the outer TPROXY rule but is not observed leaving toward or arriving at the inner OpenVPN server.
- Non-blocking follow-up candidates: investigate sing-box TPROXY UDP association/egress behavior for destinations on the same Docker network; consider a reduced UDP echo harness on the shared network before another OpenVPN nested run.
NOTES: Validation completed with negative evidence. AC2 full inner VPN-over-VPN should remain open: outer connect and route-to-inner via `tun0` were proven, but inner `tun1` did not establish and packet capture did not show egress/ingress to the inner server.
