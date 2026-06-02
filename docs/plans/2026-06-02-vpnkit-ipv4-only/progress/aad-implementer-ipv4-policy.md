# aad-implementer progress: IPv4 policy

- 2026-06-02: Started Task 1 in worktree `vpnkit-compat-bypass`; read AGENTS.md, README.md, plan.md, devops/report/task-package guidance, and relevant runtime/test/docs files.
- 2026-06-02: `git status --short` was clean before edits; branch is `vpnkit-compat-bypass`.
- 2026-06-02: Confirmed targeted commands from prompt/plan: `bash -n` on touched shell scripts, `scripts/vpnkit-routing-compat-bypass-test.sh`, `docker compose config` if available, `sing-box check` on safe rendered/temp config if available, plus invalid `VPNKIT_IPV6_POLICY` behavior if feasible.
- 2026-06-02: RED check captured: after adding IPv6 block expectations to `scripts/vpnkit-routing-compat-bypass-test.sh`, `scripts/vpnkit-routing-compat-bypass-test.sh` failed with missing `ip6tables ... OVPN_IPV6_BLOCK` rendered rule.
- 2026-06-02: GREEN implemented runtime policy/docs/config changes; `bash -n docker/vpnkit/entrypoint.sh docker/vpnkit/setup-routing.sh scripts/vpnkit-render-local-configs.sh scripts/vpnkit-routing-compat-bypass-test.sh` passed; `scripts/vpnkit-routing-compat-bypass-test.sh` passed.
- 2026-06-02: Compose/config checks passed: `docker compose config` included `VPNKIT_IPV6_POLICY: block`; template grep found `"strategy": "ipv4_only"`; temp `sing-box check` passed with compose's deprecated-feature env flags after an expected initial compatibility-gate failure without those flags.
- 2026-06-02: Wrote `verification/local.md`; no live deploy or remote mutation performed.
- 2026-06-02: Committed implementation/evidence as `184fe34 Add vpnkit IPv4-only runtime policy`; writing final report.
