# vibe-practicum-vpn

Operational repo for the `vibe-practicum` VPS VPN/routing setup.

The current goal is simple: keep clients dumb via Tailscale exit-node, while the
VPS handles proxy fallback, VLESS upstream selection, and safe rollbacks.

Repository: <https://github.com/blockedby/vibe-practicum-vpn>

## What is here

- VPS routing notes and runbooks.
- Sanitized sing-box / TPROXY configs.
- Client setup docs for Tailscale.
- `vibe-vpn`: a Go CLI for choosing the best VLESS node from a subscription.

## `vibe-vpn` CLI

`vibe-vpn` is a single Go binary installed on the VPS. It benchmarks VLESS nodes
from a subscription using a temporary isolated `xray` process, then switches the
production `xray` only once at the end.

Safety property:

```text
vibe-vpn test/pick
-> starts temporary xray SOCKS on 127.0.0.1:18080
-> tests candidate VLESS nodes there
-> does NOT touch production xray :10808 during tests
-> pick applies only the winning node at the end
```

### Build locally

```bash
go test ./...
go vet ./...
go build -o vibe-vpn ./cmd/vibe-vpn
```

### Commands from my workstation (`kcnc-pc`)

Run these from the repo checkout on the local machine:

```bash
cd ~/code/tools/vibe-practicum-vpn
```

Build and deploy the binary to the VPS:

```bash
GOOS=linux GOARCH=amd64 go build -o /tmp/vibe-vpn ./cmd/vibe-vpn
scp /tmp/vibe-vpn vibe-practicum:/tmp/vibe-vpn
ssh vibe-practicum 'sudo install -o root -g root -m 755 /tmp/vibe-vpn /usr/local/bin/vibe-vpn'
```

Prepare the VPS config directory and copy an existing legacy subscription if present:

```bash
ssh vibe-practicum 'sudo mkdir -p /etc/vibe-vpn /var/lib/vibe-vpn && sudo chmod 700 /etc/vibe-vpn /var/lib/vibe-vpn'
ssh vibe-practicum 'if [ -f /etc/vibe-proxy/sub_url ] && [ ! -f /etc/vibe-vpn/sub_url ]; then sudo cp /etc/vibe-proxy/sub_url /etc/vibe-vpn/sub_url; sudo chmod 600 /etc/vibe-vpn/sub_url; fi'
```

Run safe checks over SSH:

```bash
ssh vibe-practicum 'sudo vibe-vpn status'
ssh vibe-practicum 'sudo vibe-vpn test --limit-kib 64 --max 2'
ssh vibe-practicum 'sudo vibe-vpn test --limit-kib 256'
ssh vibe-practicum 'sudo vibe-vpn list --top 20'
```

Pick and apply the best node automatically:

```bash
ssh vibe-practicum 'sudo vibe-vpn pick --limit-kib 256'
```

Or manually apply a specific node from the latest test results:

```bash
ssh vibe-practicum 'sudo vibe-vpn apply 6'
```

Rollback if the chosen node is bad:

```bash
ssh vibe-practicum 'sudo vibe-vpn rollback'
```

### Install on VPS manually

If already logged into the VPS, install a copied binary:

```bash
sudo install -o root -g root -m 755 /tmp/vibe-vpn /usr/local/bin/vibe-vpn
```

### VPS files

```text
/etc/vibe-vpn/sub_url                 # root-only subscription URL(s), one per line, not in git
/etc/vibe-vpn/extra-nodes.json        # optional root-only static nodes, not in git
/etc/vibe-vpn/lil-sweden-hy2-auth     # Hysteria auth secret, not in git
/etc/vibe-vpn/config.json             # optional config override
/var/lib/vibe-vpn/last-results.json   # latest benchmark results
/var/lib/vibe-vpn/current-node.json   # currently applied winner metadata
/var/lib/vibe-vpn/current-link.txt     # currently applied vless:// link
/var/lib/vibe-vpn/backups/            # xray config backups
/usr/local/etc/xray/config.json       # production xray config
```

### VPS commands and flags

```bash
sudo vibe-vpn status [--config /path/to/config.json]
```

