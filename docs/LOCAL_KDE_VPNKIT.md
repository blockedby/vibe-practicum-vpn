# Local KDE vpnkit: technical notes

The human setup guide is in the [main README](../README.md#local-vpn-for-cachyoskde). This document is for maintainers and acceptance work.

## Boundaries

- Compose project: `vpnkit-local`.
- OpenVPN is published only on `127.0.0.1` (UDP port `21194` by default).
- Private state lives under ignored `secrets/vpnkit-local/`.
- The owned NetworkManager connection is exactly `vpnkit-local`.
- Production containers, profiles, endpoints, and an existing work VPN are outside this flow.
- Full-tunnel mode is sing-box TUN; IPv6 is fail-closed.

The installer validates ownership, modes, links, canonical paths, Compose ownership, and bounded environment values before mutation. It imports the KDE profile but never activates it automatically.

## Same-host routing

The root helper keeps Docker upstream traffic on the physical uplink and prevents recursion through the local OpenVPN tunnel. It owns four policy-rule priorities:

1. `998`: local Docker destination lookup through `main` with the default route suppressed;
2. `999`: fail closed if the Docker bridge route is absent;
3. `1000`: source-underlay lookup;
4. `1001`: source-underlay fail-closed rule.

Review or verify it with:

```bash
scripts/vpnkit/vpnkit-local-underlay-routing.sh plan
scripts/vpnkit/vpnkit-local-underlay-routing.sh verify
```

Install and uninstall require explicit root confirmation:

```bash
sudo scripts/vpnkit/vpnkit-local-underlay-routing.sh install --yes
sudo scripts/vpnkit/vpnkit-local-underlay-routing.sh uninstall --yes
```

## Lifecycle safety

`start`, `stop`, `retest`, and mode toggles share a private lifecycle lock. Mutations use a durable journal and exact pre/post-state verification. Interrupted operations compensate to the previous state; a committed operation is preserved only when its recorded post-state can be verified. Unverifiable recovery state blocks later mutation instead of guessing.

The local DNS path uses Cloudflare DoH as primary and Google DoH as fallback. The DNS pushed to OpenVPN clients remains Google (`8.8.8.8`, with bounded `8.8.4.4` fallback) per repository policy.

## Safe acceptance

Isolated Docker full-tunnel cycle (no NetworkManager or host routing mutation):

```bash
test/containers-test.sh --scenario local-docker --action cycle
```

Focused local checks:

```bash
python3 -m unittest test.test_vpnkit_local_kde_tui
test/vpnkit-local-install-test.sh
test/vpnkit-local-lifecycle-transaction-test.sh
test/vpnkit-local-host-smoke-test.sh
test/vpnkit-local-underlay-routing-container-test.sh
```

Live KDE acceptance is intentionally opt-in. It requires the local stack and `vpnkit-local` profile to be inactive because it snapshots, starts, verifies, and restores them:

```bash
test/containers-test.sh \
  --scenario local-kde-host \
  --action accept \
  --approve-local-kde-host
```

It verifies exact UUID-to-IPv4-to-`tun*` mapping, OpenVPN readiness, routing rules, DNS, hostname and literal-IP HTTPS, ICMP, IPv6 fail-closed behavior, work-VPN invariance, and cleanup.
