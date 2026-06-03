# Live isolated TPROXY/UDP validation

Date: 2026-06-03

## Scope and safety gates

- Private endpoints were loaded with the approved local-only pattern: `test -r config/private-endpoints.local.env && set -a && . config/private-endpoints.local.env && set +a`.
- The gitignored local env file was not printed or committed.
- Steam Deck was not touched.
- Production `vpnkit` on vibe-practicum was inspected only with safe Docker metadata. It was not restarted, recreated, adopted, or mutated.

## Isolated resources used

vibe-practicum server/client:
- Temporary checkout/state path: `/tmp/vpnkit_tproxy_live_21195` (removed during cleanup).
- Compose project: `vpnkit_tproxy_live_21195`.
- Test server container: `vpnkit_tproxy_live_21195-vpnkit-1`.
- Same-host client-test container: `vpnkit_tproxy_live_21195-ovpn-client-test-run-1bd36594c1dc`.
- Test OpenVPN port: `21195/udp` mapped to isolated server container port `1194/udp`.
- Isolated Docker network: `vpnkit_tproxy_live_21195_default`.
- Isolated Docker volumes: `vpnkit_tproxy_live_21195_vpnkit-vibe-vpn-state`, `vpnkit_tproxy_live_21195_vpnkit-sing-box-state`.

moscow-tiger client:
- Temporary client bundle path: `/tmp/vpnkit_tproxy_live_21195_client` (removed during cleanup).
- Compose project: `vpnkit_tproxy_live_21195_moscow_client`.
- Passing remote client-test container: `vpnkit_tproxy_live_21195_moscow_client-ovpn-client-test-run-5a34e944274c`.
- A prior failed attempt used a placeholder endpoint from `config/private-endpoints.local.env`; it was stopped/cleaned and superseded by the passing run using the SSH-config host endpoint, redacted here as `<vibe-practicum-public-endpoint>`.

## Commands run (sanitized)

```bash
# Source private endpoint inventory without printing values.
test -r config/private-endpoints.local.env && set -a && . config/private-endpoints.local.env && set +a

# Copy this worktree plus gitignored generated lab secrets/configs to an isolated temp path on vibe-practicum.
tar --exclude='.git' --exclude='logs/*' --exclude='config/private-endpoints.local.env' -czf /tmp/vpnkit-live-iso.tgz .
ssh vibe-practicum 'rm -rf /tmp/vpnkit_tproxy_live_21195 && mkdir -p /tmp/vpnkit_tproxy_live_21195'
scp /tmp/vpnkit-live-iso.tgz vibe-practicum:/tmp/vpnkit_tproxy_live_21195/src.tgz
ssh vibe-practicum 'cd /tmp/vpnkit_tproxy_live_21195 && tar -xzf src.tgz && rm src.tgz && mkdir -p logs'

# Safe production metadata before isolated start.
ssh vibe-practicum 'docker inspect vpnkit --format "name={{.Name}} status={{.State.Status}} restart={{.RestartCount}} started={{.State.StartedAt}}"'

# Start isolated tproxy-mode server.
ssh vibe-practicum 'cd /tmp/vpnkit_tproxy_live_21195 && \
  docker compose -p vpnkit_tproxy_live_21195 down -v --remove-orphans || true && \
  VPNKIT_OPENVPN_PORT=21195 \
  VPNKIT_ENABLE_VIBE_VPN_DAEMON=false \
  VPNKIT_ROUTING_MODE=tproxy \
  VPNKIT_IPV6_POLICY=block \
  docker compose -p vpnkit_tproxy_live_21195 up -d --build vpnkit'

# Same-host isolated client-test on vibe-practicum.
ssh vibe-practicum 'cd /tmp/vpnkit_tproxy_live_21195 && \
  VPNKIT_OPENVPN_PORT=21195 \
  VPNKIT_ENABLE_VIBE_VPN_DAEMON=false \
  VPNKIT_ROUTING_MODE=tproxy \
  VPNKIT_IPV6_POLICY=block \
  docker compose -p vpnkit_tproxy_live_21195 --profile test run --rm ovpn-client-test'

# Copy a sanitized remote-profile client bundle to moscow-tiger, with remote line set to <vibe-practicum-public-endpoint> 21195.
# Run isolated remote client-test from moscow-tiger.
ssh moscow-tiger 'cd /tmp/vpnkit_tproxy_live_21195_client && \
  docker compose -p vpnkit_tproxy_live_21195_moscow_client run --rm ovpn-client-test'

# Runtime counter/listener evidence from isolated server, then cleanup.
ssh vibe-practicum 'cd /tmp/vpnkit_tproxy_live_21195 && \
  docker compose -p vpnkit_tproxy_live_21195 exec -T vpnkit sh -c "iptables -t mangle -L OVPN_TO_SINGBOX -n -v; iptables -t nat -L OVPN_TPROXY_DNS -n -v; iptables -t nat -L OVPN_TPROXY_TCP -n -v; ss -lntu | grep -E \"(:2082|:2083|:5353|:1194)\"" && \
  docker inspect vpnkit --format "name={{.Name}} status={{.State.Status}} restart={{.RestartCount}} started={{.State.StartedAt}}" && \
  docker compose -p vpnkit_tproxy_live_21195 down -v --remove-orphans && \
  docker inspect vpnkit --format "name={{.Name}} status={{.State.Status}} restart={{.RestartCount}} started={{.State.StartedAt}}"'
ssh moscow-tiger 'docker rm -f vpnkit_tproxy_live_21195_moscow_client-ovpn-client-test-run-a7d134d9dd60 2>/dev/null || true; docker compose -p vpnkit_tproxy_live_21195_moscow_client down -v --remove-orphans || true; rm -rf /tmp/vpnkit_tproxy_live_21195_client'
ssh vibe-practicum 'rm -rf /tmp/vpnkit_tproxy_live_21195'
```

