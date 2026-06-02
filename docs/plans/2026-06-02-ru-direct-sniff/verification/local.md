# Local verification: RU direct sniff

Date: 2026-06-02
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn`
Branch: `main`

## Source/test checks
- `go test ./internal/singbox -run TestDockerTemplateRoutingInvariants`: passed.
- `go test ./...`: passed.
- `scripts/vpnkit-render-local-configs.sh`: passed after restoring gitignored local `secrets/` from `.worktrees/steamdeck-podman-vpnkit/secrets` per AGENTS local lab guidance.
- `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true sing-box check -c secrets/vps/rendered/sing-box/config.json`: passed with only pre-existing deprecation warnings for legacy DNS/missing domain resolver gates.

## Local Docker lab
- Initial `docker compose up -d --build vpnkit` with default host UDP `1194` failed because port `1194` was already allocated on this host. Retried with `VPNKIT_OPENVPN_PORT=1196`.
- `VPNKIT_OPENVPN_PORT=1196 VPNKIT_ENABLE_VIBE_VPN_DAEMON=true VPNKIT_ROUTING_MODE=redirect VPNKIT_IPV6_POLICY=block VPNKIT_COMPAT_BYPASS_ENABLED=true VPNKIT_COMPAT_BYPASS_ENDPOINTS='vpn.proofix.tv:1194/udp,vpn.proofix.tv:1194/tcp' docker compose up -d --build vpnkit`: passed.
- Process check inside `vpnkit`: `sing-box`, `openvpn`, and `vibe-vpn daemon` were alive.
- Baseline client regression:
  - Command: same env plus `docker compose --profile test run --rm ovpn-client-test`.
  - Result: passed.
  - Evidence excerpt: client got `inet 10.89.0.2/24`; `dig @8.8.8.8 example.com` returned `status: NOERROR`; `https-test http_code=200`; `literal-ip-test http_code=200`.

## Local 2ip.ru route proof
- Command: OpenVPN test container with `curl -4 -k --max-time 25 https://2ip.ru/`, then inspect `docker compose logs` for route decision.
- Result: passed.
- Client output excerpt: `2ip code=200 remote_ip=188.40.167.82 size=15`; body excerpt reported local direct source `193.233.161.64` (expected for local lab host, not VPS).
- Sing-box route log excerpt:
  - `dns: exchanged A 2ip.ru. ... A 188.40.167.82`
  - `router: match[2] inbound=[vpnkit-redirect-in vpnkit-socks-in] => sniff(1s)`
  - `router: sniffed protocol: tls, domain: 2ip.ru`
  - `router: match[4] rule_set=geosite-category-ru => route(direct-out)`
  - `outbound/direct[direct-out]: outbound connection to 188.40.167.82:443`

## Safety notes
- `secrets/` was used only as gitignored local material for rendering/client tests.
- No generated profiles, secret values, or raw logs are committed in this verification artifact.
