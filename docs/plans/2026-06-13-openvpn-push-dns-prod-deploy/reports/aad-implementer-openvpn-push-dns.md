PI_RESULT: PASS
TASK: OpenVPN push DNS prod deploy support / Task 1 production deploy syncs pushed OpenVPN DNS before activation
TASK_PACKAGE: docs/plans/2026-06-13-openvpn-push-dns-prod-deploy
REPORT_PATH: docs/plans/2026-06-13-openvpn-push-dns-prod-deploy/reports/aad-implementer-openvpn-push-dns.md
PROGRESS_PATH: docs/plans/2026-06-13-openvpn-push-dns-prod-deploy/progress/aad-implementer-openvpn-push-dns.md
COMMITS:
- daa5fd493998eb9b69fb66053ea46e08264b5106 fix(vpnkit): sync OpenVPN push DNS before prod activation
FILES_CHANGED:
- `scripts/vpnkit/vpnkit-prod-deploy.sh`: added IPv4 validation, safe deploy-mode env forwarding for `VPNKIT_OPENVPN_PUSH_DNS`, remote `server.conf` DNS sync/verification after render/fallback and before activation, and plan/dry-run step text.
- `test/prod-deploy-helper-test.sh`: added mocked rendered OpenVPN `server.conf` fixture plus default, override, invalid override, missing config, and ordering assertions.
- `docs/plans/2026-06-13-openvpn-push-dns-prod-deploy/verification/local.md`: recorded local verification summary.
- `docs/plans/2026-06-13-openvpn-push-dns-prod-deploy/progress/aad-implementer-openvpn-push-dns.md`: recorded implementation progress.
- `docs/plans/2026-06-13-openvpn-push-dns-prod-deploy/reports/aad-implementer-openvpn-push-dns.md`: final implementation evidence.
AC_VERIFICATION:
- Default deploy writes/verifies push DNS `1.1.1.1` before compose build/up with safe summary log: `test/prod-deploy-helper-test.sh` asserts `local_config_render=ok` before `openvpn_push_dns=updated`, `openvpn_push_dns=updated` before `compose_build=vpnkit`, and rendered `server.conf` contains `push "dhcp-option DNS 1.1.1.1"` while preserving `keepalive 10 120` — passed.
- Env override `VPNKIT_OPENVPN_PUSH_DNS` accepts valid IPv4 and writes it: `test/prod-deploy-helper-test.sh` mocked deploy with `VPNKIT_OPENVPN_PUSH_DNS=8.8.4.4` asserts `server.conf` contains the override and no stale default DNS line — passed.
- Invalid override fails before compose build/up: `test/prod-deploy-helper-test.sh` mocked deploy with `VPNKIT_OPENVPN_PUSH_DNS=999.1.1.1` expects failure and no `compose_build`, `compose_up`, or `activation=no_build` — passed.
- Missing/non-updatable/unverified config fails before compose build/up: `test/prod-deploy-helper-test.sh` removes `secrets/vps/rendered/openvpn/server.conf`, expects failure, and asserts no build/up/activation — passed for missing config; write/unverified paths use the same pre-activation function and return path.
- Existing render fallback still does not require source PKI: existing fallback cases in `test/prod-deploy-helper-test.sh` remain green and assert `local_config_render=singbox_only_fallback` before `compose_build=vpnkit` — passed.
TESTS_RUN:
- `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh`: passed.
- `test/prod-deploy-helper-test.sh`: passed.
- `git diff --check`: passed.
QUALITY_CHECKS:
- Shell syntax: `bash -n scripts/vpnkit/vpnkit-prod-deploy.sh test/prod-deploy-helper-test.sh` — passed.
- Targeted helper regression: `test/prod-deploy-helper-test.sh` — passed.
- Whitespace/static diff check: `git diff --check` — passed.
QUALITY_NOTES:
- Readability/reuse: reused existing remote helper structure, render/activate ordering, and mock assertion style; no new external dependencies.
- Error handling/logging: DNS sync returns explicit pre-activation failure statuses (`openvpn_push_dns=invalid`, `openvpn_push_dns_config=missing`, `openvpn_push_dns=failed`, `openvpn_push_dns=unverified`) without dumping config contents or endpoint values.
- Backend/API/data: not relevant; shell deploy helper only.
- Frontend/UI: not relevant.
- DevOps/runtime: deploy mode now syncs only `secrets/vps/rendered/openvpn/server.conf` after local config render/fallback and before compose build/up; default is `1.1.1.1`; valid deploy-mode override is forwarded to the remote command.
- Security: no secrets, raw configs, private endpoints, tokens, or generated profiles logged or committed; local override is IPv4-validated before being embedded in the SSH command.
- Concurrency/idempotency: repeated deploys are idempotent for the DNS line; existing DNS push lines are rewritten to the target value and absent DNS push is appended.
- Compatibility/performance: rollback/verify paths are not changed; DNS validation/forwarding is limited to deploy mode; sync is a small single-file operation before existing build/up.
SIDE_FINDINGS:
- Blocking: none.
- Non-blocking follow-up candidates: live production deploy/verification remains out of scope for this local-helper task.
PARENT_ACTION_REQUIRED:
- Action: none.
- Reason: no live host verification was in scope.
- Expected evidence: none.
- Safety bounds: no live hosts touched.
NOTES: Implementation evidence is local helper/mocked remote behavior only; it does not claim live production DNS behavior.
