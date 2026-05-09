# iPad IKEv2 live checkpoint

Date: 2026-05-07 UTC

This is a non-secret operational checkpoint for the live iPad IKEv2 rollout.

## Known current live state

- VPS: `45.12.74.211` (`vibe-practicum` SSH alias)
- iPad virtual IP: `10.88.0.2`
- VPN subnet: `10.88.0.0/24`
- XFRM interface: `ipsec0`, gateway `10.88.0.1/24`, `if_id = 42`
- Tailscale interface: `tailscale0`
- Tailscale peers used for testing:
  - PC: `100.68.65.56`
  - Steam Deck: `100.94.95.32`
- Services expected active:
  - `strongswan`
  - `sing-box-vibe-router`
  - `xray`
  - `tailscaled`

## Confirmed working before checkpoint

- iPad successfully established IKEv2 `IKE_SA` / `CHILD_SA` and received `10.88.0.2`.
- After the direct-NAT hotfix, iPad internet worked.
- iPad reached the PC through the tailnet bridge by opening:
  - `http://100.68.65.56:8787/index.txt`
- Tcpdump confirmed the path:
  - `10.88.0.2 -> ipsec0 -> tailscale0 -> 100.68.65.56:8787`
  - return traffic came back through `tailscale0 -> ipsec0 -> 10.88.0.2`.

## Current rollbacked live networking shape

This is the state restored after the later TPROXY/sing-box experiments caused broad iPad connectivity issues.

### Policy routing

Known-good restored rule:

```text
219: from all fwmark 0x88 lookup 188
```

Table `188` remains the TPROXY local table:

```text
local default dev lo scope host
```

### iPad public internet hotfix

A top RETURN is present in `VIBE_ROUTER_IKEV2`:

```text
vibe-vpn-ikev2-hotfix:bypass-tproxy-all
```

This intentionally bypasses IKEv2 TPROXY for iPad traffic for now.
Public iPad traffic uses direct forwarding/NAT instead:

```text
ipsec0 -> eth0
eth0 -> ipsec0 RELATED,ESTABLISHED
10.88.0.0/24 -> eth0 MASQUERADE
```

Tradeoff: this restores generic iPad internet but does not proxy iPad public traffic through `sing-box` / `xray` yet.

### Tailnet bridge

Tailnet bridge remains installed:

```text
ipsec0 -> tailscale0 for 10.88.0.0/24 -> 100.64.0.0/10
tailscale0 -> ipsec0 RELATED,ESTABLISHED
10.88.0.0/24 -> tailscale0 MASQUERADE for 100.64.0.0/10
```

This is required for iPad access to `100.68.65.56` / `100.94.95.32` without adding return routes on tailnet peers.

## Changes that were rolled back

These were reverted because the user reported broad iPad connectivity breakage:

1. `ip rule` scoped variant:

```text
219: from all fwmark 0x88 iif ipsec0 lookup 188
```

2. Removal of the top `bypass-tproxy-all` RETURN.
3. Temporary sing-box Telegram CIDR rule forcing Telegram ranges through `xray-socks-out`.

The sing-box config was restored from the backup taken before the Telegram CIDR edit.

## Useful backup paths on VPS

- Initial server backup:
  - `/root/vibe-ikev2-backups/20260507T222228Z`
- Direct internet hotfix backup:
  - `/root/vibe-ikev2-backups/20260507T222956Z-ipad-internet-hotfix`
- TPROXY mark experiment backup:
  - `/root/vibe-ikev2-backups/20260507T225139Z-ipad-tproxy-mark-fix`
- Telegram route experiment backup:
  - `/root/vibe-ikev2-backups/20260507T225519Z-telegram-route-fix2`
- Rollback-to-hotfix checkpoint:
  - `/root/vibe-ikev2-backups/20260507T230308Z-rollback-to-ipad-internet-hotfix`

## Next debugging target

Do not re-enable iPad TPROXY blindly.

Next session should audit why `ipsec0` TPROXY via sing-box breaks broad iPad traffic. Suspects:

- DNS hijack/return path for iPad traffic through sing-box.
- TPROXY mark/rule interaction with packets from `ipsec0`.
- sing-box TPROXY handling for source `10.88.0.2` compared to existing working tailnet sources like `100.68.65.56`.
- Direct-vs-proxy route ordering for Telegram and other public destinations.

Keep the known-good direct-NAT bypass as the fallback while investigating.