Shows production `xray` status, production SOCKS address, current selected node, server `host:port`, transport/security, last benchmark speed, state source, live egress IP, and SOCKS latency.

```bash
sudo vibe-vpn test [--config /path/to/config.json] [--limit-kib N] [--duration-sec N] [--max N] [--verbose] [--debug]
```

Benchmarks subscription nodes safely. Does **not** apply anything. By default it is quiet: it suppresses temporary `xray` logs and prints a sorted top-20 summary at the end.

Useful examples:

```bash
sudo vibe-vpn test --limit-kib 64 --max 2    # quick smoke test
sudo vibe-vpn test --limit-kib 256           # full safer benchmark
sudo vibe-vpn test --limit-kib 1024 --max 20 # heavier partial benchmark
sudo vibe-vpn test --duration-sec 5 --max 20 # time-based benchmark
sudo vibe-vpn test --verbose              # print every node while testing
sudo vibe-vpn test --debug                # show temporary xray logs
```

```bash
sudo vibe-vpn list [--top N] [--all] [--failed] [--json]
```

Shows saved results from the last `test` or `pick`, sorted by speed.

```bash
sudo vibe-vpn apply <index>
```

Applies a specific OK node from `/var/lib/vibe-vpn/last-results.json`, for example `sudo vibe-vpn apply 6`.

```bash
sudo vibe-vpn pick [--config /path/to/config.json] [--limit-kib N] [--duration-sec N] [--max N]
```

Benchmarks safely, selects the fastest working node, backs up production xray
config, applies the winner, and restarts `xray` once.

Useful examples:

```bash
sudo vibe-vpn pick --limit-kib 256           # normal manual switch
sudo vibe-vpn pick --limit-kib 64 --max 10   # quick/emergency switch
```

```bash
sudo vibe-vpn rollback [--config /path/to/config.json]
```

Restores the newest xray config backup from `/var/lib/vibe-vpn/backups/`.

Flag notes:

- `--config`: optional config path. If explicitly provided, the file must exist.
- `--limit-kib`: how much data to download per node during size-based benchmark. Higher is more accurate but slower.
- `--duration-sec`: run a time-based benchmark for each node. `0` disables duration mode and returns to `--limit-kib` behavior.
- `--max`: test only the first N subscription/extra nodes after filters. Useful for smoke tests.
- `--verbose`: print every node as it is tested.
- `--debug`: show temporary xray stdout/stderr.
- `list --top N`: show N fastest successful nodes from the last run.
- `list --all`: show all successful nodes from the last run.
- `list --failed`: also print failed nodes and errors.
- `list --json`: dump raw saved results.
- `apply <index>`: apply a specific OK node from the last results.

See the full design and operational notes:

- [`docs/VLESS_SUBSCRIPTION_PICKER.md`](./docs/VLESS_SUBSCRIPTION_PICKER.md)
- [`docs/FAILOVER_SERVICE_RUNBOOK.md`](./docs/FAILOVER_SERVICE_RUNBOOK.md) — install/enable/status/logs/smoke/rollback runbook for the long-lived `vibe-vpn` failover service.

## IKEv2 canary workflow

The IKEv2 MVP is prepared as a safe canary package before any real strongSwan,
XFRM, or routing mutation. Start with the runbook and smoke checklist:

```bash
vibe-vpn --config /path/to/staging-config.json ikev2 smoke
```

Then follow [`docs/IKEV2_CANARY_RUNBOOK.md`](./docs/IKEV2_CANARY_RUNBOOK.md).
For the iPad-to-PC/Steam Deck tailnet bridge use-case, review
[`docs/IPAD_IKEV2_TAILNET_BRIDGE.md`](./docs/IPAD_IKEV2_TAILNET_BRIDGE.md) and
`vibe-vpn ikev2 routing bridge enable --dry-run` before any live change. Review
all `--dry-run` output before production changes, keep Tailscale as the rollback
path, and never commit generated profiles, private keys, subscription URLs,
VLESS links, or tokens.

## Traffic model

Current intended client path:

```text
client device
-> Tailscale exit-node
-> VPS tailscale0
-> sing-box TPROXY
-> xray SOCKS :10808
-> selected VLESS upstream
-> internet
```

