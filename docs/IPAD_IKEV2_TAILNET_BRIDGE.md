# iPad IKEv2 to Tailscale tailnet bridge plan

This runbook covers the focused relocation use-case:

```text
iPad native IKEv2 -> VPS ipsec0 / 10.88.0.0/24 -> VPS tailscale0 / 100.64.0.0/10 -> PC/Steam Deck
```

It preserves the existing Tailscale, Hysteria/sing-box, xray/VLESS, Docker, and VPS default-route behavior. The commands below are planner/audit commands unless an operator separately approves live application.

## Live target facts

- VPS public IP: `45.12.74.211`
- VPS tailnet name/IP: `awsbbbuslw` / `100.121.107.112`
- PC: `kcnc-pc` / `100.68.65.56`
- Steam Deck: `positions-deck` / `100.94.95.32`
- IKEv2 subnet/gateway/interface: `10.88.0.0/24`, `10.88.0.1`, `ipsec0`
- Tailnet interface/subnet: `tailscale0`, `100.64.0.0/10`

## Intended access model

Wide private access is allowed from IKEv2 clients to the tailnet. This is not a public port-forward design.

```text
ipsec0 -> tailscale0 src 10.88.0.0/24 dst 100.64.0.0/10 ACCEPT
tailscale0 -> ipsec0 ESTABLISHED,RELATED ACCEPT
src 10.88.0.0/24 dst 100.64.0.0/10 out tailscale0 MASQUERADE
```

The MASQUERADE rule makes PC/Deck replies return through the VPS tailnet IP, so no route changes are required on those hosts.

## iPad client identity/profile

Create a stable iPad client entry and render the iOS profile through the existing safe CLI workflow. These commands write local PKI/state/profile files, so choose the intended config and output paths explicitly:

```bash
vibe-vpn --config /path/to/staging-or-live-config.json ikev2 client create ipad --ip 10.88.0.10 --os ios
vibe-vpn --config /path/to/staging-or-live-config.json ikev2 client render ipad --output-dir /secure/operator/chosen/path
```

Do not paste or commit generated profiles, private keys, certificates, PSKs, subscription URLs, VLESS links, or other secret material.

## Dry-run bridge planning

Review the existing IKEv2 routing/TPROXY plan first. It must keep private/tailnet destinations as `RETURN` bypasses before TPROXY capture:

```bash
vibe-vpn --config /path/to/staging-or-live-config.json ikev2 routing status
vibe-vpn --config /path/to/staging-or-live-config.json ikev2 routing enable --dry-run
```

Then review the bridge plan:

```bash
vibe-vpn --config /path/to/staging-or-live-config.json ikev2 routing bridge status
vibe-vpn --config /path/to/staging-or-live-config.json ikev2 routing bridge enable --dry-run
```

Expected bridge plan properties:

- adds only comment-scoped `vibe-vpn-ikev2-tailnet-bridge:*` rules;
- uses check-before-add idempotent commands;
- allows `10.88.0.0/24 -> 100.64.0.0/10` from `ipsec0` to `tailscale0`;
- allows only `ESTABLISHED,RELATED` return from `tailscale0` to `ipsec0`;
- adds MASQUERADE only for `10.88.0.0/24 -> 100.64.0.0/10` out `tailscale0`;
- inserts comment-scoped private bypass rules into `VIBE_ROUTER_IKEV2` only if that chain exists;
- does not change the VPS default route and does not restart tailscaled, strongSwan, xray, sing-box, Hysteria, or Docker.

## Read-only live audit commands

The bridge status command prints read-only `iptables -C` audit commands. On the VPS, after live approval/application, these should report `present:*` for the bridge rules. Missing bridge rules mean private tailnet access from the iPad may fail.

Additional read-only checks:

```bash
ip -brief addr show ipsec0 || true
ip -brief addr show tailscale0 || true
ip route get 100.68.65.56 || true
ip route get 100.94.95.32 || true
sudo iptables-save | grep 'vibe-vpn-ikev2-tailnet-bridge' || true
```

## User acceptance checks

With the iPad VPN connected:

1. Confirm the iPad uses the expected private address, e.g. `10.88.0.10`.
2. Reach PC at `100.68.65.56`.
3. Reach Steam Deck at `100.94.95.32`.
4. Test SSH/SCP/SFTP where SSH is enabled.
5. Test RDP to PC only if Windows RDP service and host firewall allow it.
6. Confirm iPad internet still works through the existing VPS path.
7. Confirm private tailnet traffic does not go through xray/VLESS.

## Rollback plan

Review rollback before any live application:

```bash
vibe-vpn --config /path/to/staging-or-live-config.json ikev2 routing bridge disable --dry-run
```

The rollback plan deletes only exact comment-scoped bridge rules. It must not flush broad chains, delete existing Tailscale/Hysteria/IKEv2 rules, change the default route, or restart services.

If a broader IKEv2 rollback is needed, run the bridge disable plan first, then follow [`IKEV2_ROLLBACK.md`](./IKEV2_ROLLBACK.md).
