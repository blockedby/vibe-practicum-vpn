PI_RESULT: PASS
TASK: vpnkit compatibility bypass / Task 1 scoped routing bypass
TASK_PACKAGE: docs/plans/2026-06-02-vpnkit-compat-bypass
REPORT_PATH: docs/plans/2026-06-02-vpnkit-compat-bypass/reports/aad-implementer-routing.md
PROGRESS_PATH: docs/plans/2026-06-02-vpnkit-compat-bypass/progress/aad-implementer-routing.md
COMMITS:
- c4d0cc7cbcfe3824e4a339d1338c273028bf57bd: Add scoped vpnkit compatibility bypass
- dd6bc85ee30f40d14857c7785d883065f4e5999e: Add compat bypass implementation report
FILES_CHANGED:
- docker/vpnkit/setup-routing.sh: added redirect-mode compatibility bypass envs, endpoint parsing/validation, hostname-to-IPv4 resolution, dry-run rendering for tests, scoped RETURN/FORWARD/MASQUERADE rules for configured endpoint IP/proto/port, and optional endpoint-only ICMP direct rules.
- docker-compose.yml: wired compatibility bypass env defaults and made routing mode configurable with redirect as default.
- docs/CONTAINERIZED_VPNKIT_RUNBOOK.md: documented scoped compatibility bypass usage, defaults, explicit proto syntax, optional ICMP, and no-broad-NAT behavior.
- scripts/vpnkit-routing-compat-bypass-test.sh: added lightweight dry-run rendering test for positive UDP/TCP/ICMP rule shape and negative invalid/conflicting proto cases.
- docs/plans/2026-06-02-vpnkit-compat-bypass/plan.md: updated execution ledger.
- docs/plans/2026-06-02-vpnkit-compat-bypass/progress/aad-implementer-routing.md: recorded implementation progress.
- docs/plans/2026-06-02-vpnkit-compat-bypass/verification/local.md: recorded local verification evidence.
AC_VERIFICATION:
- Redirect mode still sends TCP and UDP/53 to sing-box: `bash scripts/vpnkit-routing-compat-bypass-test.sh` asserts rendered `-p tcp -j REDIRECT --to-ports 2082` and `-p udp --dport 53 -j REDIRECT --to-ports 5353`; default endpoint dry-run also showed these redirect rules after endpoint RETURN — passed.
- Direct rules only apply to configured endpoint IP/proto/port plus optional ICMP: render test asserts endpoint-specific RETURN and MASQUERADE for `198.51.100.10:1194/udp` and `203.0.113.20:443/tcp`, endpoint-only ICMP when enabled, and no broad rendered `POSTROUTING -s 10.89.0.0/24 -j MASQUERADE` — passed.
- Support `vpn.proofix.tv:1194` default UDP and explicit proto config: compose config exposes default `VPNKIT_COMPAT_BYPASS_ENDPOINTS=vpn.proofix.tv:1194`; dry-run with compatibility enabled resolved default host and rendered UDP/1194 RETURN; render test covers explicit `/tcp` and rejects invalid/conflicting proto — passed.
- No broad direct VPS NAT: source grep over `docker/vpnkit/setup-routing.sh docker-compose.yml` found no broad OpenVPN-client POSTROUTING MASQUERADE; docs retain no-broad-NAT language — passed.
TESTS_RUN:
- `bash scripts/vpnkit-routing-compat-bypass-test.sh`: passed.
- RED evidence: same test failed before production changes because current script attempted live iptables and lacked dry-run/compat bypass rendering — expected red failure observed.
QUALITY_CHECKS:
- `bash -n docker/vpnkit/setup-routing.sh scripts/vpnkit-routing-compat-bypass-test.sh`: passed.
- `shellcheck docker/vpnkit/setup-routing.sh scripts/vpnkit-routing-compat-bypass-test.sh`: not run; `shellcheck` is not installed in this environment.
- `docker compose config >/tmp/vpnkit-compose-config.out`: passed.
- Broad NAT source grep: passed/no matches in routing/compose source.
- `git diff --check`: passed.
QUALITY_NOTES:
- Readability/reuse: reused existing `setup-routing.sh` env/default and iptables-chain style; added small shell helpers only for validation, dry-run rendering, and idempotent rule attachment needed by this task.
- Error handling/logging: invalid ports/protos/conflicting protocol declarations and unresolved hosts fail fast with explicit stderr messages; existing routing mode error behavior preserved.
- Backend/API/data: not relevant.
- Frontend/UI: not relevant.
- DevOps/runtime: compose defaults are disabled-by-default; default endpoint is narrow and documented; hostname resolution occurs at container startup with all returned IPv4s receiving scoped rules.
- Security: no secrets, generated profiles, logs, or private env values touched; no broad OpenVPN-client NAT added.
- Concurrency/idempotency: compatibility chains are flushed/rebuilt on setup; jump rules use `iptables -C` before append to avoid duplicate parent jumps.
- Compatibility/performance: redirect mode still installs TCP and UDP/53 sing-box rules; non-matching traffic is not accepted/NATed by the compatibility chain; dry-run test mode has no runtime effect unless explicitly enabled.
SIDE_FINDINGS:
- Blocking: none.
- Non-blocking follow-up candidates: shellcheck could be run by an environment that has it installed; live container/OpenVPN runtime validation was outside scope and not run.
NOTES: No live VPS mutation performed. Branch `vpnkit-compat-bypass` was pushed to `origin` after implementation/report commits.
