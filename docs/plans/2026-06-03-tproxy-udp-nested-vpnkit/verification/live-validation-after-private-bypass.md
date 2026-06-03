# Live isolated validation after private UDP bypass fix

Date: 2026-06-03
Executor: aad-implementer

## Safety gates

- Loaded `config/private-endpoints.local.env` only with `set -a; . config/private-endpoints.local.env; set +a`; values were not printed.
- Used SSH aliases `vibe-practicum` and `moscow-tiger`; private/public endpoint values are redacted from this artifact.
- Used only fresh isolated Docker/project/container/network/volume/temp names and high UDP ports.
- Did not restart, recreate, adopt, or mutate production containers. Steam Deck was not touched.
- Did not print or commit generated profiles, PKI, rendered configs, endpoint values, raw OpenVPN logs, or raw sing-box logs.
- Matching gitignored bundle was used by path only: rendered OpenVPN server/PKI, rendered tproxy sing-box config, and `test-client.ovpn`. Temporary profile edits only rewrote `remote` lines and `dev tun1`; the inner server temp config used subnet `10.90.0.0/24` to avoid outer/inner tunnel address collision.

## Isolated resources used

### Full live baseline + nested run

- vibe-practicum temp path: `/tmp/vpnkit_live_bypass_21470_21471_21472` (removed).
- moscow-tiger temp path: `/tmp/vpnkit_live_bypass_client_21470_21471_21472` (removed).
- Outer server project/container: `vpnkit_live_bypass_outer_21470` / `vpnkit_live_bypass_outer_21470-vpnkit-1`.
- Outer OpenVPN port: `21470/udp`.
- Inner server project/container: `vpnkit_live_bypass_inner_21471` / `vpnkit_live_bypass_inner_21471-vpnkit-1`.
- Inner diagnostic OpenVPN port: `21471/udp`.
- Shared isolated network: `vpnkit_live_bypass_net_21470_21471_21472`.
- Same-host client container: `vpnkit-live-bypass-vibe-client-21470_21471_21472`.
- Remote client container/image: `vpnkit-live-bypass-moscow-21470_21471_21472` / `vpnkit-live-bypass-client-21470_21471_21472`.
- Public echo process path/port during this run: `/tmp/vpnkit_live_bypass_client_21470_21471_21472`, `21472/udp` on moscow-tiger (removed). This echo attempt happened after the inner tunnel and is recorded as non-decisive because the inner tunnel changed client routes.

### Reduced public UDP echo run

- vibe-practicum temp path: `/tmp/vpnkit_public_echo_21473_21475` (removed).
- Outer server project/container: `vpnkit_public_echo_outer_21473` / `vpnkit_public_echo_outer_21473-vpnkit-1`.
- Outer OpenVPN port: `21473/udp`.
- Same-host public-echo client container/image: `vpnkit-public-echo-client-21473_21475` / `vpnkit-public-echo-client-21473_21475`.
- moscow-tiger echo process path/port: `/tmp/vpnkit_public_echo_21473_21475`, `21475/udp` (removed).

### Focused Stage 1 true nested run

- vibe-practicum temp path: `/tmp/vpnkit_stage1_nested_21478_21479` (removed).
- Outer server project/container: `vpnkit_stage1_nested_outer_21478` / `vpnkit_stage1_nested_outer_21478-vpnkit-1`.
- Outer OpenVPN port: `21478/udp`.
- Inner server project/container: `vpnkit_stage1_nested_inner_21479` / `vpnkit_stage1_nested_inner_21479-vpnkit-1`.
- Inner diagnostic OpenVPN port: `21479/udp`.
- Shared isolated server network: `vpnkit_stage1_nested_net_21478_21479`.
- Same-host client container/image: `vpnkit-stage1-nested-client-21478_21479` / `vpnkit-stage1-nested-client-21478_21479`; this client was not attached to the inner server network and connected to the outer server through the published high UDP port.

Cleanup-only notes:
- Two initial wrapper attempts stopped locally before remote mutation because of an endpoint-resolution shell bug.
- One temp-tree copy attempt after public echo startup cleaned all resources before server startup.
- One focused Stage 1 setup attempt on `21476/udp` + `21477/udp` started isolated servers but failed before client run due to a temp profile path bug; cleanup verified no leftovers before retrying on `21478/udp` + `21479/udp`.

## Pass/fail matrix

