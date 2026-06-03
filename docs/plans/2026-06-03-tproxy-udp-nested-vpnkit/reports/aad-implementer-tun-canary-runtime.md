PI_RESULT: PASS
TASK: Task 5 - Opt-in vpnkit sing-box TUN-mode runtime path
TASK_PACKAGE: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit
REPORT_PATH: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/aad-implementer-tun-canary-runtime.md
PROGRESS_PATH: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-tun-canary-runtime.md
COMMITS:
- pending: commit not created yet at report-write time
FILES_CHANGED:
- config/sing-box/config.tun.json.template: new opt-in sing-box TUN inbound template with `vpnkit-tun-in` on `sb-tun0`, DNS direct inbound, SOCKS loopback inbound, direct/private/rule-set routing, and selected native outbound final.
- docker/vpnkit/entrypoint.sh: selects `/etc/sing-box/config.tun.json` for `VPNKIT_ROUTING_MODE=tun` and uses mode-specific readiness for redirect, tproxy, and tun.
- docker/vpnkit/setup-routing.sh: keeps tun mode policy-route-only and adds a bounded wait for the sing-box TUN interface; no redirect/tproxy capture rules are installed in tun mode.
- scripts/vpnkit-render-local-configs.sh: renders/chmods/reports `config.tun.json` alongside redirect/tproxy rendered configs.
- tests/vpnkit-singbox-template-test.sh: adds tun template, entrypoint, and render-script assertions while preserving redirect/tproxy assertions.
- tests/vpnkit-setup-routing-test.sh: adds tun dry-run assertions for policy route/rule and absence of redirect/tproxy capture rules.
- docs/DOCKER_SETUP.md: documents opt-in `VPNKIT_ROUTING_MODE=tun` canary behavior and default redirect preservation.
- docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/tun-canary-runtime.md: automated verification evidence.
AC_VERIFICATION:
- Redirect/default mode selects existing redirect template/readiness and remains unchanged: template test asserts redirect inbound on 2082, DNS 5353, and no tun/tproxy inbound; entrypoint defaults to redirect config — passed.
- Tproxy mode remains available/unchanged: template test asserts tproxy inbound 2082, redirect TCP 2083, DNS 5353, UDP route rule order, and readiness still checks tproxy ports — passed.
- Tun mode selects a TUN sing-box config/template with clear inbound tag/interface/address/MTU/stack and loop-avoidance route design: `config.tun.json.template` has `vpnkit-tun-in`, `sb-tun0`, `172.19.0.1/30`, MTU 1400, `stack=mixed`, `auto_route=false`, `route.auto_detect_interface=true`, direct rules for TUN/private ranges, DNS detour via selected outbound, and final selected native outbound — passed by template test and sing-box check.
- `setup-routing.sh` tun branch installs only needed route/policy for OpenVPN client CIDR and no redirect/tproxy capture rules: dry-run test asserts route/rule and rejects `OVPN_TO_SINGBOX`, `TPROXY`, `REDIRECT --to-ports`, and `OVPN_REDIRECT_TO_SINGBOX` — passed.
- Entry point/readiness waits for tun-mode readiness signals and not redirect/tproxy-only ports: entrypoint now waits for `sb-tun0`, `172.19.0.1/30`, and UDP 5353 in tun mode; redirect/tproxy use separate port readiness — passed by source/test and local lab readiness in Task 6 partial validation.
- Render/template tests cover tun selection/syntax and route/readiness expectations: template/setup-routing tests plus dummy `sing-box check` on redirect/tproxy/tun — passed.
TESTS_RUN:
- `bash tests/vpnkit-singbox-template-test.sh`: passed.
- `bash tests/vpnkit-setup-routing-test.sh`: passed.
- `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh`: passed.
- `go test ./...`: passed.
- Dummy rendered `sing-box check` for redirect/tproxy/tun templates with `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true`: passed with deprecation warnings only.
- `git diff --check`: passed.
QUALITY_CHECKS:
- Shell syntax: `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh` passed.
- Go tests: `go test ./...` passed.
- Config validation: dummy redirect/tproxy/tun `sing-box check` passed with required deprecation env flags; warnings are inherited from existing DNS config style.
- Whitespace/static: `git diff --check` passed.
QUALITY_NOTES:
- Readability/reuse: reused existing mode branching, template shape, route/outbound structure, dry-run helpers, and tests; no new dependency or broad abstraction.
- Error handling/logging: preserved existing startup failure style; tun readiness/setup waits now have bounded timeout messages.
- Backend/API/data: not relevant.
- Frontend/UI: not relevant.
- DevOps/runtime: added opt-in config/render/entrypoint/routing/doc wiring; default redirect path remains default; tun uses policy route from `OVPN_CIDR` instead of global `auto_route` to avoid self-routing sing-box egress.
- Security: no secrets, endpoint values, profiles, rendered config contents, or raw logs committed; live/private values not printed.
- Concurrency/idempotency: setup-routing uses existing idempotent rule-add patterns where applicable; tun mode only replaces route and adds rule if absent.
- Compatibility/performance: redirect/tproxy modes preserved; tun mode is opt-in and avoids broad capture rules.
SIDE_FINDINGS:
- Blocking: none for Task 5 implementation.
- Non-blocking follow-up candidates: migrate sing-box DNS config away from deprecated legacy server/domain-resolver settings before sing-box 1.14 removes compatibility env flags.
NOTES: Task 5 runtime implementation evidence is green. Optional Task 6 local validation was also started and is reported separately; live/nested staged validation was not completed in this implementation pass.
