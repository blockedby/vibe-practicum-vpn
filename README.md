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

## Steam Deck test-lab lifecycle runner

Issue #27 adds an isolated public-safe Steam Deck lab scenario. Load private Deck bindings locally when available, without printing them:

```bash
test -r config/private-endpoints.local.env && set -a && . config/private-endpoints.local.env && set +a

test/containers-test.sh --scenario steamdeck-host --action cycle
# or individual lifecycle phases:
test/containers-test.sh --scenario steamdeck-host --action up
test/containers-test.sh --scenario steamdeck-host --action test
test/containers-test.sh --scenario steamdeck-host --action down
```

Defaults are intentionally distinct from production: container `vpnkit-test-steamdeck-host`, image `localhost/vpnkit:test-steamdeck-host`, remote state `~/.local/state/vpnkit-labs/steamdeck-host`, and host UDP `21194 -> 1194/udp`. `down` refuses the default/prod `vpnkit` container and only removes the isolated lab container unless `VPNKIT_TEST_LAB_REMOVE_REMOTE_STATE=1` is explicitly set for the isolated remote lab directory.

Generated lab PKI, rendered configs, and client profiles live under the gitignored layout `secrets/vpnkit-labs/steamdeck-host/` (for example `rendered/`, `openvpn/pki/`, and `openvpn/client/test-client.ovpn`). Tracked templates and rule sets remain public-safe; never commit `.ovpn`, PEM/key/cert, rendered private configs, or logs. Lab setup defaults `VPNKIT_RULESET_SOURCE_MODE=local-fixture`, which renders minimal local source JSON fixtures for the RU rule-set tags under `rendered/sing-box/rule-sets/` so the isolated lab does not depend on GitHub `.srs` downloads at startup. It also defaults `VPNKIT_SELECTED_OUTBOUND_MODE=direct-fixture` so the lab keeps the `selected-native-out` final/tag policy shape without requiring a real VLESS proxy, and `VPNKIT_OPENVPN_PUSH_DNS=172.19.0.1` so pushed client DNS enters sing-box TUN instead of the server's local OpenVPN `tun0` address. Normal renderer defaults remain remote binary RU rule sets, proxy/VLESS selected outbound, and OpenVPN DNS `10.89.0.1` unless explicitly overridden.

Nested OpenVPN acceptance is part of the same `steamdeck-host` lifecycle, not a separate scenario. Lab setup also creates throwaway nested server/client material under `secrets/vpnkit-labs/steamdeck-host/nested/openvpn/`; `test`/`cycle` require the client smoke to prove the pre-nested route to the nested target uses outer `tun0`, nested OpenVPN handshakes, `tun1` exists, and the nested tunnel peer pings. `VPNKIT_STEAMDECK_NESTED_VPN_ENABLED=0` is only a diagnostic escape hatch and makes the run not deploy-ready.

Useful overrides:

```bash
VPNKIT_TEST_SSH_TARGET=<local-deck-ssh-alias> \
VPNKIT_TEST_ENDPOINT=<deck-lan-or-approved-test-endpoint> \
VPNKIT_OPENVPN_PORT=21194 \
VPNKIT_TEST_ROUTING_MODE=tun \
  test/containers-test.sh --scenario steamdeck-host --action cycle
```

For explicit `steamdeck-host`, SSH target precedence is `VPNKIT_TEST_SSH_TARGET`, then `VPNKIT_STEAMDECK_SSH_TARGET`, then `VPNKIT_STEAMDECK_SSH_HOST`, then `deck`. Endpoint precedence is `VPNKIT_TEST_ENDPOINT`, then `VPNKIT_STEAMDECK_LAN_ENDPOINT`. Documented example placeholders (`your-*`, `*.invalid`, `192.0.2.*`, `203.0.113.*`) are treated as missing prerequisites and reported as `FAIL` diagnostics rather than green acceptance.

Timeouts are bounded and configurable for slow Deck operations: `VPNKIT_TEST_SSH_TIMEOUT`, `VPNKIT_TEST_REMOTE_CMD_TIMEOUT`, `VPNKIT_TEST_DEPLOY_TIMEOUT`, `VPNKIT_TEST_CLIENT_TIMEOUT`, plus helper-level `VPNKIT_STEAMDECK_BUILD_TIMEOUT`, `VPNKIT_STEAMDECK_RUN_TIMEOUT`, `VPNKIT_STEAMDECK_LOGS_TIMEOUT`, and `VPNKIT_STEAMDECK_VERIFY_TIMEOUT`.

