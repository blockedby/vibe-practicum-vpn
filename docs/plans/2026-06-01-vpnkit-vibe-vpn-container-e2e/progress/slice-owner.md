# Apply adapter fix slice owner progress

## 2026-06-01T03:25Z intake
- Goal: diagnose/fix post-switch `scripts/vpnkit-vibe-vpn-e2e.sh --switching` failure where baseline passes, apply/restart happens, then OpenVPN client DNS/HTTPS fails with sing-box selected outbound hostname resolution loop/timeouts.
- Worktree/branch: provided worktree on `pi/containerized-vpnkit-openvpn-singbox`; no new worktree created.
- Scope stays whole: one blocker, one verification story. Delegate implementation/debug to one `aad-implementer`.
- Plan gate: prior apply-adapter plan and reports identify the adapter wiring and unresolved U-1. Fix task will focus on selected outbound proxy-server hostname bootstrap resolution without changing client DNS acceptance or VPS defaults.

## Fix plan task
Goal:
- Make applied domain-form VLESS outbounds safe in the container by resolving proxy server hostnames through an explicit bootstrap path (or equivalent sing-box resolver config) while preserving Google DoT client DNS through `selected-native-out`.

Existing evidence/reuse:
- Initial render pre-resolves `selected-native-out.server` in `scripts/vpnkit-render-local-configs.sh` to avoid bootstrap loop.
- `cmd/vibe-vpn applyResult` currently converts the selected link with `vless.SingBoxOutbound` and writes the raw hostname into active config.
- `config/sing-box/config.json.template` has only Google DoT DNS servers detoured through `selected-native-out`, so selected outbound hostname resolution can loop after apply.

Acceptance:
- Concrete cause is evidenced from code/logs/config behavior.
- Small robust fix preserving VPS defaults, no secrets, no VPS mutation, no broad NAT.
- Targeted Go tests, full local checks, script/compose checks, and real `--switching` e2e if runtime inputs permit.

Dispatch:
- Executor: `aad-implementer`, report `reports/aad-implementer-apply-adapter-fix.md`, progress `progress/aad-implementer-apply-adapter-fix.md`.
