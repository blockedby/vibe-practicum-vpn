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
```

Pick and apply the best node:

```bash
ssh vibe-practicum 'sudo vibe-vpn pick --limit-kib 256'
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
/etc/vibe-vpn/sub_url                 # root-only subscription URL, not in git
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

Shows production `xray` status, current node if known, and a SOCKS smoke check.

```bash
sudo vibe-vpn test [--config /path/to/config.json] [--limit-kib N] [--max N]
```

Benchmarks subscription nodes safely. Does **not** apply anything.

Useful examples:

```bash
sudo vibe-vpn test --limit-kib 64 --max 2    # quick smoke test
sudo vibe-vpn test --limit-kib 256           # full safer benchmark
sudo vibe-vpn test --limit-kib 1024 --max 20 # heavier partial benchmark
```

```bash
sudo vibe-vpn pick [--config /path/to/config.json] [--limit-kib N] [--max N]
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
- `--limit-kib`: how much data to download per node during benchmark. Higher is more accurate but slower.
- `--max`: test only the first N subscription nodes. Useful for smoke tests.

See the full design and operational notes:

- [`docs/VLESS_SUBSCRIPTION_PICKER.md`](./docs/VLESS_SUBSCRIPTION_PICKER.md)

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
- [`docs/PIXEL_ACCEPTANCE_CHECKLIST.md`](./docs/PIXEL_ACCEPTANCE_CHECKLIST.md) — current accepted canary checklist.
- [`docs/RU_DIRECT_RULESETS.md`](./docs/RU_DIRECT_RULESETS.md) — RU/direct rule-set notes.
- [`docs/LOCAL_SING_BOX_D1.md`](./docs/LOCAL_SING_BOX_D1.md) — smart local sing-box/TUN mode for `kcnc-pc` gaming split routing.
- [`docs/ROLLBACK.md`](./docs/ROLLBACK.md) — rollback commands.

## Security notes

- Do not commit subscription URLs or full `vless://` secrets.
- Keep `/etc/vibe-vpn/sub_url` mode `0600`.
- `vibe-vpn test` is safe for live usage; `vibe-vpn pick` changes production only after the winner is selected.
