# IKEv2 MVP design

This document is a design note for adding native-client IKEv2/IPsec access to the existing `vibe-practicum` VPS routing stack. It is intentionally documentation-only for milestone 0: no runtime code, production scripts, or VPS state are changed by this document.

## Goal

Add a native-client VPN entry path that can replace Tailscale for selected devices while preserving the existing downstream traffic selector and VLESS upstream selection pipeline.

The MVP should let one canary iOS device connect to the VPS using IKEv2, receive an address from `10.88.0.0/24`, and send eligible public internet traffic through the existing:

```text
sing-box TPROXY -> xray SOCKS -> vibe-vpn selected VLESS upstream -> internet
```

pipeline.

## Non-goals

- Do not replace `vibe-vpn` VLESS testing, picking, status, or rollback behavior.
- Do not migrate firewalling from iptables to nftables in the MVP.
- Do not mutate the VPS default route for canary rollout.
- Do not remove or disable the existing Tailscale path during the MVP.
- Do not commit generated private keys, PSKs, client profiles with embedded secrets, subscription URLs, or VLESS links.
- Do not implement runtime code in milestone 0.

## Current Tailscale-based architecture

The production path today is:

```text
client device
  -> Tailscale exit-node on VPS
  -> VPS tailscale0
  -> VPS sing-box TPROXY listener, port 2082
  -> xray SOCKS at 127.0.0.1:10808
  -> selected VLESS upstream managed by vibe-vpn
  -> internet
```

Operationally, Tailscale currently provides device enrollment, client VPN UX, client addressing, and the ingress interface (`tailscale0`). The VPS then classifies traffic and transparently proxies selected public internet flows through sing-box and xray. `vibe-vpn` remains responsible for selecting and rolling back the VLESS upstream used by production xray.

## Target IKEv2 architecture

The target MVP adds an IKEv2 ingress beside Tailscale, not instead of it:

```text
native VPN client, first canary: iOS
  -> IKEv2/IPsec tunnel to VPS
  -> strongSwan / swanctl
  -> route-based XFRM interface ipsec0
  -> VPN client address from 10.88.0.0/24
  -> VPS VPN gateway 10.88.0.1
  -> existing iptables classification / TPROXY rules
  -> sing-box TPROXY listener, port 2082
  -> xray SOCKS at 127.0.0.1:10808
  -> selected VLESS upstream managed by vibe-vpn
  -> internet
```

Coexistence during rollout:

```text
Tailscale clients -> tailscale0 -> existing selector -> sing-box -> xray -> VLESS
IKEv2 clients     -> ipsec0     -> existing selector -> sing-box -> xray -> VLESS
```

The selector must treat `ipsec0` as an additional trusted VPN ingress once implementation is finalized.

## Exact chosen stack

- VPN daemon/configuration: **strongSwan with swanctl**.
- IPsec model: **route-based IKEv2/IPsec using XFRM interface `ipsec0`**.
- VPN subnet: **`10.88.0.0/24`**.
- VPS VPN gateway IP: **`10.88.0.1`**.
- Authentication: **per-device certificates first**.
- Fallback authentication: EAP only if Android native support proves painful.
- CLI direction: extend the existing **`vibe-vpn`** CLI with `ikev2` subcommands later.
- Firewall/routing for MVP: **iptables**, matching the existing operational model.

## Why route-based XFRM instead of pure policy-based IPsec

Route-based XFRM gives the IKEv2 path an interface-like boundary (`ipsec0`) that looks similar to the existing `tailscale0` boundary. That is a better fit for this repository because the production value is not only encryption; it is the downstream routing and proxy selection pipeline.

Preferred properties:

- iptables rules can match `-i ipsec0`, keeping classification readable and close to existing Tailscale rules.
- Operators can inspect traffic and routes by interface, which is easier to reason about during canary rollout.
- The MVP can add IKEv2 as another ingress without changing the VPS default route.
- Route-based behavior makes bypass/public-internet decisions explicit in routing and firewall rules instead of burying them only in IPsec traffic selector policy.
- It gives future `vibe-vpn ikev2` commands a concrete object to verify: connection state, `ipsec0` existence, assigned pool, and per-interface counters.