## Issue #24 manifest/profile matrix and smart routing

Public topology examples live in `config/vpnkit-manifest.example.yaml` and are validated against `config/vpnkit-manifest.schema.json`. The tracked example uses the logical pair `server=steamdeck` and `client=host-machine` with separate `test` and `production` profile intents. The Steam Deck server host is a test/lab target, not production: Deck test runs do not require the production approval gate, but they still remain public-safe, Podman-only on the Deck, and bounded by explicit live-action approval. Real endpoint values and certificate/key material must be supplied only through local environment bindings and must not be committed.

Install the public Python validation dependencies in your local/CI environment before running manifest-positive checks:

```bash
python3 -m pip install PyYAML jsonschema
```

Then run the public-safe fixture path:

```bash
python3 scripts/vpnkit-manifest-validate.py \
  --manifest config/vpnkit-manifest.example.yaml \
  --server steamdeck --client host-machine \
  --profile-intent test

python3 scripts/vpnkit-manifest-validate.py \
  --manifest config/vpnkit-manifest.example.yaml \
  --server steamdeck --client host-machine \
  --profile-intent production

scripts/vpnkit-render-profile-for-pair.sh \
  --manifest config/vpnkit-manifest.example.yaml \
  --server steamdeck --client host-machine \
  --profile-intent test \
  --out-dir generated/openvpn-profiles --fixture

VPNKIT_TEST_MANIFEST=config/vpnkit-manifest.example.yaml \
VPNKIT_TEST_MANIFEST_SERVER=steamdeck \
VPNKIT_TEST_MANIFEST_CLIENT=host-machine \
VPNKIT_TEST_MANIFEST_RENDER_MODE=fixture \
test/containers-test.sh
```

The fixture mode creates only public-safe dummy profile material under ignored `generated/openvpn-profiles/`. Selected manifest-pair harness runs default to `VPNKIT_TEST_MANIFEST_PROFILE_INTENT=test`; set `VPNKIT_TEST_MANIFEST_PROFILE_INTENT=production` only for an explicit production-profile check. For real mode, source approved local bindings first and expect missing selected-pair prerequisites to be reported as clear `FAIL` diagnostics rather than modeled matrix `SKIP` rows. Do not run real Deck live mutation without an explicit Deck test action, and do not run production mutation without explicit operator approval.

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

## Production Docker deploy/rollback helper (tooling only)

Production mutation still requires explicit operator approval and real endpoint
bindings from the gitignored `config/private-endpoints.local.env`. The tracked
helper is safe to review locally first and does not embed production hosts or
paths:

```bash
# Plan only; no remote mutation.
scripts/vpnkit-prod-deploy.sh plan --target-ref origin/main your-prod-ssh-alias
# Equivalent alias.
scripts/vpnkit-prod-deploy.sh dry-run --target-ref origin/main your-prod-ssh-alias

# After explicit approval only; mutating commands refuse without --yes.
scripts/vpnkit-prod-deploy.sh deploy --yes --target-ref <commit-or-branch> \
  your-prod-ssh-alias-a your-prod-ssh-alias-b
scripts/vpnkit-prod-deploy.sh rollback --yes your-prod-ssh-alias-a your-prod-ssh-alias-b
scripts/vpnkit-prod-deploy.sh verify your-prod-ssh-alias-a your-prod-ssh-alias-b
```

The helper discovers the live Compose workdir/service/container from Docker
Compose labels. Approved overrides for unusual hosts are
`VPNKIT_PROD_WORKDIR`, `VPNKIT_PROD_SERVICE`, `VPNKIT_PROD_CONTAINER`, and
`VPNKIT_PROD_PROJECT`; keep their real values local-only. Deploy is sequential
across hosts and stops on the first failed host after attempting rollback. The
remote flow is: create `.rollback/vpnkit/<timestamp>/`, fetch/checkout the target
ref, render/check and refresh persisted sing-box config, rebuild/recreate only
the `vpnkit` service, smoke the runtime, auto-rollback on failed smoke, and smoke
after rollback. Smoke checks are bounded and cover container state, UDP 1194,
OpenVPN/`tun0`, sing-box, `sb-tun0` policy routing for `tun` mode, and
`sing-box check` when available. Output is redacted; do not paste raw secret
files, rendered configs, profiles, logs, image exports, or private endpoint
values into tracked docs.