## Results

### vibe-practicum isolated server and same-host client

Result: PASS.

Evidence:
- Isolated server started as `vpnkit_tproxy_live_21195-vpnkit-1` with port mapping `0.0.0.0:21195->1194/udp`.
- Same-host client connected to the isolated server over UDP inside the isolated Compose network.
- OpenVPN completed TLS negotiation and received tunnel address `10.89.0.2/24` with pushed DNS `10.89.0.1`.
- UDP DNS through the tunnel passed: `dig +time=10 +tries=1 @8.8.8.8 example.com` returned `NOERROR`; query time 45 ms; server reported as `8.8.8.8#53 (UDP)`.
- HTTPS hostname smoke passed: `http_code=200`.
- Literal-IP HTTPS smoke passed: `http_code=200`.

### moscow-tiger isolated remote client

Result: PASS after correcting a placeholder endpoint in the local private env by using the SSH-config host endpoint, redacted as `<vibe-practicum-public-endpoint>`.

Evidence:
- Remote client connected from moscow-tiger to `<vibe-practicum-public-endpoint>:21195/udp`.
- OpenVPN completed TLS negotiation and received tunnel address `10.89.0.2/24` with pushed DNS `10.89.0.1`.
- UDP DNS through the remote outer tunnel passed: `dig +time=10 +tries=1 @8.8.8.8 example.com` returned `NOERROR`; query time 132 ms; server reported as `8.8.8.8#53 (UDP)`.
- HTTPS hostname smoke passed: `http_code=200`.
- Literal-IP HTTPS smoke passed: `http_code=200`.

### UDP / nested-adjacent runtime evidence

Result: PASS for outer OpenVPN plus UDP path on both live hosts; FULL INNER TUNNEL NOT RUN.

Isolated server runtime evidence after both successful client tests:
- `OVPN_TO_SINGBOX` chain:
  - UDP/53 RETURN: `2` packets / `160` bytes.
  - TCP RETURN: `48` packets / `5648` bytes.
  - non-DNS UDP TPROXY rule present on port `2082` with mark `0x1/0x1`.
- `OVPN_TPROXY_DNS` chain:
  - REDIRECT to DNS inbound `5353`: `2` packets / `160` bytes.
- `OVPN_TPROXY_TCP` chain:
  - REDIRECT to tproxy-mode TCP redirect inbound `2083`: `4` packets / `240` bytes.
- Listeners present inside isolated server:
  - UDP `1194` OpenVPN.
  - UDP `5353` DNS inbound.
  - UDP `2082` TPROXY inbound.
  - TCP `2082` and TCP `2083` sing-box inbounds.

Full inner VPN-over-VPN was not performed safely in this pass because only the existing generated test-client profile/certificate was available in the isolated bundle. Starting a second simultaneous inner OpenVPN session from inside the same isolated client would reuse the same client identity/profile and risk interfering with the already-active outer test session rather than proving a clean independent nested-client path. No separate inner client certificate/profile or documented safe inner-tunnel harness exists in this slice. The proven nested-adjacent evidence is: live UDP OpenVPN outer tunnel from moscow-tiger to the isolated vibe-practicum vpnkit server, UDP DNS over that outer tunnel, TCP HTTPS over that tunnel, and installed/listening non-DNS UDP TPROXY path on the isolated server.

## Production untouched evidence

vibe-practicum production container `vpnkit` safe metadata:
- Before isolated server start: `name=/vpnkit status=running restart=0 started=2026-06-02T13:47:35.235471647Z`.
- Before cleanup: `name=/vpnkit status=running restart=0 started=2026-06-02T13:47:35.235471647Z`.
- After cleanup: `name=/vpnkit status=running restart=0 started=2026-06-02T13:47:35.235471647Z`.

No production container was restarted, recreated, adopted, or mutated.

## Cleanup status

- Removed `vpnkit_tproxy_live_21195-vpnkit-1`.
- Removed isolated volumes `vpnkit_tproxy_live_21195_vpnkit-vibe-vpn-state` and `vpnkit_tproxy_live_21195_vpnkit-sing-box-state`.
- Removed isolated network `vpnkit_tproxy_live_21195_default`.
- Removed temporary vibe-practicum path `/tmp/vpnkit_tproxy_live_21195`.
- Removed/cleaned moscow-tiger isolated client project `vpnkit_tproxy_live_21195_moscow_client` and temp path `/tmp/vpnkit_tproxy_live_21195_client`.
- Nothing retained intentionally.