Pure policy-based IPsec may work, but it is easier to accidentally create broad selectors that are hard to map onto the existing TPROXY pipeline. For this project, debuggability and canary safety are more important than minimizing interface objects.

## Traffic classification rules

The IKEv2 ingress must preserve the existing downstream selector semantics:

- VPN/private/internal destinations bypass xray/VLESS.
- Public internet destinations enter the selector and, if selected, are TPROXYed to sing-box.
- sing-box forwards selected traffic to xray SOCKS at `127.0.0.1:10808`.
- xray uses the VLESS upstream selected by `vibe-vpn`.

Design intent for bypasses:

```text
10.88.0.0/24          IKEv2 client pool / local VPN subnet: bypass VLESS
100.64.0.0/10         Tailscale CGNAT range: bypass VLESS when relevant
RFC1918/private nets  private/internal routing: bypass VLESS
VPS-local services    management and local health checks: bypass VLESS
public internet       eligible for existing TPROXY -> sing-box -> xray path
```

Implementation must avoid proxying IKE control traffic, IPsec encapsulation traffic, local management traffic, or private/VPN-to-VPN traffic back into xray.

## Migration and canary constraints

- Tailscale remains operational throughout MVP rollout.
- Do not disable `tailscaled`, change existing Tailscale ACL assumptions, or remove existing `tailscale0` routing until a separate migration decision is made.
- Do not mutate the VPS default route during the canary.
- Start with one iOS canary device.
- Add `ipsec0` and IKEv2-specific rules as additive ingress behavior.
- Keep existing `vibe-vpn` state and current VLESS upstream selection unchanged unless intentionally testing upstream changes with existing `vibe-vpn` commands.
- Prefer reversible, narrowly scoped rules and backups for any future implementation step.

## Security and secrets

- Never commit private keys, PSKs, generated client profiles containing private keys, VLESS links, subscription URLs, or real device-identifying secrets.
- Store CA, server, and device private keys only on intended hosts with restrictive permissions.
- Treat mobile configuration profiles as secrets if they embed private keys or credentials.
- Logs and support output must redact certificate private material, VLESS links, subscription URLs, and any generated profile payloads.
- Per-device certificates are the MVP default so a lost or retired device can be revoked independently.
- EAP fallback, if added later, must avoid shared credentials in git and must document revocation/rotation.

## MVP acceptance criteria

Summarized from issue #1 and the selected direction, the MVP is accepted when:

- An iOS canary can connect with native IKEv2 using per-device certificate auth.
- The canary receives/uses the `10.88.0.0/24` VPN network with VPS gateway `10.88.0.1`.
- IKEv2 client public internet traffic follows the existing selector into sing-box, xray, and the selected VLESS upstream.
- VPN/private/internal traffic bypasses xray/VLESS as intended.
- Tailscale clients continue to work during the canary.
- The VPS default route is not changed by the IKEv2 rollout.
- Operators have read-only status checks and a documented rollback path.
- No secrets are committed or printed in routine logs.
- The design leaves room for later `vibe-vpn ikev2` subcommands without changing current `vibe-vpn` behavior.

## Risks and open questions

- XFRM road-warrior details: exact strongSwan/swanctl configuration, address pool behavior, route installation, marks, and interface lifecycle must be validated during implementation.
- Android UX: per-device certificate import and native IKEv2 behavior may be painful; EAP fallback remains an option only if needed.
- UDP and DNS TPROXY: DNS handling and UDP proxy behavior must be tested explicitly for IKEv2 clients, not assumed from Tailscale behavior.
- Profile/private key handling: the process for generating, storing, transferring, revoking, and deleting device profiles must be finalized before real profiles are produced.
- Canary observability: status commands must distinguish Tailscale ingress from `ipsec0` ingress without exposing secrets.
- Rule ordering: additive iptables rules for `ipsec0` must not shadow or break existing `tailscale0` rules.
