# Repository agent notes

## Public-safety rules

- This repository is being prepared for public publication. Do not commit or reveal secrets, private keys, generated OpenVPN profiles, rendered configs, subscription URLs, auth files, logs, snapshots, image exports, or private endpoint values.
- Real private endpoints/SSH aliases/IPs/domains belong only in the gitignored file:
  - `config/private-endpoints.local.env`
- A sanitized tracked template is available at:
  - `config/private-endpoints.example.env`
- Before running commands that require real private endpoints, agents/operators should inspect and source the gitignored local file if it exists:
  ```bash
  test -r config/private-endpoints.local.env && set -a && . config/private-endpoints.local.env && set +a
  ```
- If `config/private-endpoints.local.env` is absent, use placeholders in docs and stop before live/runtime mutation.
- Public/test availability-check domains used by tests or health probes are intentionally allowed to remain tracked; do not replace them merely because they are public domains.

## Container images and runtimes

- Use the current Docker setup documentation in `docs/DOCKER_SETUP.md` for local validation.
- Steam Deck deployment remains Podman-only when intentionally operating on a Deck, but tracked public docs must not include real Deck LAN endpoints.
- Docker/Podman images are build artifacts, not source artifacts. Do not commit generated image exports or logs.
- For tests or experiments on a live host, start separate throwaway containers with distinct names, Compose project names, ports, networks, volumes, and state directories. Do **not** reuse, remove, recreate, restart, or adopt the production `vpnkit` container for tests.
- Mutating the production `vpnkit` container is allowed only for an explicit deploy/rollback/maintenance action after operator approval, with a backup/rollback path and post-change smoke tests.

## Default testing workflow before live deploy

For `vpnkit` runtime, routing, OpenVPN, sing-box, DNS, IPv6, or `vibe-vpn` daemon changes, do not deploy directly to any live host first. Use the local Docker lab and client-test container as the default acceptance path, then mutate a live runtime only after local evidence passes and private endpoint values are loaded from the gitignored local endpoint file.

## Production VPN topology and routing decisions

- Production is a two-endpoint OpenVPN failover topology. Real endpoint values, SSH aliases, private IPs, and generated client profiles remain local/gitignored; use `config/private-endpoints.local.env` as the source of truth for live values.
- The operator-facing OpenVPN endpoint is a stable failover DNS name with two `A` records. User-importable profiles should keep deterministic fallback order:
  1. failover DNS name on UDP `1194`
  2. first concrete endpoint on UDP `1194`
  3. second concrete endpoint on UDP `1194`
- Do **not** add `remote-random` unless the operator explicitly wants random distribution instead of ordered failover.
- Steam Deck, phone, PC, and router are ordinary OpenVPN clients. Do not generate LAN/hotspot-only profiles for them unless a task explicitly asks for Deck-local hotspot gateway work.
- Production `vpnkit` full-tunnel mode is `VPNKIT_ROUTING_MODE=tun`, using sing-box TUN (`sb-tun0`) plus policy routing from the OpenVPN client CIDR into the sing-box TUN table.
- `redirect` mode only handles TCP redirect plus DNS (`udp/53`) hijack; it is **not** full-tunnel and does not carry ICMP/ping or arbitrary UDP. Do not use `redirect` mode for production full-tunnel acceptance.
- `OVPN_CIDR` must match the actual OpenVPN server client network. If it is wrong, policy routing or redirect rules can match the wrong source range and clients will appear connected but traffic will fail.
- Persisted sing-box runtime state can drift across deploys or mode changes. When switching modes, ensure the persisted `/var/lib/vpnkit/sing-box/config.json` matches the mounted/rendered sing-box config before recreating the container.
- The OpenVPN server intentionally pushes `redirect-gateway def1 bypass-dhcp` and a VPN DNS option; the full-tunnel server path must therefore carry DNS, TCP/HTTPS, literal-IP HTTPS, ICMP, and general IP traffic.
- The OpenVPN server template intentionally keeps `tun-mtu 1400` and `mssfix 1360`; do not remove them without fresh MTU/MSS evidence.

## Production deployment and acceptance checklist

- Production mutation requires explicit operator approval, a rollback image/tag or equivalent backup, and post-change smoke tests on every production endpoint.
- Discover each Compose working directory from Docker Compose labels or approved private config; do not assume a hard-coded path when operating on a live host.
- Updating one endpoint is not enough for failover work. Deploy and verify every production endpoint in the failover set.
- After deploy/recreate, verify at minimum on each endpoint:
  - SSH reachable and Docker/Compose available
  - `vpnkit` container running
  - UDP `1194` published/listening
  - OpenVPN process up and `tun0` exists
  - sing-box process up and `sb-tun0` exists for `tun` mode
  - policy rule for the OpenVPN client CIDR points at the sing-box routing table
  - routing table has the sing-box TUN default route
- Real profile acceptance must test the same style of profile intended for users. For failover profiles, test:
  - domain profile as-is
  - endpoint 1 forced
  - endpoint 2 forced
- A full-tunnel profile is not accepted unless all of these pass through the VPN: OpenVPN readiness, route via client `tun0`, DNS, HTTPS by hostname, HTTPS by literal IP, `ping 1.1.1.1`, and `ping 8.8.8.8`.
- Docker OpenVPN client tests are useful acceptance evidence for server data path, but they do not prove GUI import behavior on phone/PC/router. If a user reports client import or UI failures, inspect client/server logs for that real attempt instead of claiming success from Docker alone.

## Container test runner

- Use `test/containers-test.sh` as the unified container acceptance runner for vpnkit server-container plus OpenVPN client-container checks, especially for Steam Deck test deployments and future sing-box routing-policy/adblock/dev-direct validation.
- The runner intentionally has simple behavior: it tests everything it knows about rather than requiring mode/group flags.
- Missing inputs, unavailable SSH targets, absent profiles, missing endpoint values, or unavailable runtime tools should be reported as `SKIP` or a clear `FAIL` reason while the runner continues to later checks; do not make one missing prerequisite abort the whole run.
- The runner must write redacted output to both console and a log file immediately. Default log path is `logs/vpnkit-containers-test-<timestamp>.log`; use `VPNKIT_CONTAINERS_TEST_LOG` to override.
- For Deck tests, source `config/private-endpoints.local.env` when available, then run with `VPNKIT_TEST_SSH_TARGET`, `VPNKIT_TEST_RUNTIME=podman`, `VPNKIT_TEST_SERVER_CONTAINER`, `VPNKIT_TEST_ENDPOINT`, and `VPNKIT_TEST_PROFILE` as needed.
