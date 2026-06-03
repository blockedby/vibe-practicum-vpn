# Non-DNS UDP TPROXY debug verification

Date: 2026-06-03

## Change under test

- `config/sing-box/config.tproxy.json.template`: added a UDP-specific route rule for `vpnkit-tproxy-in` before the sniff rule so opaque UDP/OpenVPN traffic is routed to `selected-native-out` without protocol sniffing.
- `tests/vpnkit-singbox-template-test.sh`: asserts the UDP route exists and is ordered before sniffing.

## Automated checks

- `bash tests/vpnkit-singbox-template-test.sh` — PASS (`vpnkit sing-box templates ok`).
- `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh` — PASS.
- `go test ./...` — PASS.
- `go vet ./...` — PASS.
- `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn` — PASS.
- Rendered tproxy template with direct placeholder outbound and ran `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true sing-box check -c <tmp>` — PASS; deprecation warnings only.

## Local Docker lab smoke

Isolated resources:
- Compose project: `vpnkit_tproxy_udp_nested_lab2`.
- Host OpenVPN port: `21196/udp`.
- Server container: `vpnkit_tproxy_udp_nested_lab2-vpnkit-1`.
- Client-test run container: `vpnkit_tproxy_udp_nested_lab2-ovpn-client-test-run-c78e5ad9e805` (removed by `--rm`).

Commands:

```bash
docker compose -p vpnkit_tproxy_udp_nested_lab2 down -v --remove-orphans || true
VPNKIT_OPENVPN_PORT=21196 \
VPNKIT_ENABLE_VIBE_VPN_DAEMON=false \
VPNKIT_ROUTING_MODE=tproxy \
VPNKIT_IPV6_POLICY=block \
docker compose -p vpnkit_tproxy_udp_nested_lab2 up -d --build vpnkit

VPNKIT_OPENVPN_PORT=21196 \
VPNKIT_ENABLE_VIBE_VPN_DAEMON=false \
VPNKIT_ROUTING_MODE=tproxy \
VPNKIT_IPV6_POLICY=block \
docker compose -p vpnkit_tproxy_udp_nested_lab2 --profile test run --rm ovpn-client-test

docker exec vpnkit_tproxy_udp_nested_lab2-vpnkit-1 iptables -t mangle -L OVPN_TO_SINGBOX -v -n -x

docker compose -p vpnkit_tproxy_udp_nested_lab2 down -v --remove-orphans
```

Result: PASS for local tproxy smoke.
- OpenVPN client connected and brought up `tun0` with `10.89.0.2/24`.
- UDP DNS through tunnel returned `NOERROR` for `example.com` using `8.8.8.8#53`.
- HTTPS hostname smoke returned `http_code=200`.
- Literal-IP HTTPS smoke returned `http_code=200`.
- Runtime rules after pass:
  - UDP/53 RETURN: `2` packets / `148` bytes.
  - TCP RETURN: `28` packets / `3032` bytes.
  - Non-DNS UDP TPROXY rule present on `2082`; counter stayed `0` for this smoke because it does not send non-DNS UDP.

Cleanup:
- `docker compose -p vpnkit_tproxy_udp_nested_lab2 down -v --remove-orphans` removed isolated server container, volumes, and network.

## Live nested validation gate

- Sourced `config/private-endpoints.local.env` using the approved local-only pattern without printing values.
- Required variable presence: `VPNKIT_VPS_SSH_HOST` and `VPNKIT_VPS_PUBLIC_ENDPOINT` were set; a remote client host variable was not present in this local file.
- SSH gate failed before any remote mutation: the configured VPS SSH host is an unresolved placeholder alias.

Result: BLOCKED for live nested rerun. No live containers, networks, volumes, ports, or state paths were created or modified in this continuation.

## Production untouched status

- No production container commands were run successfully against live hosts.
- Local Docker actions used only isolated project `vpnkit_tproxy_udp_nested_lab2`, then cleaned it up.
- Steam Deck was not touched.
- No generated profiles, logs, secrets, rendered configs, or private endpoint values are recorded here.
