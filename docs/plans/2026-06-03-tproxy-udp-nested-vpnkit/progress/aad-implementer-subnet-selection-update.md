# Progress: chosen OpenVPN subnet defaults and nested guidance

- 2026-06-03: Started in active worktree `vpnkit-tproxy-udp-nested`; read AGENTS/task plan/skills; `CLAUDE.md` absent.
- 2026-06-03: Initial `git status --short` showed pre-existing related task-package change: `M docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/plan.md`; proceeding because it contains the delegated continuation task.
- 2026-06-03: Reviewed relevant source/tests/scripts and tracked search results for `10.89.0.0`, `10.89.0.1`, `10.89.0.2`, `10.90.0.0`; will avoid `secrets/`, `logs/`, and rendered/generated artifacts.
- 2026-06-03: RED complete: added `tests/openvpn-server-template-test.sh` and updated `tests/vpnkit-setup-routing-test.sh` default expectations; pre-production run failed as expected (`openvpn_template_status=1`, `setup_routing_status=1`).
- 2026-06-03: GREEN updates applied to `config/openvpn/server.tpl`, `docker/vpnkit/setup-routing.sh`, active `scripts/openvpn-asus-*` defaults/guidance, routing tests, and TUN task-package guidance notes.
- 2026-06-03: GREEN focused checks passed: `bash tests/openvpn-server-template-test.sh`, `bash tests/vpnkit-setup-routing-test.sh`, `bash scripts/vpnkit-routing-compat-bypass-test.sh`.
- 2026-06-03: Search review: active source/scripts/tests now use `10.231.89.0/24`; remaining tracked `10.89.*`/`10.90.0.0` references are historical task-package evidence or unrelated `internal/ikev2/registry_test.go` negative input.
- 2026-06-03: Owner-specified verification passed: `bash tests/openvpn-server-template-test.sh`, `bash tests/vpnkit-singbox-template-test.sh`, `bash tests/vpnkit-setup-routing-test.sh`, `bash scripts/vpnkit-routing-compat-bypass-test.sh`, `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh`, `go test ./...`, `git diff --check`.
- 2026-06-03: Preparing implementation commit; no live hosts, generated artifacts, secrets, logs, rendered configs, or private endpoint values touched.
