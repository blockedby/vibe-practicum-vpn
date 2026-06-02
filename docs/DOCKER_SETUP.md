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

## Live operations boundary

Do not run SSH/SCP/deploy/recreate commands from public docs by copy-paste without first loading `config/private-endpoints.local.env` and confirming the target. Live runtime mutation is intentionally not documented with real hostnames or IP addresses in tracked files.
