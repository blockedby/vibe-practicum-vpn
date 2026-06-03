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

## vpnkit routing modes

`VPNKIT_ROUTING_MODE` defaults to `redirect`; this remains the production/default Docker lab path. `tproxy` remains available for the existing transparent-proxy canary path.

A new opt-in TUN canary is available with:

```bash
VPNKIT_ROUTING_MODE=tun docker compose up -d --build vpnkit
```

TUN mode renders and selects `config.tun.json`, starts a sing-box `tun` inbound named `vpnkit-tun-in` on interface `sb-tun0` (`172.19.0.1/30`, MTU 1400), and policy-routes only OpenVPN client CIDR traffic through that interface. It intentionally does not install redirect or tproxy capture rules. Keep using isolated Docker project names, fresh ports, and gitignored rendered configs/profiles for canary validation.

## Live operations boundary

Do not run SSH/SCP/deploy/recreate commands from public docs by copy-paste without first loading `config/private-endpoints.local.env` and confirming the target. Live runtime mutation is intentionally not documented with real hostnames or IP addresses in tracked files.
