# VLESS subscription picker

Goal: make `update from subscription -> test nodes -> pick best -> apply to xray` repeatable and safe.

## Go CLI

The current implementation is `cmd/vibe-vpn`.

```bash
go test ./...
go build -o vibe-vpn ./cmd/vibe-vpn
```

Default state/config paths:

```text
/etc/vibe-vpn/config.json       # optional CLI config
/etc/vibe-vpn/sub_url           # root-only subscription URL(s), one per line
/etc/vibe-vpn/extra-nodes.json  # optional root-only static nodes
/var/lib/vibe-vpn/last-results.json
/var/lib/vibe-vpn/current-node.json
/var/lib/vibe-vpn/current-link.txt
/var/lib/vibe-vpn/backups/      # xray config backups for rollback
/usr/local/etc/xray/config.json # production xray config
```

`sub_url` can contain either the legacy single subscription URL or several URLs, one per line. Empty lines and lines starting with `#` are ignored; fetched VLESS links are concatenated before filtering/testing.

Example optional config (`/etc/vibe-vpn/config.json`):

```json
{
  "subscription_file": "/etc/vibe-vpn/sub_url",
  "xray_bin": "/usr/local/bin/xray",
  "xray_config": "/usr/local/etc/xray/config.json",
  "state_dir": "/var/lib/vibe-vpn",
  "production_socks": "127.0.0.1:10808",
  "test_socks": "127.0.0.1:18080",
  "test_url": "https://speed.cloudflare.com/__down?bytes=75000000",
  "test_limit_kib": 512,
  "test_duration_seconds": 5,
  "timeout_seconds": 20
}
```

Dry run: starts a temporary xray SOCKS listener on `test_socks` for each node.
Production xray and `production_socks` are not touched.

```bash
sudo vibe-vpn test --duration-sec 5 --max 10
```

Pick and apply: benchmarks in isolation, then writes only the winning outbound to
production xray.

```bash
sudo vibe-vpn pick --duration-sec 5
```

Rollback to the newest saved config backup:

```bash
sudo vibe-vpn rollback
```

Safety notes:

- `test` never rewrites or restarts production xray.
- `test_socks` must be a free local address; the CLI refuses to benchmark if it
  is already occupied, so stale listeners cannot skew results.
- `pick` saves a backup before changing production config and preserves the
  existing first outbound tag for routing-rule compatibility.
- If `systemctl restart xray` fails after applying the winner, the CLI restores
  the previous config and restarts xray again.
- `rollback` uses backups from `/var/lib/vibe-vpn/backups/`.

## Legacy helper

`scripts/vibe-pick-proxy-isolated.py` is retained as a legacy standalone helper.
Prefer the Go CLI for new runs.

## Updated CLI workflow

The picker CLI is Cobra-based. Run `vibe-vpn --help` or `vibe-vpn test --help` for authoritative options.

Shared filters apply consistently to `test`, `pick`, `list`, and `apply best`:

```bash
vibe-vpn test --transport tcp --security reality --min-mbps 10
vibe-vpn list --exclude hongkong --failed
vibe-vpn apply best --include germany --no-default-exclude
```

`test` uses an isolated temporary xray instance and leaves production untouched. `pick` only applies after tests complete and chooses the best working non-excluded node. `apply <index>` applies an explicit tested result and warns if the current filter set excludes that index. Use `vibe-vpn current --link` to retrieve the currently applied VLESS link.
