# vpnkit + vibe-vpn container e2e runbook

This lab runs OpenVPN, sing-box, and the branch-built `vibe-vpn` binary inside the
`vpnkit` container. The current supported mode is observe/control-limited:
`vibe-vpn doctor` and `vibe-vpn test` run against real gitignored subscription
input, while the existing REDIRECT + DNS hijack path remains owned by the
container entrypoint and `setup-routing.sh`.

## Secrets and rendering

Do not commit subscription URLs, full `vless://` links, keys, generated OpenVPN
profiles, or rendered configs. Prepare gitignored local inputs under
`secrets/vps/`, then render:

```bash
scripts/vpnkit-render-local-configs.sh
```

For `vibe-vpn`, provide one of:

```text
secrets/vps/vibe-vpn/sub_url
secrets/vps/vibe-vpn/subscription.url
secrets/vps/vibe-vpn/subscription.txt
secrets/vps/sub_url
```

The renderer writes gitignored container files to
`secrets/vps/rendered/vibe-vpn/`, including `config.yaml` from the sanitized
tracked template at `config/vibe-vpn/container-lab.yaml.template`.

To include `lil-sweden` Hysteria2 in `vibe-vpn test`/daemon periodic tests,
copy the sanitized template and provide the auth file locally:

```bash
mkdir -p secrets/vps/vibe-vpn
cp config/vibe-vpn/extra-nodes.lil-sweden.hy2.json.template \
  secrets/vps/vibe-vpn/extra-nodes.json
install -m 600 /path/to/lil-sweden-hy2-auth \
  secrets/vps/vibe-vpn/lil-sweden-hy2-auth
scripts/vpnkit-render-local-configs.sh
```

The tracked template dials `84.22.149.216:443` with TLS/SNI
`computer.peacedata.company` to avoid DNS bootstrap loops inside sing-box.

## Run the e2e

```bash
scripts/vpnkit-vibe-vpn-e2e.sh --run-id manual-$(date -u +%Y%m%dT%H%M%SZ)
```

Useful options:

```text
--run-id ID
--log-file PATH
--keep-artifacts
--cleanup-on-failure
--no-build
--cleanup-images / --no-cleanup-images
```

By default logs go to `logs/vpnkit-vibe-vpn-e2e/<run-id>.log`. The runner uses a
unique Compose project name and a generated override that removes the fixed host
OpenVPN port for the e2e path, so multiple runs do not collide on container names
or `1194/udp`.

## Expected checks

The runner validates compose config, builds the image unless `--no-build` is
set, starts `vpnkit`, runs:

```bash
vibe-vpn doctor --config /etc/vibe-vpn/config.yaml
vibe-vpn test --config /etc/vibe-vpn/config.yaml --limit-kib 64 --max 2
sing-box check -c /etc/sing-box/config.json
```

Then it runs the OpenVPN client test. Passing evidence should show the client
receiving a `10.89.0.x` address, DNS resolution through the hijacked path, HTTPS
checks succeeding, and sing-box logs mentioning `selected-native-out` when the
configured node is used.

## Cleanup

On success the runner removes containers, volumes, orphans, and local e2e-built
images by default. On failure it keeps artifacts for debugging and prints the
exact cleanup command. Use `--cleanup-on-failure` when a failed run should still
run `docker compose down --remove-orphans --volumes`; combine it with
`--cleanup-images` or `--no-cleanup-images` to control whether local e2e-built
images are removed. `--keep-artifacts` keeps artifacts regardless of success.
Logs and redacted evidence under `logs/` are never deleted automatically.

## Daemon mode

By default the container starts OpenVPN and sing-box only. Enable the long-running
`vibe-vpn daemon` explicitly:

```bash
VPNKIT_ENABLE_VIBE_VPN_DAEMON=true docker compose up -d vpnkit
```

or pass the same environment variable to `docker run`/Podman. The daemon uses the
container-safe sing-box request-file restart adapter from
`config/vibe-vpn/container-lab.yaml.template`; the vpnkit entrypoint supervises
OpenVPN, sing-box, and the daemon process. Keep the `vpnkit-socks-in` sing-box
inbound at `127.0.0.1:2080` because daemon health probes use `production_socks`.

The container template defaults to `service.mode: failover-only`: periodic tests
update `last-results.json`, while automatic switching is reserved for confirmed
health failures. Use `mode: fastest-rotation` only when regular fastest-node
switching is intended.
