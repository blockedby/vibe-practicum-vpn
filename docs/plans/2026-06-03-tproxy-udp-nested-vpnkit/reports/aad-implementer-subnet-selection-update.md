PI_RESULT: PASS
TASK: chosen OpenVPN subnet defaults and nested guidance
TASK_PACKAGE: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit
REPORT_PATH: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/aad-implementer-subnet-selection-update.md
PROGRESS_PATH: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-subnet-selection-update.md

COMMITS:
- a428a0c: Set vpnkit OpenVPN subnet defaults (pushed to `vpnkit-tproxy-udp-nested` before this report was written)

FILES_CHANGED:
- `config/openvpn/server.tpl`: default OpenVPN server subnet/DNS changed to `10.231.89.0/24` and `10.231.89.1`.
- `docker/vpnkit/setup-routing.sh`: default `OVPN_CIDR` changed to `10.231.89.0/24`.
- `scripts/openvpn-asus-install.sh`: active ASUS OpenVPN defaults updated to `10.231.89.0/24` gateway `10.231.89.1`, ASUS/static IP `10.231.89.2`, and pool `10.231.89.20-10.231.89.254`.
- `scripts/openvpn-asus-rollback.sh`, `scripts/openvpn-asus-status.sh`: active OpenVPN VPN CIDR defaults updated to `10.231.89.0/24`.
- `scripts/openvpn-asus-pool-tproxy-profile.sh`: current pool guidance updated to `10.231.89.20-10.231.89.254`.
- `scripts/openvpn-asus-tproxy-canary-rules.sh`: current canary IP guidance/default updated to `10.231.89.3`.
- `scripts/vpnkit-routing-compat-bypass-test.sh`: current default-CIDR routing expectation updated.
- `tests/openvpn-server-template-test.sh`: new focused OpenVPN server template default check.
- `tests/vpnkit-setup-routing-test.sh`: default routing/TUN expectations now assert `10.231.89.0/24` without overriding `OVPN_CIDR`.
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/plan.md`: delegated continuation task and implementation ledger note.
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/tun-live-complete-matrix.md`, `reports/tun-live-complete-report.md`, `verification/tun-canary-runtime.md`: future nested guidance added/clarified while preserving historical evidence.
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-subnet-selection-update.md`: progress evidence.

AC_VERIFICATION:
- AC1 default rendered OpenVPN server uses `10.231.89.0/24` and DNS `10.231.89.1`: `bash tests/openvpn-server-template-test.sh` passed; direct source diff shows `server 10.231.89.0 255.255.255.0` and `push "dhcp-option DNS 10.231.89.1"` — passed.
- AC2 default TUN/routing code/tests/docs expectations use `10.231.89.0/24`: `docker/vpnkit/setup-routing.sh` default changed; `tests/vpnkit-setup-routing-test.sh` no longer overrides `OVPN_CIDR` and asserts `10.231.89.0/24`; `bash tests/vpnkit-setup-routing-test.sh` passed — passed.
- AC3 nested guidance records `10.232.90.0/24` without rewriting temporary `10.90.0.0/24` evidence: added current-guidance notes to TUN validation docs/reports and left historical run lines intact — passed.
- AC4 search terms reviewed and active defaults/guidance/tests updated only where current: tracked `git grep` found active source/scripts/tests clean for old `10.89.*` values except unrelated `internal/ikev2/registry_test.go` negative input; historical task-package evidence left listed below — passed.
- AC5 no production/generated/private artifacts touched: no live-host/container commands were run; no `secrets/`, `logs/`, rendered configs/profiles, or private endpoint env files were edited or committed — passed.
- AC6 focused checks passed: see TESTS_RUN/QUALITY_CHECKS — passed.
- AC7 commit/push: implementation commit `a428a0c` created and `git push` succeeded (`4d87dd9..a428a0c`) — passed for implementation commit.

Historical references intentionally left:
- `docs/plans/2026-06-02-moscow-tiger-runtime-smoke-fix/plan.md`: previous live smoke evidence with `10.89.0.2/24`.
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/plan.md`: prior execution-ledger evidence and search-scope text mentioning old/temp values.
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/progress/aad-implementer-tun-validation-followup.md` and `progress/aad-implementer-udp-echo-tproxy-fix.md`: historical validation/progress notes using temporary `10.90.0.0/24`.
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/*tun*`, `reports/slice-owner-next-tun-validation-run*`, `reports/aad-implementer-tun-canary-validation.md`: historical TUN validation reports; current guidance note added where useful.
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/*`: historical validation evidence including `10.89.0.0/24`, `10.89.0.1`, `10.89.0.2`, and temporary nested `10.90.0.0/24`; current guidance note added to `tun-live-complete-matrix.md` and `tun-canary-runtime.md`.
- `internal/ikev2/registry_test.go`: unrelated IKEv2 negative test sample `10.89.0.2`, not an OpenVPN default/current guidance.

TESTS_RUN:
- `bash tests/openvpn-server-template-test.sh`: passed.
- `bash tests/vpnkit-singbox-template-test.sh`: passed.
- `bash tests/vpnkit-setup-routing-test.sh`: passed.
- `bash scripts/vpnkit-routing-compat-bypass-test.sh`: passed.
- `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh`: passed.
- `go test ./...`: passed.
- `git diff --check`: passed.

QUALITY_CHECKS:
- Shell syntax: `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh` — passed.
- Go tests: `go test ./...` — passed.
- Whitespace/static diff check: `git diff --check` — passed.

QUALITY_NOTES:
- Readability/reuse: reused existing shell defaults/tests; added one small focused template test instead of a new abstraction.
- Error handling/logging: preserved existing shell error handling and logging conventions.
- Backend/API/data: not relevant; no storage/API/schema changes.
- Frontend/UI: not relevant.
- DevOps/runtime: runtime config defaults and helper-script guidance were paired with routing/template tests and task-package guidance; default redirect/tproxy/tun mechanics otherwise unchanged.
- Security: no secrets, endpoint values, profiles, rendered configs, logs, or private env values were read into reports, edited, or committed.
- Concurrency/idempotency: existing idempotent routing helper behavior preserved; only default CIDR values changed.
- Compatibility/performance: env overrides such as `OVPN_CIDR` and `OPENVPN_*` still work; no performance-relevant code paths changed.

SIDE_FINDINGS:
- Blocking: none.
- Non-blocking follow-up candidates: if future acceptance wants zero old-subnet mentions in task-package docs, it requires an explicit historical-evidence rewrite decision; current task asked to preserve those facts.

NOTES: No live hosts or containers were touched. Implementation commit was pushed before this report was written; report/progress artifacts may be committed separately if the owner wants report artifacts on the branch.
