# Slice verification evidence

## Automated/config checks

- `bash tests/vpnkit-singbox-template-test.sh` — PASS (`vpnkit sing-box templates ok`).
- `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh` — PASS.
- `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true sing-box check` on rendered dummy `config.json.template` and `config.tproxy.json.template` — PASS; warnings are existing deprecation warnings for legacy DNS/default resolver format.
- `go test ./...` — PASS.
- `go vet ./...` — PASS.
- `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn` — PASS.

## Local Docker lab

Isolated local lab inputs/resources:
- Compose project: `vpnkit_tproxy_udp_nested_lab`.
- Test OpenVPN host port: `21194/udp`.
- Containers used: `vpnkit_tproxy_udp_nested_lab-vpnkit-1`, ephemeral `vpnkit_tproxy_udp_nested_lab-ovpn-client-test-run-*`.
- Volumes/networks used: Compose-created `vpnkit_tproxy_udp_nested_lab_*` resources.
- Gitignored/generated local lab secrets/profiles: under `secrets/` only; not committed.

Observed PASS before client smoke:
- vpnkit tproxy container starts.
- sing-box starts with tproxy TCP listener `0.0.0.0:2082`, tproxy UDP listener `0.0.0.0:2082`, DNS UDP listener `0.0.0.0:5353`, and SOCKS listener `127.0.0.1:2080`.
- OpenVPN server initializes on UDP `1194` inside isolated container.
- TPROXY mangle chain contains TCP and UDP rules to port `2082` with mark `0x1/0x1`.

Observed FAIL / current blocker:
- Isolated client-test connects to outer OpenVPN successfully and receives `10.89.0.2/24` plus default split routes through `10.89.0.1`.
- UDP DNS through the tunnel fails: `dig +time=10 +tries=1 @8.8.8.8 example.com` times out with `no servers could be reached`.
- Server-side mangle counter increments for the UDP TPROXY rule, proving the tunneled UDP packet reaches the TPROXY rule, but the client does not receive a DNS response.
- Because local Docker lab did not pass, no live-host mutation/testing was attempted.

## Cleanup / production untouched

- Cleanup run: `docker compose -p vpnkit_tproxy_udp_nested_lab down -v --remove-orphans`; isolated lab containers/volumes/network removed.
- After cleanup, no containers named `vpnkit_tproxy_udp_nested_lab-*` remained.
- Production/hard-boundary containers `vpnkit` and `current-vpnkit-1` were not present in `docker ps -a` output; no production containers were restarted/recreated/exec-mutated by this slice.
- Existing non-slice containers observed but not touched included `vpnkit-compat-bypass-vpnkit-1` and `vpnkit-client-127.0.0.1-183549`.
- `config/private-endpoints.local.env` is absent in this worktree, so live-host testing is also blocked until local lab passes and private endpoints are available.
