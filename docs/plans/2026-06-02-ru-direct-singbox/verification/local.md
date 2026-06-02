# Local verification: RU direct sing-box routing

Date: 2026-06-02
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/ru-direct-singbox`
Branch: `ru-direct-singbox`

## Automated checks

- RED: `go test ./internal/singbox -run TestDockerTemplateRoutingInvariants`
  - Result: failed as expected before production change.
  - Key output: `route.rules length = 2, want DNS hijack rules plus RU direct rules`.
- GREEN: `go test ./internal/singbox -run TestDockerTemplateRoutingInvariants -count=1`
  - Result: passed.
- Broader: `go test ./...`
  - Result: passed.
- Static diff check: `git diff --check`
  - Result: passed (no output).

## sing-box template validation

Used a temp-rendered config with `{{SELECTED_NATIVE_OUT_JSON}}` replaced by a safe dummy direct outbound tagged `selected-native-out`; no secrets or rendered repo artifacts were used.

- `sing-box check -c <temp-rendered-config>`
  - Result: failed on pre-existing sing-box 1.13.12 deprecation gate for legacy DNS server format.
  - Key output: `legacy DNS servers is deprecated in sing-box 1.12.0 ... set environment variable ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true`.
- `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true sing-box check -c <temp-rendered-config>`
  - Result: failed on second pre-existing deprecation gate for missing default domain resolver.
  - Key output: `missing route.default_domain_resolver or domain_resolver ... set environment variable ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true`.
- `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true sing-box check -c <temp-rendered-config>`
  - Result: passed with only the two deprecation warnings above.

## Docker/render waiver

- `secrets/` is absent in this worktree (`secrets-dir-missing`).
- Docker daemon is available (`docker version` server `29.5.1`), but the AGENTS Docker lab requires gitignored secret material and the delegated boundary says not to touch secrets.
- Therefore `scripts/vpnkit-render-local-configs.sh` and Docker compose OpenVPN client regression were not run in this worktree.
- No VPS commands were run.
