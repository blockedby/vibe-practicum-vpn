# vibe-practicum-vpn

Public-safe operational tooling for the containerized `vpnkit` VPN/routing setup and the `vibe-vpn` Go helper.

## Documentation

- Current Docker setup: [`docs/DOCKER_SETUP.md`](./docs/DOCKER_SETUP.md)
- Consolidated historical notes: [`docs/RESEARCH_AND_ATTEMPTS.md`](./docs/RESEARCH_AND_ATTEMPTS.md)
- Private endpoint template: [`config/private-endpoints.example.env`](./config/private-endpoints.example.env)
- Vercel DNS failover runbook: [`docs/VERCEL_DNS_FAILOVER.md`](./docs/VERCEL_DNS_FAILOVER.md)

Read-only backend drift check after sourcing local endpoints or passing SSH aliases:

```bash
scripts/vpnkit-backend-drift-check.sh <ssh-target> [<ssh-target> ...]
# or: VPNKIT_BACKEND_SSH_HOSTS="alias-a alias-b" scripts/vpnkit-backend-drift-check.sh
```

Throwaway Docker OpenVPN profile check:

```bash
scripts/vpnkit-profile-check.sh /path/to/client.ovpn
```


Local browser control panel for VPN diagnostics:

```bash
scripts/vpnkit-control-panel.py
# open http://127.0.0.1:8765/
```

The panel binds to localhost by default and exposes only fixed diagnostic
scripts with validated arguments. It can run the Docker profile checker and the
ASUS router slot cycle test from a prefilled local form. Do not bind it beyond
localhost unless you understand the risk.



Steam Deck one-adapter hotspot VPN gateway preparation:

```bash
# Read-only inventory/report
scripts/deck-hotspot-vpn-discover.sh --ssh-target deck

# First create a host-namespace OpenVPN client on the Deck so tun0 exists there.
# See steam-deck/hotspot-client/README.md for the git-pull-on-Deck workflow.

# Dry-run hotspot bring-up plan; no Deck mutation
scripts/deck-hotspot-vpn-up.sh --ssh-target deck --dry-run

# Apply only after reviewing discovery/dry-run and setting a hotspot password
DECK_HOTSPOT_PASSWORD='<local-wifi-password>' \
  scripts/deck-hotspot-vpn-up.sh --ssh-target deck --apply --yes

# Read-only Deck-side checks after bring-up
scripts/deck-hotspot-vpn-test.sh --ssh-target deck

# Idempotent cleanup of this tool's hotspot connection/firewall table
scripts/deck-hotspot-vpn-down.sh --ssh-target deck
```

The one-adapter Deck path is the primary target. USB Wi-Fi dongle mode is a
fallback only if the internal Wi-Fi cannot keep managed uplink plus AP stable.
The scripts write redacted reports under `reports/` by default and avoid printing
profiles, keys, private endpoints, or raw observed IPs.

Steam Deck host OpenVPN client packaging lives in:

```text
steam-deck/hotspot-client/
```

It includes `compose.yaml`, a Podman/OpenVPN `Containerfile`, local install/up/down/test scripts,
and a sanitized `.env.example`. It starts a separate `vpnkit-host-ovpn-client`
container and does not touch the existing `vpnkit` container.

Real private endpoints belong in gitignored `config/private-endpoints.local.env`, never in tracked docs or configs.

## Issue #24 manifest/profile matrix and smart routing

Public topology examples live in `config/vpnkit-manifest.example.yaml` and are validated against `config/vpnkit-manifest.schema.json`. The tracked example uses the logical pair `server=steamdeck` and `client=host-machine`; real endpoint values and certificate/key material must be supplied only through local environment bindings and must not be committed.

Install the public Python validation dependencies in your local/CI environment before running manifest-positive checks:

```bash
python3 -m pip install PyYAML jsonschema
```

Then run the public-safe fixture path:

```bash
python3 scripts/vpnkit-manifest-validate.py \
  --manifest config/vpnkit-manifest.example.yaml \
  --server steamdeck --client host-machine

scripts/vpnkit-render-profile-for-pair.sh \
  --manifest config/vpnkit-manifest.example.yaml \
  --server steamdeck --client host-machine \
  --out-dir generated/openvpn-profiles --fixture

VPNKIT_TEST_MANIFEST=config/vpnkit-manifest.example.yaml \
VPNKIT_TEST_MANIFEST_SERVER=steamdeck \
VPNKIT_TEST_MANIFEST_CLIENT=host-machine \
VPNKIT_TEST_MANIFEST_RENDER_MODE=fixture \
test/containers-test.sh
```

The fixture mode creates only public-safe dummy profile material under ignored `generated/openvpn-profiles/`. For real mode, source approved local bindings first and expect missing selected-pair prerequisites to be reported as clear `FAIL` diagnostics rather than modeled matrix `SKIP` rows. Do not run real Deck/production mutation without explicit operator approval.

Smart sing-box routing policy is defined by local rule sets under `config/sing-box/rule-sets/` and wired into both sing-box templates. Rule order is: DNS hijack/sniff, adblock -> `block-out`, developer/package infrastructure -> `direct-out`, RU geo/geosite -> `direct-out`, final -> `selected-native-out`. Local proof (not live production acceptance):

```bash
python3 test/sing-box-smart-routing-proof.py
```

## Local checks

```bash
go test ./...
go vet ./...
go build -o /tmp/vibe-vpn ./cmd/vibe-vpn
bash -n scripts/*.sh
```

See `docs/DOCKER_SETUP.md` for Docker lab verification and secret/rendered-config paths.

ASUS router OpenVPN client cycle test (operator-run only; mutates router VPN state):

```bash
# Prefer loading real SSH values from gitignored config/private-endpoints.local.env first.
ASUS_CONFIRM=YES scripts/openvpn-asus-client-cycle-test.sh \
  --host <asus-ssh-target> --port <ssh-port> --key <ssh-key> --slots 1,2,3,4
```

The script sequentially starts each requested ASUS OpenVPN client slot, checks
router-side ICMP/DNS/HTTPS/IP identity, stops the slot, and writes a redacted
report under `reports/` by default. It also traps exit/interrupt and stops all
tested slots to restore router connectivity. Run it only with an explicit
operator recovery path because it can temporarily break Internet access for this
computer.
