# Hysteria2 Docker deploy bundle

Public-safe Docker Compose bundle for a Hysteria2 server deploy. This folder is
intended to be copied/rsynced to a server and run there with a gitignored `.env`.

## Public-safety rules

Do not commit or paste:

- real `.env` values;
- Hysteria2 auth or obfs passwords;
- private endpoint values or real server IPs;
- generated certificates, rendered configs, runtime data, or logs.

The real local `.env`, runtime `data/`, and logs are ignored by this repo.

## Files

```text
deploy/hysteria2/
  compose.yaml           # Hysteria2 server container; UDP/443 only
  config.yaml.template   # public-safe server config template/placeholders
  .env.example           # sanitized environment template
  README.md              # this runbook
```

## Network and TLS model

`compose.yaml` publishes only UDP/443:

```text
443/udp on host -> 443/udp in container
```

This keeps TCP/80 and TCP/443 available for Caddy or another HTTPS server.
Hysteria2 uses UDP; Caddy can continue serving HTTPS on TCP/443 **only if Caddy
HTTP/3/QUIC is disabled** so Caddy is not also binding UDP/443.

The default live model for this bundle is to reuse an existing Caddy-managed
Let's Encrypt certificate. The host's Caddy certificate storage is mounted
read-only into the container and `.env` points `HY2_TLS_CERT` / `HY2_TLS_KEY` at
the certificate paths inside that read-only mount.

Before starting on a host that already runs Caddy:

1. Configure Caddy to serve only HTTP/1.1 and HTTP/2, not HTTP/3.
2. Reload Caddy.
3. Confirm UDP/443 is free:

   ```bash
   ss -lunp | grep ':443' || true
   ```

## Prepare locally on the server

From the copied deploy directory on the target server:

```bash
cd /path/to/hysteria2
cp .env.example .env
chmod 600 .env
$EDITOR .env
```

Edit `.env` with the real deployment values:

- `HY2_SERVER_NAME`: real DNS name used by clients and TLS SNI;
- `HY2_CADDY_CERTS_DIR`: host path to Caddy certificate storage;
- `HY2_TLS_CERT`: certificate path inside the container, under `/caddy-certs`;
- `HY2_TLS_KEY`: key path inside the container, under `/caddy-certs`;
- `HY2_AUTH_*_USER` / `HY2_AUTH_*_PASSWORD`: per-client `userpass` credentials;
- `HY2_OBFS_PASSWORD`: shared Salamander obfuscation password;
- optional runtime overrides such as `HY2_CONTAINER_NAME`, `HY2_HOST_UDP_PORT`,
  `HY2_IMAGE`, `HY2_DATA_DIR`, and `HY2_MASQUERADE_URL`.

The compose service renders its runtime Hysteria2 config inside the container
from those `.env` variables. `config.yaml.template` mirrors the expected server
shape for review/manual rendering, but no rendered secret config should be
committed.

## Copy to a server later

Example placeholder rsync command; replace the SSH alias and path locally:

```bash
rsync -av --exclude '.env' --exclude 'data/' --exclude 'logs/' \
  deploy/hysteria2/ your-server-ssh-alias:/opt/hysteria2/
```

Then create/edit `/opt/hysteria2/.env` on the server. Do not put real endpoint
or secret values in tracked repo files.

## Start

After `.env` is present and reviewed on the server:

```bash
cd /opt/hysteria2
docker compose --env-file .env -f compose.yaml config >/dev/null
docker compose --env-file .env -f compose.yaml up -d
```

## Verify on the server

Check container state and logs without printing secret files:

```bash
docker compose --env-file .env -f compose.yaml ps
docker compose --env-file .env -f compose.yaml logs --tail=100 hysteria2
```

Check that UDP/443 is listening/published:

```bash
ss -lunp | grep ':443'
docker port hysteria2-udp443 443/udp
```

If you changed `HY2_CONTAINER_NAME`, use that name in the `docker port` command.
A successful server-side listener check only proves the container is running and
UDP/443 is exposed; client connectivity still needs a separate Hysteria2 client
smoke test with the real local credentials.

## Stop / rollback

```bash
cd /opt/hysteria2
docker compose --env-file .env -f compose.yaml down
```

This removes the container but leaves local runtime data. Remove `data/` only
when you intentionally want to discard generated runtime state.
