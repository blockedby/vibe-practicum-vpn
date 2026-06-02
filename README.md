# vibe-practicum-vpn

Operational docs and Go tooling for the `vibe-practicum` VPS VPN/routing setup.

Repository: <https://github.com/blockedby/vibe-practicum-vpn>

## Local checks and build

Containerized vpnkit currently defaults to an IPv4-only client policy: compose exposes `VPNKIT_IPV6_POLICY=block`, sing-box DNS defaults to `ipv4_only`, and OpenVPN-client IPv6 traffic is dropped by managed `ip6tables` rules. See [`docs/CONTAINERIZED_VPNKIT_RUNBOOK.md`](./docs/CONTAINERIZED_VPNKIT_RUNBOOK.md) for safe verification and deploy/recreate steps.

```bash
go test ./...
go vet ./...
go build -o /tmp/vibe-vpn ./cmd/vibe-vpn
```

Optional service asset checks:

```bash
bash -n scripts/install-vibe-vpn-service.sh
bash -n scripts/validate-vibe-vpn-service-assets.sh
./scripts/validate-vibe-vpn-service-assets.sh
```

Cross-build the VPS binary from a workstation:

```bash
GOOS=linux GOARCH=amd64 go build -o /tmp/vibe-vpn ./cmd/vibe-vpn
```

## VPS install/update commands

> Run these only when intentionally operating on the VPS. They are documented here; local verification should not run `systemctl`, live SSH/SCP deploys, production `xray`, or VPS-mutating commands.

From a workstation:

```bash
scp /tmp/vibe-vpn vibe-practicum:/tmp/vibe-vpn
scp systemd/vibe-vpn.service vibe-practicum:/tmp/vibe-vpn.service
scp examples/vibe-vpn-config.yaml vibe-practicum:/tmp/vibe-vpn-config.yaml
```

On the VPS:

```bash
sudo install -d -o root -g root -m 700 /etc/vibe-vpn /var/lib/vibe-vpn /var/log/vibe-vpn
sudo install -o root -g root -m 755 /tmp/vibe-vpn /usr/local/bin/vibe-vpn
sudo install -o root -g root -m 644 /tmp/vibe-vpn.service /etc/systemd/system/vibe-vpn.service
sudo install -o root -g root -m 600 /tmp/vibe-vpn-config.yaml /etc/vibe-vpn/config.yaml
```

Or, on the target host with repo files present:

```bash
sudo scripts/install-vibe-vpn-service.sh --binary /tmp/vibe-vpn --config examples/vibe-vpn-config.yaml
```

Prepare or migrate subscription secrets on the VPS:

```bash
sudo install -d -o root -g root -m 700 /etc/vibe-vpn /var/lib/vibe-vpn /var/log/vibe-vpn
sudo sh -c 'if [ -f /etc/vibe-proxy/sub_url ] && [ ! -f /etc/vibe-vpn/sub_url ]; then cp /etc/vibe-proxy/sub_url /etc/vibe-vpn/sub_url; elif [ ! -f /etc/vibe-vpn/sub_url ]; then : > /etc/vibe-vpn/sub_url; fi'
sudo chown root:root /etc/vibe-vpn/sub_url
sudo chmod 600 /etc/vibe-vpn/sub_url
```

## VPS validation and run commands

Validate before enabling the daemon:

```bash
sudo /usr/local/bin/vibe-vpn doctor --config /etc/vibe-vpn/config.yaml
sudo /usr/local/bin/vibe-vpn test --config /etc/vibe-vpn/config.yaml --limit-kib 64 --max 2
sudo systemd-analyze verify /etc/systemd/system/vibe-vpn.service
```

Enable and inspect the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now vibe-vpn
sudo systemctl status vibe-vpn
sudo journalctl -u vibe-vpn --since "12 hours ago"
sudo journalctl -u vibe-vpn -f
```

Run the daemon manually with the smoke config:

```bash
sudo install -o root -g root -m 600 examples/vibe-vpn-smoke-config.yaml /etc/vibe-vpn/config-smoke.yaml
sudo /usr/local/bin/vibe-vpn daemon --config /etc/vibe-vpn/config-smoke.yaml
```

Stop service and rollback production sing-box config if needed:

```bash
sudo systemctl disable --now vibe-vpn
sudo vibe-vpn rollback --config /etc/vibe-vpn/config.yaml
sudo systemctl status sing-box-vibe-router
sudo vibe-vpn status --config /etc/vibe-vpn/config.yaml
```

## Manual `vibe-vpn` commands

```bash
sudo vibe-vpn status --config /etc/vibe-vpn/config.yaml
sudo vibe-vpn refresh --config /etc/vibe-vpn/config.yaml
sudo vibe-vpn test --config /etc/vibe-vpn/config.yaml --limit-kib 64 --max 2
sudo vibe-vpn test --config /etc/vibe-vpn/config.yaml --limit-kib 256
sudo vibe-vpn test --config /etc/vibe-vpn/config.yaml --duration-sec 5 --max 20
sudo vibe-vpn list --config /etc/vibe-vpn/config.yaml --top 20
sudo vibe-vpn list --config /etc/vibe-vpn/config.yaml --failed
sudo vibe-vpn pick --config /etc/vibe-vpn/config.yaml --limit-kib 256
sudo vibe-vpn apply --config /etc/vibe-vpn/config.yaml <index>
sudo vibe-vpn apply --config /etc/vibe-vpn/config.yaml best
sudo vibe-vpn current --config /etc/vibe-vpn/config.yaml
sudo vibe-vpn current --config /etc/vibe-vpn/config.yaml --link
sudo vibe-vpn logs --config /etc/vibe-vpn/config.yaml
sudo vibe-vpn prune --config /etc/vibe-vpn/config.yaml --dry-run
sudo vibe-vpn rollback --config /etc/vibe-vpn/config.yaml
```

Safety summary:

```text
test: isolated temporary sing-box SOCKS on 127.0.0.1:18080 by default; explicit runtime: xray uses legacy temporary xray; no production changes
pick: runs isolated benchmark, then applies one winning node to the configured production runtime (sing-box by default)
apply: applies one saved result from /var/lib/vibe-vpn/last-results.json to configured runtime
rollback: restores newest backup from /var/lib/vibe-vpn/backups/ for configured runtime
```

Useful filters for `test`, `pick`, `list`, and `apply best`:

```bash
--include TEXT --exclude TEXT --transport tcp --security reality --min-mbps 10 --no-default-exclude
```

## Service modes

`service.mode` defaults to `fastest-rotation` in `/etc/vibe-vpn/config.yaml`.

Default fastest-rotation mode:

```yaml
service:
  enabled: true
  startup_test: true
  mode: fastest-rotation