| Check | Evidence | Result |
| --- | --- | --- |
| Stage 1 baseline, vibe-practicum isolated client/server | Full run: `STAGE1_OUTER_UP`, `STAGE1_DNS_NOERROR`, `STAGE1_HTTPS_CODE=200`, `STAGE1_LITERAL_CODE=200` on outer port `21470/udp`. Focused true nested run repeated baseline on `21478/udp`: `STAGE1_TRUE_OUTER_UP`, `STAGE1_TRUE_DNS_NOERROR`, `STAGE1_TRUE_HTTPS_CODE=200`, `STAGE1_TRUE_LITERAL_CODE=200`. | PASS |
| Stage 1 nested private OpenVPN | Focused true nested run: client route to inner container endpoint was `dev tun0`; inner OpenVPN reached `STAGE1_TRUE_INNER_UP`; outer private UDP bypass counters showed `172.16.0.0/12` outbound/return packets. | PASS |
| Stage 2 baseline, moscow-tiger isolated client to vibe-practicum isolated server | Full run: `STAGE2_OUTER_UP`, `STAGE2_DNS_NOERROR`, `STAGE2_HTTPS_CODE=200`, `STAGE2_LITERAL_CODE=200` against outer port `21470/udp`. | PASS |
| Stage 2 nested private OpenVPN | Full run: `STAGE2_ROUTE_TO_INNER=tun0`, `STAGE2_INNER_UP`; outer private UDP bypass counters showed `172.16.0.0/12` traffic. | PASS |
| Public non-DNS UDP echo through outer tunnel | Reduced public echo run: route to moscow-tiger echo endpoint was `dev tun0`; `PUBLIC_UDP_ECHO_TIMEOUT`; outer generic non-private UDP TPROXY rule incremented `1` packet / `44` bytes; private UDP bypass counters stayed zero. | FAIL for public UDP TPROXY egress; distinction recorded |
| Cleanup | Final checks reported `vibe_final_leftovers=no` and `moscow_final_leftovers=no`; all named temp paths, containers, images, volumes, networks, and echo processes removed. | PASS |
| Production untouched | Safe `docker inspect vpnkit` metadata stayed `name=/vpnkit status=running restart=0 started=2026-06-02T13:47:35.235471647Z` before/mid/after all runs. | PASS |

## Sanitized command shapes

```bash
# Source private endpoints without printing values.
set -a; . config/private-endpoints.local.env; set +a

# Package current worktree plus gitignored matching bundle, excluding private env/logs/.git.
tar --exclude='.git' --exclude='logs/*' --exclude='config/private-endpoints.local.env' ...
scp <temp-tar> vibe-practicum:<isolated-temp>/src.tgz

# Start isolated tproxy vpnkit servers with fresh projects/ports.
VPNKIT_OPENVPN_PORT=<fresh-high-port> \
VPNKIT_ENABLE_VIBE_VPN_DAEMON=false \
VPNKIT_ROUTING_MODE=tproxy \
VPNKIT_IPV6_POLICY=block \
docker compose -p <fresh-project> up -d --build vpnkit

# Run isolated OpenVPN client containers with temp profile remote lines only.
docker run --rm --cap-add NET_ADMIN --cap-add NET_RAW --device /dev/net/tun \
  -v <temp-client-dir>:/etc/openvpn/client:ro \
  --entrypoint bash <fresh-client-image> -lc '<outer baseline, route, inner OpenVPN, echo checks>'

# Cleanup every isolated resource by exact fresh name/path.
docker compose -p <fresh-project> down -v --remove-orphans
rm -rf <fresh-temp-path>
```

## Runtime counter excerpts (sanitized)

Stage 2/full run outer counters after same-host and moscow nested checks:

```text
OVPN_TO_SINGBOX udp/53 RETURN: 3 packets / 217 bytes
OVPN_TO_SINGBOX tcp RETURN: 49 packets / 5700 bytes
OVPN_TO_SINGBOX private UDP bypass 172.16.0.0/12: 8 packets / 3533 bytes
OVPN_TO_SINGBOX generic public UDP TPROXY: 0 packets / 0 bytes
OVPN_TPROXY_UDP_FWD 172.16.0.0/12 outbound: 8 packets / 3533 bytes
OVPN_TPROXY_UDP_FWD 172.16.0.0/12 return: 8 packets / 4036 bytes
Listeners present: udp/1194, udp/2082, udp/5353, tcp/2082, tcp/2083
```

Reduced public UDP echo counters:

```text
PUBLIC_OUTER_UP
PUBLIC_ROUTE_TO_ECHO=tun0
PUBLIC_UDP_ECHO_TIMEOUT
OVPN_TO_SINGBOX generic public UDP TPROXY: 1 packet / 44 bytes
OVPN_TPROXY_UDP_POST private CIDR MASQUERADE counters: 0
OVPN_TPROXY_UDP_FWD private CIDR counters: 0
```

Focused Stage 1 true nested counters:

```text
STAGE1_TRUE_ROUTE_TO_INNER=tun0
STAGE1_TRUE_INNER_UP
OVPN_TO_SINGBOX private UDP bypass 172.16.0.0/12: 8 packets / 3533 bytes
OVPN_TPROXY_UDP_POST 172.16.0.0/12 MASQUERADE: 1 packet / 82 bytes
OVPN_TPROXY_UDP_FWD 172.16.0.0/12 outbound: 8 packets / 3533 bytes
OVPN_TPROXY_UDP_FWD 172.16.0.0/12 return: 7 packets / 3652 bytes
```

## Interpretation

- The private UDP bypass fix is live-validated for private nested OpenVPN targets: both a same-host isolated client and the remote moscow-tiger isolated client reached an inner OpenVPN `tun1` through an established outer tunnel, with route-to-inner via `tun0` and private UDP bypass counters.
- The reduced public echo check distinguishes the remaining behavior: non-private UDP still enters the generic TPROXY rule and did not egress successfully to the isolated public UDP echo endpoint in this run.
- Therefore private Docker-IP nested OpenVPN passes, while public/non-private UDP TPROXY egress remains failing/not proven.

## Cleanup status

Final cleanup checks:

```text
vibe_final_leftovers=no
moscow_final_leftovers=no
prod=/vpnkit status=running restart=0 started=2026-06-02T13:47:35.235471647Z
```

Nothing was intentionally retained for debugging.
