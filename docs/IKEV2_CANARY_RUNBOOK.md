# IKEv2 canary runbook

This runbook prepares a safe IKEv2/IPsec canary for the MVP described in [`IKEV2_MVP_DESIGN.md`](./IKEV2_MVP_DESIGN.md). It is intentionally conservative: **no real mutation is allowed until every dry-run output has been reviewed and explicitly approved**.

## Safety rules

- Start with one iOS/mobile canary only.
- Keep Tailscale enabled and reachable for operator access and rollback.
- Do not change the VPS default route.
- Do not run non-dry-run `server install`, `xfrm install`, `xfrm disable`, `routing enable`, or `routing disable`; those real mutations are not implemented for this slice.
- Do not paste or commit private keys, PSKs, generated `.mobileconfig` files containing credentials, VLESS links, subscription URLs, tokens, or device-identifying private material.
- Treat `/etc/vibe-vpn/ikev2`, `/var/lib/vibe-vpn/ikev2`, rendered client profiles, and backups as sensitive operational state.

## Prerequisites

1. Build and deploy the current `vibe-vpn` binary using the normal README process.
2. Confirm the existing production path is healthy:

   ```bash
   sudo vibe-vpn status
   systemctl is-active tailscaled || true
   ip -brief addr show tailscale0 || true
   systemctl is-active sing-box-vibe-router || true
   systemctl is-active xray || true
   ```

3. Confirm strongSwan/swanctl planning inputs are known before real rollout review:
   - public server name or address for IKEv2;
   - underlay interface name for XFRM creation;
   - canary client name and planned VPN IP inside `10.88.0.0/24` (not `10.88.0.1`).

## Staging paths

Use temporary/staging paths first. Example config file for local planning only:

```json
{
  "ikev2": {
    "server_name": "vpn.example.test",
    "config_dir": "/tmp/vibe-vpn-ikev2/etc",
    "state_dir": "/tmp/vibe-vpn-ikev2/state",
    "swanctl_dir": "/tmp/vibe-vpn-ikev2/swanctl",
    "underlay_interface": "ens3"
  }
}
```

Production defaults are expected to be root-only paths such as `/etc/vibe-vpn/ikev2` and `/var/lib/vibe-vpn/ikev2`; do not copy staged secrets into git.

## Smoke plan

Print the read-only checklist that should be reviewed before touching the VPS:

```bash
vibe-vpn --config /tmp/ikev2-canary.json ikev2 smoke
```

Expected output includes `NO REAL MUTATION`, status/doctor checks, client audit/render steps, `server install --dry-run`, `xfrm install --dry-run`, and `routing enable --dry-run`.

## PKI/state initialization

Initialize only the configured staging/config/state directories. This command creates directories and placeholder files; it does not print private material.

```bash
vibe-vpn --config /tmp/ikev2-canary.json ikev2 pki init
```

Expected output:

```text
initialized ikev2 pki/state directories
config_dir: ...
state_dir: ...
secret_material: not printed
```

Safety gate: verify directories are mode `0700` and placeholder/client registry files are mode `0600`.

## Client create/list/audit/render

Create one mobile canary entry with a non-gateway address:

```bash
vibe-vpn --config /tmp/ikev2-canary.json ikev2 client create ios-canary --ip 10.88.0.2 --os ios
vibe-vpn --config /tmp/ikev2-canary.json ikev2 client list
vibe-vpn --config /tmp/ikev2-canary.json ikev2 client audit ios-canary
```

Render a placeholder iOS profile to staging:

```bash
mkdir -p /tmp/vibe-vpn-ikev2/profiles
vibe-vpn --config /tmp/ikev2-canary.json ikev2 client render ios-canary --output-dir /tmp/vibe-vpn-ikev2/profiles --format ios
```

Safety gates:

- Output must include `secret_material: not printed`.
- Rendered profiles in this MVP are previews/placeholders only and must not contain real private keys.
- If a future real mobile profile embeds credentials or private keys, transfer it only through an approved secure channel and delete staging copies after installation.

## Server render/install dry-run

Render deterministic strongSwan config to staging:

```bash
mkdir -p /tmp/vibe-vpn-ikev2/rendered-server
vibe-vpn --config /tmp/ikev2-canary.json ikev2 server render --output-dir /tmp/vibe-vpn-ikev2/rendered-server
```

Review generated `swanctl.conf` for server name, pool `10.88.0.0/24`, gateway `10.88.0.1`, `ipsec0`, and only the intended canary client.

