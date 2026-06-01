# Steam Deck Podman vpnkit deployment

This runbook deploys the containerized vpnkit runtime to a Steam Deck over SSH using plain `podman`. It is separate from the local Docker e2e path in `docs/CONTAINERIZED_VPNKIT_RUNBOOK.md`.

Do not run VPS deployment or `systemctl` commands for this workflow. Do not print or commit subscription URLs, private keys, generated client profiles, or raw rendered configs.

## Prerequisites

- SSH target for the Deck, for example `deck` on LAN or `steamdeck-ts` over Tailscale.
- Podman available on the Deck.
- Rendered local vpnkit inputs already prepared under gitignored `secrets/vps/rendered`:
  - `openvpn/server.conf`
  - `sing-box/config.json`
  - `vibe-vpn/config.yaml`
  - `vibe-vpn/sub_url`

Prepare/render secrets only with the existing local helpers when intentionally operating with real material:

```bash
scripts/vpnkit-copy-vps-secrets.sh vibe-practicum
scripts/vpnkit-render-local-configs.sh
```

## Read-only discovery

```bash
scripts/vpnkit-steamdeck-podman.sh --ssh-target deck check-ssh
scripts/vpnkit-steamdeck-podman.sh --ssh-target steamdeck-ts --ssh-option '-p 2222' check-ssh
```

## Deploy

Default remote state is `~/.local/state/vpnkit`. The script resolves `~` / `~/...` over SSH to the Deck user's real `$HOME` before creating directories or using Podman volume mounts; absolute remote paths are used unchanged. It transfers a tracked `git archive` build context plus the rendered gitignored config tree. It logs only paths/sizes and redacted runtime excerpts.

```bash
scripts/vpnkit-steamdeck-podman.sh \
  --ssh-target deck \
  --remote-dir '~/.local/state/vpnkit' \
  --image localhost/vpnkit:steamdeck \
  --container vpnkit \
  --openvpn-port 1194 \
  --lan-endpoint 192.168.50.13 \
  --log-file logs/steamdeck-podman/deploy-lan-$(date -u +%Y%m%dT%H%M%SZ).log \
  deploy
```

Tailscale example:

```bash
scripts/vpnkit-steamdeck-podman.sh \
  --ssh-target steamdeck-ts \
  --ssh-option '-p 2222' \
  --remote-dir '~/.local/state/vpnkit' \
  --image localhost/vpnkit:steamdeck \
  --container vpnkit \
  --openvpn-port 1194 \
  --tailscale-endpoint 100.94.95.32 \
  --log-file logs/steamdeck-podman/deploy-ts-$(date -u +%Y%m%dT%H%M%SZ).log \
  deploy
```

## Runtime wiring

The `run`/`deploy` action recreates the container with:

- `--privileged`, `--cap-add NET_ADMIN`, `--cap-add NET_RAW`
- `/dev/net/tun:/dev/net/tun`
- OpenVPN UDP host port `${VPNKIT_OPENVPN_PORT:-1194}` mapped to container `1194/udp`
- sysctls: IPv4 forwarding, `src_valid_mark`, and disabled reverse-path filter
- read-only rendered config volumes for `/etc/openvpn`, `/etc/sing-box`, `/etc/vibe-vpn`
- writable state/log volumes below the remote state directory
- the existing image entrypoint, which starts `sing-box`, `openvpn`, routing setup, and `vibe-vpn` doctor/test tooling inside the image

## Operations

```bash
scripts/vpnkit-steamdeck-podman.sh --ssh-target deck status
scripts/vpnkit-steamdeck-podman.sh --ssh-target deck verify
scripts/vpnkit-steamdeck-podman.sh --ssh-target deck logs
scripts/vpnkit-steamdeck-podman.sh --ssh-target deck stop
scripts/vpnkit-steamdeck-podman.sh --ssh-target deck cleanup
```

`cleanup --remove-image` also removes the configured image tag.

## Verification checklist

Record redacted evidence in the active task package:

- `bash -n scripts/vpnkit-steamdeck-podman.sh`
- `docker compose config` and `docker compose --profile test config`
- `go test ./...`
- Deck read-only: `check-ssh`
- Deck deploy: `deploy`, `status`, `verify`, `logs`
- Confirm no real secrets appear in tracked diffs before commit.

OpenVPN client e2e from this host can be run with the tracked client test helper. It creates an endpoint-specific temporary profile, runs the existing OpenVPN client test container, and writes redacted logs when `--log-file` is set:

```bash
scripts/vpnkit-steamdeck-client-test.sh \
  --endpoint 192.168.50.13 \
  --log-file logs/steamdeck-podman/client-lan-$(date -u +%Y%m%dT%H%M%SZ).log

scripts/vpnkit-steamdeck-client-test.sh \
  --endpoint 100.94.95.32 \
  --log-file logs/steamdeck-podman/client-tailscale-$(date -u +%Y%m%dT%H%M%SZ).log
```

The helper requires local container runtime access (`docker` by default, or `--runtime podman`) and `/dev/net/tun`. Do not commit generated profiles or logs.
