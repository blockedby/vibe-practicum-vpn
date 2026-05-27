# Vibe VPN failover service runbook

This runbook prepares the local `vibe-vpn daemon` failover service for a future VPS deploy. The local implementation in this branch was **not deployed, enabled, started, or smoke-tested on the VPS**; do those steps manually only when ready.

## Files and paths

- Binary: `/usr/local/bin/vibe-vpn`
- Systemd unit: `/etc/systemd/system/vibe-vpn.service` from `systemd/vibe-vpn.service`
- Config: `/etc/vibe-vpn/config.yaml` (JSON also supported)
- Subscription secrets: `/etc/vibe-vpn/sub_url` and optional `/etc/vibe-vpn/extra-nodes.json` (not in git)
- State: `/var/lib/vibe-vpn/last-results.json`, `current-node.json`, `current-link.txt`, `backups/`
- Service logs: `/var/log/vibe-vpn/vibe-vpn-YYYY-MM-DD-HH.log`, default retention `12h`
- Journal: important events also go to stdout/stderr for `journalctl -u vibe-vpn`

## Install or update on VPS

Build and copy the binary by your normal deploy path, then install the unit and config:

```bash
sudo install -o root -g root -m 755 /tmp/vibe-vpn /usr/local/bin/vibe-vpn
sudo install -o root -g root -m 644 systemd/vibe-vpn.service /etc/systemd/system/vibe-vpn.service
sudo install -d -o root -g root -m 700 /etc/vibe-vpn /var/lib/vibe-vpn /var/log/vibe-vpn
sudo install -o root -g root -m 600 examples/vibe-vpn-config.yaml /etc/vibe-vpn/config.yaml
sudo systemctl daemon-reload
sudo systemctl enable --now vibe-vpn
```

Use `scripts/install-vibe-vpn-service.sh` as a parameterized local packaging helper if desired. It only installs files on the host where it is run; it does not SSH/SCP by itself.

## Normal operations

```bash
sudo systemctl status vibe-vpn
sudo journalctl -u vibe-vpn --since "12 hours ago"
sudo journalctl -u vibe-vpn -f
sudo ls -lah /var/log/vibe-vpn/
```

Manual commands still exist and remain useful:

```bash
sudo vibe-vpn status
sudo vibe-vpn test --limit-kib 64 --max 2
sudo vibe-vpn pick --limit-kib 256
sudo vibe-vpn apply <index>
sudo vibe-vpn rollback
```

`test` never applies production changes. In the default daemon mode (`service.mode: failover-only`), the scheduled test loop uses the same safe non-apply path: startup/scheduled benchmarks refresh results, and only confirmed production health failure triggers failover.

Optional `service.mode: fastest-rotation` changes only the daemon scheduled-test success hook. After each successful scheduled/startup test, the daemon runs the configured production SOCKS health probe (`health.required_urls` determine failover health; `health.diagnostic_urls` are diagnostic), loads the fresh latest benchmark results, and applies the fastest OK non-excluded node even if health is currently OK. If that fastest node is already current by the normal current-node comparison, it skips apply. If the scheduled test fails and old results are restored/preserved, fastest rotation does not apply from those old results; the daemon logs the error and stays alive.

## Config example

```yaml
service:
  enabled: true
  startup_test: true
  mode: failover-only # default; alternative: fastest-rotation

test:
  interval: 30m

health:
  normal_interval: 5s
  failure_retry_delays: [1s, 2s, 3s]
  probe_timeout: 5s
  required_urls:
    - https://x.com/
    - https://rutracker.org/
  diagnostic_urls:
    - https://ya.ru/

logging:
  path: /var/log/vibe-vpn/
  retention: 12h
  also_journal: true
```

Full sample: [`examples/vibe-vpn-config.yaml`](../examples/vibe-vpn-config.yaml). Accelerated smoke sample: [`examples/vibe-vpn-smoke-config.yaml`](../examples/vibe-vpn-smoke-config.yaml).

Fastest-rotation example override:

```yaml
service:
  enabled: true
  startup_test: true
  mode: fastest-rotation
```

## Accelerated manual smoke config

For a quick operator smoke after deployment, use a copied config with shorter test interval and low benchmark limits. Keep the health failure retry sequence unchanged to verify the intended 1s/2s/3s state machine.

```bash
sudo install -o root -g root -m 600 examples/vibe-vpn-smoke-config.yaml /etc/vibe-vpn/config-smoke.yaml
sudo /usr/local/bin/vibe-vpn daemon --config /etc/vibe-vpn/config-smoke.yaml
```

Or edit `/etc/vibe-vpn/config.yaml` temporarily and then restart the service manually. This was not run by the agent because the user forbade VPS/systemd mutation.

## Pre-deploy checks

Run locally before copying anything:

```bash
go test ./...
go vet ./...
go build ./cmd/vibe-vpn
bash -n scripts/install-vibe-vpn-service.sh
bash -n scripts/validate-vibe-vpn-service-assets.sh
./scripts/validate-vibe-vpn-service-assets.sh
```

On the VPS, before `enable --now`, verify:

```bash
sudo /usr/local/bin/vibe-vpn doctor --config /etc/vibe-vpn/config.yaml
sudo /usr/local/bin/vibe-vpn test --config /etc/vibe-vpn/config.yaml --limit-kib 64 --max 2
sudo systemd-analyze verify /etc/systemd/system/vibe-vpn.service
```

## Rollback

Disable the daemon first, then use the existing production rollback path:

```bash
sudo systemctl disable --now vibe-vpn
sudo vibe-vpn rollback --config /etc/vibe-vpn/config.yaml
sudo systemctl status xray
sudo vibe-vpn status --config /etc/vibe-vpn/config.yaml
```

If the new service binary or unit is suspected, restore the previous `/usr/local/bin/vibe-vpn` and `/etc/systemd/system/vibe-vpn.service`, then run `sudo systemctl daemon-reload`.

## Secrets and redaction

Never commit real subscription URLs, `vless://` links, tokens, or auth secrets. Keep `/etc/vibe-vpn/sub_url` mode `0600`. Service logs redact full VLESS links and sensitive token/auth-like values, but operators should still avoid pasting raw log bundles into issues or chats without review.