```

- After each successful startup/scheduled test, the daemon may apply the fastest OK non-excluded node from fresh results.
- If the fastest node is already current, apply is skipped.
- If the scheduled test fails, old results may be preserved but fastest rotation does not apply from them.
- Health-triggered failover still exists.

Explicit failover-only opt-out:

```yaml
service:
  enabled: true
  startup_test: true
  mode: failover-only
```

- Startup and scheduled tests refresh `/var/lib/vibe-vpn/last-results.json` only.
- Production changes happen only after confirmed health failure triggers daemon failover.

## Config, state, service, and log paths

```text
/usr/local/bin/vibe-vpn                         # installed binary
/etc/systemd/system/vibe-vpn.service           # installed systemd unit
systemd/vibe-vpn.service                       # repo source unit
/etc/vibe-vpn/config.yaml                      # daemon config used by systemd examples
/etc/vibe-vpn/config.json                      # default CLI config path if --config is omitted
/etc/vibe-vpn/sub_url                          # root-only subscription URL(s), not in git
/etc/vibe-vpn/extra-nodes.json                 # optional root-only static nodes, not in git
/etc/vibe-vpn/lil-sweden-hy2-auth              # optional Hysteria auth secret, not in git
/var/lib/vibe-vpn/last-results.json            # latest benchmark results
/var/lib/vibe-vpn/current-node.json            # currently applied node metadata
/var/lib/vibe-vpn/current-link.txt             # currently applied VLESS link
/var/lib/vibe-vpn/backups/                     # configured runtime config backups
/var/log/vibe-vpn/vibe-vpn-YYYY-MM-DD-HH.log   # service log files
/etc/sing-box-vibe/tproxy-canary.json          # production sing-box config
sing-box-vibe-router                           # production sing-box systemd service
```

## Config examples

```bash
cp examples/vibe-vpn-config.yaml /tmp/vibe-vpn-config.yaml
cp examples/vibe-vpn-smoke-config.yaml /tmp/vibe-vpn-smoke-config.yaml
```

Important config keys:

```yaml
subscription_file: /etc/vibe-vpn/sub_url
extra_nodes_file: /etc/vibe-vpn/extra-nodes.json
runtime: singbox
sing_box_bin: /usr/bin/sing-box
sing_box_config: /etc/sing-box-vibe/tproxy-canary.json
sing_box_service: sing-box-vibe-router
# xray_bin/xray_config are only used for explicit runtime: xray legacy benchmarks/production.
state_dir: /var/lib/vibe-vpn
production_socks: 127.0.0.1:2080
test_socks: 127.0.0.1:18080
test_limit_kib: 512
timeout_seconds: 12
service:
  enabled: true
  startup_test: true
  mode: fastest-rotation
test:
  interval: 30m
health:
  normal_interval: 5s
  failure_retry_delays: [1s, 2s, 3s]
  probe_timeout: 5s
  required_urls:
    - https://x.com/
    - https://www.linkedin.com/
  diagnostic_urls:
    - https://ya.ru/
logging:
  path: /var/log/vibe-vpn/
  retention: 12h
  also_journal: true
```

Health behavior is strict for `required_urls`: all required URLs must pass, and any required URL failure enters progressive failover confirmation. `diagnostic_urls` are non-decisive; their failures (including current 3xx/non-OK probe results) do not trigger failover by themselves. Current `DefaultProbe`/`nettest.Get` treats only HTTP 2xx as OK, so redirects, TLS failures, and network/proxy errors are failures when configured as required URLs.

## Reference docs

- [`docs/FAILOVER_SERVICE_RUNBOOK.md`](./docs/FAILOVER_SERVICE_RUNBOOK.md)
- [`docs/VLESS_SUBSCRIPTION_PICKER.md`](./docs/VLESS_SUBSCRIPTION_PICKER.md)
- [`docs/STATIC_EXTRA_NODES.md`](./docs/STATIC_EXTRA_NODES.md)
- [`docs/ROLLBACK.md`](./docs/ROLLBACK.md)
- [`docs/ADD_CLIENT_RUNBOOK.md`](./docs/ADD_CLIENT_RUNBOOK.md)
- [`docs/TAILSCALE_CLIENT_SETUP.md`](./docs/TAILSCALE_CLIENT_SETUP.md)
- [`docs/IKEV2_CANARY_RUNBOOK.md`](./docs/IKEV2_CANARY_RUNBOOK.md)

## Secrets

Do not commit subscription URLs, full `vless://` links, tokens, private keys, generated mobile profiles, or VPS-specific secrets. Keep `/etc/vibe-vpn/sub_url` and `/etc/vibe-vpn/extra-nodes.json` mode `0600`.