Then run install planning only:

```bash
vibe-vpn --config /tmp/ikev2-canary.json ikev2 server install --dry-run --output-dir /tmp/vibe-vpn-ikev2/staged-install
```

Safety gate: every line must say `dry-run`; no files under real `/etc/swanctl` should be changed by this command.

## XFRM status/install dry-run

```bash
vibe-vpn --config /tmp/ikev2-canary.json ikev2 xfrm status
vibe-vpn --config /tmp/ikev2-canary.json ikev2 xfrm install --dry-run
```

Expected plan includes `ipsec0`, if_id `42`, gateway `10.88.0.1/24`, and the configured underlay interface. If the underlay is missing, stop and fix config before any real rollout.

## Routing status/enable dry-run

```bash
vibe-vpn --config /tmp/ikev2-canary.json ikev2 routing status
vibe-vpn --config /tmp/ikev2-canary.json ikev2 routing enable --dry-run
```

Expected plan:

- creates only `VIBE_ROUTER_IKEV2`;
- hooks only `PREROUTING -i ipsec0 -s 10.88.0.0/24`;
- bypasses VPN/private/local ranges, including `10.88.0.0/24` and the configured tailnet subnet `100.64.0.0/10`;
- TPROXYs eligible TCP/UDP to port `2082` with mark/table from config;
- does not mention `tailscale0` interface changes or default route changes.

## iPad to tailnet bridge dry-run

For the relocation/iPad use-case, review the dedicated bridge plan after the base routing plan:

```bash
vibe-vpn --config /tmp/ikev2-canary.json ikev2 routing bridge status
vibe-vpn --config /tmp/ikev2-canary.json ikev2 routing bridge enable --dry-run
```

Expected bridge plan:

- allows only `ipsec0 -> tailscale0` traffic with source `10.88.0.0/24` and destination `100.64.0.0/10`;
- allows only `ESTABLISHED,RELATED` return traffic from `tailscale0 -> ipsec0`;
- adds MASQUERADE only for `10.88.0.0/24 -> 100.64.0.0/10` out `tailscale0`;
- adds comment-scoped private bypass rules to `VIBE_ROUTER_IKEV2` only when that chain exists;
- uses `vibe-vpn-ikev2-tailnet-bridge:*` comments for exact rollback;
- does not change default routes, flush firewall chains, or restart services.

See [`IPAD_IKEV2_TAILNET_BRIDGE.md`](./IPAD_IKEV2_TAILNET_BRIDGE.md) for iPad profile/user acceptance steps and target addresses.

## Manual iOS/mobile canary prep

Before connecting a real device:

1. Confirm the server certificate identity matches the mobile IKEv2 remote identifier.
2. Install CA/server trust and the canary client certificate/profile using a secure channel.
3. Keep Tailscale available on the device for comparison and emergency access, but do not test both tunnels simultaneously unless explicitly planned.
4. On the device, verify:
   - VPN connects and stays connected;
   - assigned/expected VPN address is `10.88.0.2` or the planned canary IP;
   - public IP checks match the selected VLESS/proxy path when expected;
   - private/VPN destinations bypass xray/VLESS;
   - DNS/UDP apps, browser, Telegram/YouTube, and the existing Pixel checklist style app checks still work;
   - battery/network UX is acceptable after reconnect, Wi-Fi/mobile transition, and sleep/wake.

## Rollback / disabling planned pieces

For this slice, use dry-run disable plans first:

```bash
vibe-vpn --config /tmp/ikev2-canary.json ikev2 routing disable --dry-run
vibe-vpn --config /tmp/ikev2-canary.json ikev2 xfrm disable --dry-run
```

If real rollout commands are later approved, rollback must remove only IKEv2-specific pieces: the dedicated routing chain/hook/table rule, active IKEv2 SAs, `ipsec0`, and staged swanctl changes. Follow [`IKEV2_ROLLBACK.md`](./IKEV2_ROLLBACK.md). Never flush broad iptables chains, delete default routes, stop Tailscale, or alter the selected VLESS upstream as part of IKEv2 rollback.

## Final go/no-go gates

Go only if:

- `ikev2 doctor` is OK;
- all plans are reviewed and scoped to IKEv2 only;
- no command output contains secrets;
- Tailscale and `vibe-vpn status` are healthy before and after dry-runs;
- rollback commands are prepared and reviewed.

No-go if any dry-run proposes a broad firewall flush, default route change, unrelated interface change, real secret output, or non-IKEv2 production mutation.
