# TPROXY/UDP debug continuation verification

## Changes verified
- `docker/vpnkit/setup-routing.sh`: tproxy mode now routes UDP/53 to the sing-box DNS inbound by local REDIRECT, TCP to a mode-specific redirect inbound on `2083`, and preserves non-DNS UDP on the `tproxy` inbound `2082`.
- `config/sing-box/config.tproxy.json.template`: adds `vpnkit-redirect-in` on `2083` while retaining `vpnkit-tproxy-in` TCP/UDP listener on `2082` and `vpnkit-dns-in` UDP `5353`.
- `docker/vpnkit/entrypoint.sh`: recopies the source sing-box config at startup and waits for tproxy-mode `2082`/`2083`/`5353` listeners.

## Fresh automated checks
- `bash tests/vpnkit-singbox-template-test.sh` — PASS (`vpnkit sing-box templates ok`).
- `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh` — PASS.
- `go test ./...` — PASS.
- `go vet ./...` — PASS.
- `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn` — PASS.

## Local Docker lab

Isolated resources:
- Compose project: `vpnkit_tproxy_udp_nested_lab`.
- Host OpenVPN port: `21194/udp`.
- Server container: `vpnkit_tproxy_udp_nested_lab-vpnkit-1`.
- Client-test container for passing run: `vpnkit_tproxy_udp_nested_lab-ovpn-client-test-run-9e07b47b6321`.
- Generated local configs/secrets were under gitignored `secrets/`; rendered config was updated locally for the lab and not committed.

Commands:
```bash
docker compose -p vpnkit_tproxy_udp_nested_lab down -v --remove-orphans || true
VPNKIT_OPENVPN_PORT=21194 \
VPNKIT_ENABLE_VIBE_VPN_DAEMON=false \
VPNKIT_ROUTING_MODE=tproxy \
VPNKIT_IPV6_POLICY=block \
docker compose -p vpnkit_tproxy_udp_nested_lab up -d --build vpnkit

VPNKIT_OPENVPN_PORT=21194 \
VPNKIT_ENABLE_VIBE_VPN_DAEMON=false \
VPNKIT_ROUTING_MODE=tproxy \
VPNKIT_IPV6_POLICY=block \
docker compose -p vpnkit_tproxy_udp_nested_lab --profile test run --rm ovpn-client-test
```

Result: PASS for the existing client smoke path.
- OpenVPN client connected and received `10.89.0.2/24` plus default split routes via `10.89.0.1`.
- UDP DNS through the tunnel passed: `dig +time=10 +tries=1 @8.8.8.8 example.com` returned `NOERROR`; query time 123 ms; server reported as `8.8.8.8#53 (UDP)`.
- HTTPS by hostname passed: `https-test http_code=200 remote_ip=104.20.23.154`.
- Literal-IP HTTPS passed: `literal-ip-test http_code=200 remote_ip=1.1.1.1`.

Runtime rule/listener evidence after pass:
- `OVPN_TO_SINGBOX`: UDP/53 RETURN counter `2` packets/`148` bytes; TCP RETURN counter `26` packets/`2928` bytes; non-DNS UDP TPROXY rule present on `2082`.
- `OVPN_TPROXY_DNS`: REDIRECT to `5353` counter `2` packets/`148` bytes.
- `OVPN_TPROXY_TCP`: REDIRECT to `2083` counter `2` packets/`120` bytes.
- `ss`: TCP listener on `0.0.0.0:2083`; UDP listener on `0.0.0.0:2082`.

Nested/inner tunnel evidence:
- Full inner VPN-over-VPN was not attempted because local lab is now passing but `config/private-endpoints.local.env` is absent, so approved isolated live-host staging cannot safely begin from this worktree.
- What was proven locally: outer OpenVPN tunnel plus UDP DNS through the vpnkit tproxy-mode runtime and the non-DNS UDP TPROXY rule remains installed for nested UDP traffic.

## Live-test gate
- `test -r config/private-endpoints.local.env` — FAIL/blocked (`PRIVATE_ENV_ABSENT`).
- No live-host mutation was attempted.

## Cleanup / production untouched
- Cleanup run: `docker compose -p vpnkit_tproxy_udp_nested_lab down -v --remove-orphans`, followed by forced removal of stale interrupted client-test containers from this isolated project and network removal.
- After cleanup: no `vpnkit_tproxy_udp_nested_lab-*` containers remained.
- Production/hard-boundary containers `vpnkit` and `current-vpnkit-1` were not present. Existing non-slice containers observed and not touched: `vpnkit-compat-bypass-vpnkit-1`, `vpnkit-client-127.0.0.1-183549`.
