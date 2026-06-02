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

## Owner verification refresh

- `go test ./internal/singbox -run TestDockerTemplateRoutingInvariants -count=1`
  - Result: passed (fresh owner run).
- `go test ./...`
  - Result: passed (fresh owner run; packages reported ok/cached after the targeted package had just run).
- `git diff --check`
  - Result: passed.
- `scripts/vpnkit-render-local-configs.sh`
  - Result: passed after copying gitignored local secrets from `.worktrees/steamdeck-podman-vpnkit/secrets` per AGENTS local-lab workflow. The copied `secrets/` tree was removed after verification and was not committed.
- Docker lab attempt with AGENTS recommended feature flags:
  - Result: not passed. Initial `docker compose up -d --build vpnkit` hit a host port conflict: `Bind for 0.0.0.0:1194 failed: port is already allocated` by an existing `vpnkit-compat-bypass-vpnkit-1` container.
  - Subsequent client run under the partially-created compose project could not resolve `vpnkit:1194`; this was discarded and the compose project was cleaned.
- Docker lab retry on alternate host port `VPNKIT_OPENVPN_PORT=1195` with compat bypass disabled to avoid the unrelated unresolved `vpn.proofix.tv` bypass endpoint:
  - Result: partial runtime evidence only. `vpnkit` built and started; `ps` showed `sing-box run -c /var/lib/vpnkit/sing-box/config.json` and `openvpn --config /etc/openvpn/server.conf`.
  - OpenVPN client connected and received `10.89.0.2/24`, but the compose client regression failed at DNS: `dig @8.8.8.8 example.com` timed out with `no servers could be reached`.
  - `vpnkit` logs showed the new RU rule sets being updated from `raw.githubusercontent.com` and direct outbound attempts for those downloads, plus pre-existing warnings about legacy DNS/default domain resolver.
- VPS: not touched.
