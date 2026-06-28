# Steam Deck singnox hotspot client

Reusable Steam Deck package for a Hysteria2 client rendered into native
`sing-box` TUN mode, then shared through the Deck hotspot helper scripts.
The directory name intentionally keeps the requested spelling:
`steam-deck/singnox-hotspot-client`.

This package is public-safe. Tracked files contain only placeholders and empty
rule-set templates. Real Hysteria2 YAML/URI files, generated sing-box configs,
logs, reports, and `.env` values stay under ignored local paths.

## Files

```text
steam-deck/singnox-hotspot-client/
  README.md
  .env.example
  config/sing-box/config.tun.json.template
  config/sing-box/rule-sets/*.json
  scripts/lib.sh
  scripts/install-sing-box.sh
  scripts/render-sing-box-config.sh
  scripts/hotspot-up.sh
  scripts/hotspot-test.sh
  scripts/hotspot-status.sh
  scripts/hotspot-down.sh
```

The scripts reuse the repo-level Deck helpers instead of reimplementing hotspot
mutation logic:

- `scripts/deck/deck-hy2-hotspot.sh`
- `scripts/deck/deck-hotspot-vpn-up.sh`
- `scripts/deck/deck-hotspot-vpn-test.sh`
- `scripts/deck/deck-hotspot-vpn-down.sh`

## Public-safety rules

Do not commit or paste:

- real Hysteria2 YAML or URI values;
- real endpoints, auth strings, obfs passwords, tokens, or private hostnames;
- generated `config.json` files;
- `.env` files;
- runtime logs/reports from a real Deck.

Use only these ignored locations for operator-local material:

```text
steam-deck/singnox-hotspot-client/.env
steam-deck/singnox-hotspot-client/local/
steam-deck/singnox-hotspot-client/secrets/
steam-deck/singnox-hotspot-client/runtime/
steam-deck/singnox-hotspot-client/logs/
steam-deck/singnox-hotspot-client/reports/
steam-deck/singnox-hotspot-client/generated/
```

## One-time setup

From a full checkout:

```bash
cd steam-deck/singnox-hotspot-client
cp .env.example .env
mkdir -p local
```

Place exactly one real Hysteria2 client source in the ignored `local/` directory,
for example:

```text
local/hysteria2-client.yaml
# or
local/hysteria2-client.uri
```

Edit `.env` so `SINGNOX_HY2_CLIENT_CONFIG` points at that local file. Put the
hotspot WPA password only in `.env` or in the shell environment.

## Install native sing-box on the Deck

The runtime expects native sing-box on the Deck, normally at:

```text
/home/deck/.local/bin/sing-box
```

If it is already installed, verify it:

```bash
./scripts/install-sing-box.sh
```

To install from an operator-provided local binary or release archive, place it
under ignored `local/` and set one of these in `.env`:

```bash
SINGNOX_SINGBOX_SOURCE_BIN=local/sing-box
# or
SINGNOX_SINGBOX_SOURCE_ARCHIVE=local/sing-box-linux-amd64.tar.gz
```

Then run:

```bash
./scripts/install-sing-box.sh
```

The installer intentionally does not download binaries by default.

## Generate sing-box config from Hysteria2 YAML/URI

Render the package-local template into an ignored runtime config:

```bash
./scripts/render-sing-box-config.sh
```

Expected output path:

```text
runtime/sing-box/config.json
```

That file contains real client auth material and must remain ignored. If the
configured sing-box binary exists, the render script also runs `sing-box check`.

## Start hotspot through sing-box

From this package directory, with `.env` filled and SSH access to the Deck:

```bash
./scripts/hotspot-up.sh
```

`hotspot-up.sh` renders the config, exports the matching `DECK_HY2_*` and
`DECK_HOTSPOT_*` variables, then delegates to `scripts/deck/deck-hy2-hotspot.sh
up`. The repo helper starts native sing-box on the Deck, starts the hotspot via
the existing hotspot up helper, and installs the hotspot policy route.

## Test

Deck-side gateway checks are read-only:

```bash
./scripts/hotspot-test.sh
```

The generated report also prints client-side commands to run from a device that
is connected to the Deck hotspot.

For a quick read-only status snapshot:

```bash
./scripts/hotspot-status.sh
```

## Stop / rollback

Stop only this package's hotspot/sing-box runtime names:

```bash
./scripts/hotspot-down.sh
```

The down path delegates to the existing repo helper and is intended to be
idempotent. It does not mutate unrelated production `vpnkit` containers.

## Notes

- Static validation for this package is `bash -n scripts/*.sh` plus a secret scan
  of tracked package files.
- Hotspot IPv6 is blocked by default; set `DECK_HOTSPOT_IPV6_POLICY=allow` only
  if you explicitly need IPv6 on the Deck hotspot path.
- Live Deck mutation is intentionally not part of static validation.
- Keep generated configs, local secrets, logs, and reports out of git.
