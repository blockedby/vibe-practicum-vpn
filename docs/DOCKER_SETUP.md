# Docker vpnkit setup

This is the public-safe setup path for the current containerized `vpnkit` runtime. Real endpoints, SSH aliases, OpenVPN client profiles, subscriptions, auth files, rendered configs, and logs stay outside git.

## Private endpoints

1. Copy the tracked example file:

   ```bash
   cp config/private-endpoints.example.env config/private-endpoints.local.env
   ```

2. Fill `config/private-endpoints.local.env` with operator-local values. This file is gitignored.
3. Source it before commands that need real endpoint values:

   ```bash
   set -a
   . config/private-endpoints.local.env
   set +a
   ```

Public/test availability-check domains in scripts and tests are intentionally not replaced by this file.

## Local checks and build

```bash
go test ./...
go vet ./...
go build -o /tmp/vibe-vpn ./cmd/vibe-vpn
```

Optional shell/service checks:

```bash
bash -n scripts/*.sh
./scripts/validate-vibe-vpn-service-assets.sh
```

## Prepare gitignored local secrets

Expected local-only inputs live under `secrets/`, for example:

```text
secrets/vps/openvpn/pki/
secrets/vps/openvpn/client/test-client.ovpn
secrets/vps/vibe-vpn/sub_url
secrets/vps/vibe-vpn/extra-nodes.json
secrets/vps/vibe-vpn/lil-sweden-hy2-auth
```

Render local configs from the current checkout:

```bash
scripts/vpnkit-render-local-configs.sh
```

Rendered config and client profile outputs remain under gitignored `secrets/vps/rendered/` and `secrets/vps/openvpn/client/`.

The tracked OpenVPN server template intentionally includes `tun-mtu 1400` and `mssfix 1360`. This persists the `moscow-tiger` runtime fix for a path-MTU/MSS issue where clients received a tunnel address and DNS `NOERROR`, but HTTPS by hostname timed out until TCP segment size was clamped. Keep the rendered `server.conf` gitignored; verify directives with a sanitized grep instead of committing rendered config contents.

`vibe-vpn` subscription input stays gitignored as `secrets/vps/vibe-vpn/sub_url` (or the documented fallback names). If no operator-managed extra nodes are needed or a previous extra-nodes file is invalid, use an empty JSON list in gitignored `secrets/vps/vibe-vpn/extra-nodes.json`; the render path also writes `[]` when that file is absent.

## Local Docker lab

Use the Docker lab before changing any live runtime:

```bash
docker compose down -v --remove-orphans || true

VPNKIT_ENABLE_VIBE_VPN_DAEMON=true \
VPNKIT_ROUTING_MODE=redirect \
VPNKIT_IPV6_POLICY=block \
VPNKIT_COMPAT_BYPASS_ENABLED=true \
VPNKIT_COMPAT_BYPASS_ENDPOINTS='<COMPAT_BYPASS_ENDPOINTS>' \
docker compose up -d --build vpnkit

docker compose exec vpnkit ps auxww | grep -E '[o]penvpn|[s]ing-box|[v]ibe-vpn'

VPNKIT_ENABLE_VIBE_VPN_DAEMON=true \
VPNKIT_ROUTING_MODE=redirect \
VPNKIT_IPV6_POLICY=block \
VPNKIT_COMPAT_BYPASS_ENABLED=true \
VPNKIT_COMPAT_BYPASS_ENDPOINTS='<COMPAT_BYPASS_ENDPOINTS>' \
docker compose --profile test run --rm ovpn-client-test
```

Expected client-test result: OpenVPN connects, client receives a VPN address, DNS returns `NOERROR`, HTTPS returns `200`, and literal-IP HTTPS returns `200`.

### Routing mode consistency

The Compose default is `VPNKIT_ROUTING_MODE=redirect`, matching the tracked
`config/sing-box/config.json.template` redirect inbound on TCP `2082` and DNS
inbound on UDP `5353`. Keep these settings aligned for redirect-mode production
runs: if production sets `VPNKIT_ROUTING_MODE=redirect`, the rendered sing-box
config must include both the redirect inbound and the DNS inbound. `tproxy` mode
uses TCP `2082` without the DNS redirect readiness gate. `tun` mode uses
`config/sing-box/config.tun.json.template`, creates `${SINGBOX_TUN_IFACE:-sb-tun0}`
with the tracked default address/peer pair used by `setup-routing.sh`, and waits
for that interface instead of redirect ports.

`docker-compose.yml` passes `OVPN_CIDR` with the same public-safe default used by
`docker/vpnkit/setup-routing.sh`; production may override it from its local
`.env` without changing tracked files.

## Live operations boundary

Do not run SSH/SCP/deploy/recreate commands from public docs by copy-paste without first loading `config/private-endpoints.local.env` and confirming the target. Live runtime mutation is intentionally not documented with real hostnames or IP addresses in tracked files.
