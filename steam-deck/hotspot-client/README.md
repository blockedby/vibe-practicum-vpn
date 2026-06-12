# Steam Deck host OpenVPN client

This folder packages a **separate** Steam Deck host-network OpenVPN client runtime
for the one-adapter hotspot gateway plan.

It is intentionally separate from the existing `vpnkit` container. The default
container name is:

```text
vpnkit-host-ovpn-client
```

The runtime uses:

- Podman on Steam Deck;
- host network namespace;
- `NET_ADMIN` and `NET_RAW` capabilities;
- `/dev/net/tun` from the Deck host;
- an operator-provided, gitignored OpenVPN client profile.

The goal is to create `tun0` on the **Steam Deck host**, so the hotspot gateway
scripts can later route/NAT hotspot clients through that interface.

## Public-safety rules

Do not commit or paste:

- real `.ovpn` profiles;
- private keys;
- rendered configs;
- logs with private endpoints;
- real private endpoint values.

The real client profile should live only on the Deck, for example:

```text
steam-deck/hotspot-client/local/client.ovpn
```

That path is ignored by git.

## Files

```text
steam-deck/hotspot-client/
  compose.yaml                 # declarative Podman/Docker Compose runtime
  Containerfile                 # OpenVPN client image
  .env.example                  # sanitized local config template
  scripts/install.sh            # build/prep, optional --start
  scripts/up.sh                 # start host-network client container
  scripts/down.sh               # remove only this tool's client container
  scripts/test.sh               # Deck-side route/DNS/HTTPS/IP checks
  scripts/container-entrypoint.sh
  scripts/lib.sh
```

## Operator workflow on Steam Deck

From the Steam Deck:

```bash
cd /path/to/vibe-practicum-vpn
git fetch origin
git switch feat/steam-deck-hotspot-client
git pull --ff-only

cd steam-deck/hotspot-client
cp .env.example .env
mkdir -p local
# Copy your real OpenVPN client profile to this gitignored path:
#   local/client.ovpn
chmod 600 local/client.ovpn

./scripts/install.sh
./scripts/up.sh
./scripts/test.sh
```

If rootless Podman cannot create the host `tun0`, use sudo Podman explicitly:

```bash
VPNKIT_DECK_PODMAN="sudo podman" ./scripts/install.sh
VPNKIT_DECK_PODMAN="sudo podman" ./scripts/up.sh
VPNKIT_DECK_PODMAN="sudo podman" ./scripts/test.sh
```

Rollback:

```bash
./scripts/down.sh
# or, if sudo Podman was used:
VPNKIT_DECK_PODMAN="sudo podman" ./scripts/down.sh
```

## Expected success evidence

After `up.sh`:

```bash
ip -4 addr show tun0
ip -4 route get 1.1.1.1
```

After `test.sh`, expected public-safe signals include:

```text
vpn_iface=present
route_checks_start
icmp_checks_start
dns_checks_start
ip_ifconfig_me=ok hash=<hash>
ip_api_ipify=ok hash=<hash>
access_x_com=ok
access_ya_ru=ok
access_linkedin_com=ok
```

The scripts write durable redacted logs from the start under:

```text
steam-deck/hotspot-client/reports/
steam-deck/hotspot-client/logs/
```

These directories are ignored by git.

## Compose usage

`compose.yaml` is included for inspection and operators who already have
`podman compose` or `podman-compose` available. The shell scripts use direct
Podman commands by default because SteamOS installations do not always include a
Compose frontend.

Equivalent compose-style runtime properties are still captured in
`compose.yaml`: host network, `NET_ADMIN`, `NET_RAW`, `/dev/net/tun`, profile
mount, log mount, and separate container name.

## Next step after this works

Once `tun0` exists on the Deck host and `./scripts/test.sh` passes, continue with
the hotspot gateway scripts from the repo root:

```bash
scripts/deck/deck-hotspot-vpn-up.sh --ssh-target deck --dry-run
```

Then review the dry-run report before using `--apply`.