## Useful docs

- [`docs/VLESS_SUBSCRIPTION_PICKER.md`](./docs/VLESS_SUBSCRIPTION_PICKER.md) — `vibe-vpn` CLI design and usage.
- [`docs/ADD_CLIENT_RUNBOOK.md`](./docs/ADD_CLIENT_RUNBOOK.md) — exact runbook for adding a new Tailscale client to VPS routing.
- [`docs/TAILSCALE_CLIENT_SETUP.md`](./docs/TAILSCALE_CLIENT_SETUP.md) — install/use Tailscale on Android, Windows, Kubuntu/Ubuntu.
- [`docs/IKEV2_MVP_DESIGN.md`](./docs/IKEV2_MVP_DESIGN.md) — native-client IKEv2 MVP design for the future Tailscale replacement path.
- [`docs/IKEV2_CANARY_RUNBOOK.md`](./docs/IKEV2_CANARY_RUNBOOK.md) — safe canary preparation workflow, dry-run gates, and mobile checks.
- [`docs/IKEV2_ROLLBACK.md`](./docs/IKEV2_ROLLBACK.md) — design-level rollback guidance for the future IKEv2 canary.
- [`docs/ASUS_OPENVPN_SITE_TO_SITE.md`](./docs/ASUS_OPENVPN_SITE_TO_SITE.md) — safe ASUS OpenVPN site-to-site runbook and scripts entry point.
- [`docs/PIXEL_ACCEPTANCE_CHECKLIST.md`](./docs/PIXEL_ACCEPTANCE_CHECKLIST.md) — current accepted canary checklist.
- [`docs/RU_DIRECT_RULESETS.md`](./docs/RU_DIRECT_RULESETS.md) — RU/direct rule-set notes.
- [`docs/LOCAL_SING_BOX_D1.md`](./docs/LOCAL_SING_BOX_D1.md) — smart local sing-box/TUN mode for `kcnc-pc` gaming split routing.
- [`docs/LIL_SWEDEN_GATEWAY.md`](./docs/LIL_SWEDEN_GATEWAY.md) — SSH/access, web, and Hysteria2 notes for the Sweden gateway.
- [`docs/issues/001-hysteria2-performance-followup.md`](./docs/issues/001-hysteria2-performance-followup.md) — deferred Hysteria2 performance tuning ideas.
- [`docs/STATIC_EXTRA_NODES.md`](./docs/STATIC_EXTRA_NODES.md) — `vibe-vpn` static/extra node file format.
- [`docs/ROLLBACK.md`](./docs/ROLLBACK.md) — rollback commands.

## Security notes

- Do not commit subscription URLs or full `vless://` secrets.
- Keep `/etc/vibe-vpn/sub_url` mode `0600`; it may contain multiple subscription URLs, one per line (`#` comments and empty lines are ignored).
- `vibe-vpn test` is safe for live usage; `vibe-vpn pick` changes production only after the winner is selected.

## vibe-vpn CLI

`vibe-vpn` now uses Cobra and provides command-specific help (`vibe-vpn <command> --help`). Production safety remains unchanged: `test` benchmarks nodes with a temporary isolated xray SOCKS listener and never changes production; `pick` runs the same isolated tests and applies only the fastest working non-excluded node; `rollback` restores the latest backup.

Common filters are available on `test`, `pick`, `list`, and `apply best`: `--include`, `--exclude`, `--transport`, `--security`, `--min-mbps`, `--default-exclude`, and `--no-default-exclude`. Explicit `apply <index>` is allowed for a working node from `last-results.json`; if current filters would exclude it, the CLI prints a warning before applying.

Useful commands:

- `vibe-vpn refresh` fetches the subscription and prints a node/transport summary.
- `vibe-vpn current` shows the current node; `vibe-vpn current --link` prints only the VLESS link.
- `vibe-vpn doctor` checks config, xray binary/config, state directory, subscription file, and test SOCKS availability.
- `vibe-vpn logs` prints recent xray/vibe-vpn journal summaries when journalctl is available.
- `vibe-vpn prune` removes stale temporary test files/processes and keeps recent backups.
