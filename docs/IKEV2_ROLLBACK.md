# IKEv2 rollback plan

This document is design-level rollback guidance for the planned IKEv2 MVP. It is **not** a final tested command runbook. Commands in this file are read-only unless explicitly marked as future placeholders to finalize during implementation.

The rollback goal is to remove or disable the IKEv2 ingress path while preserving the existing Tailscale and `vibe-vpn` production path.

## Safety assumptions

- Tailscale remains installed, enabled, and usable during IKEv2 canary rollout.
- The VPS default route was not changed for IKEv2.
- IKEv2 changes were implemented additively: strongSwan/swanctl config, XFRM interface `ipsec0`, and iptables rules scoped to IKEv2 ingress.
- Backups exist for any swanctl/strongSwan files modified during implementation.
- Operators can access the VPS through a non-IKEv2 path before changing IKEv2 state.
- No rollback command should print private keys, PSKs, VLESS links, subscription URLs, or generated client profile payloads.

## Must remain untouched

Rollback of IKEv2 must not change these unless the operator is intentionally performing a separate production change:

- VPS default route.
- Existing Tailscale path, including `tailscaled`, `tailscale0`, and current Tailscale client routing assumptions.
- Existing sing-box/xray/vibe-vpn production path except for narrowly scoped IKEv2 TPROXY/routing rules.
- Existing `vibe-vpn` upstream selection state, including current node and xray config, unless explicitly changing upstream with `vibe-vpn` commands.
- VLESS subscription files, VLESS links, and `vibe-vpn` backups.

## Future rollback areas

These areas are expected to have concrete implementation-specific commands later. Until implementation exists, treat this as a checklist.

1. Disable the optional IKEv2-to-tailnet bridge if it was enabled.
   - Review `vibe-vpn ikev2 routing bridge disable --dry-run`.
   - Remove only exact `vibe-vpn-ikev2-tailnet-bridge:*` comment-scoped rules from `filter/FORWARD`, `nat/POSTROUTING`, and the dedicated IKEv2 mangle chain.
   - Do not remove existing Tailscale/Hysteria rules or broad `tailscale0` behavior.
2. Disable IKEv2-specific TPROXY/routing rules.
   - Remove or disable iptables rules that match `ipsec0` or `10.88.0.0/24` and send traffic into the TPROXY selector.
   - Do not remove existing `tailscale0` rules outside the exact bridge comments above.
3. Unload or stop the strongSwan IKEv2 connection.
   - Terminate active IKE_SA/CHILD_SA state for the canary connection.
   - Disable loading of the MVP connection if needed.
4. Remove or disable `ipsec0`.
   - Bring down/delete the XFRM interface only after traffic has stopped and strongSwan state is unloaded.
   - Do not touch unrelated interfaces.
5. Restore swanctl backups.
   - Restore only files changed for IKEv2 MVP.
   - Preserve permissions and ownership.
6. Verify Tailscale path.
   - Confirm existing clients still route through `tailscale0`, sing-box, xray, and the selected VLESS upstream.

## Read-only verification before rollback

Use read-only checks first to understand current state. Exact commands may change during implementation, but these patterns are safe because they inspect state only:

```bash
# Interfaces and addresses
ip -brief addr show
ip -details link show ipsec0 || true

# Routes and policy rules
ip route show
ip rule show

# XFRM/IPsec state
ip xfrm state
ip xfrm policy
sudo swanctl --list-conns
sudo swanctl --list-sas

# Firewall/routing rules; do not include secrets in comments
sudo iptables-save | grep -E 'ipsec0|10\.88\.0\.|TPROXY|2082|vibe-vpn-ikev2-tailnet-bridge' || true

# Existing production path status
systemctl is-active tailscaled || true
ip -brief addr show tailscale0 || true
systemctl is-active sing-box-vibe-router || true
systemctl is-active xray || true
sudo vibe-vpn status
```

Before rollback, capture enough output to identify which rules and connections are IKEv2-specific. Do not paste private key files, generated profiles, subscription URLs, or VLESS links into logs or chat.

## Future placeholder commands

The following are **placeholders only**. They are not claimed to be tested and must be finalized during implementation after exact connection names, table names, rule comments, and service names are known.

```bash
# FUTURE PLACEHOLDER: terminate IKEv2 connection by finalized swanctl name
# sudo swanctl --terminate --ike <ikev2-connection-name>

# FUTURE PLACEHOLDER: unload finalized swanctl connection or reload restored config
# sudo swanctl --load-all

# Bridge rollback planner: deletes only exact vibe-vpn-ikev2-tailnet-bridge:* rules
# sudo vibe-vpn ikev2 routing bridge disable --dry-run

# FUTURE PLACEHOLDER: delete only finalized IKEv2 iptables rules by exact handle/comment
# sudo iptables -t mangle -D <CHAIN> <exact finalized rule spec>

# FUTURE PLACEHOLDER: remove XFRM interface after strongSwan state is stopped
# sudo ip link set ipsec0 down
# sudo ip link delete ipsec0

# FUTURE PLACEHOLDER: restore backed up swanctl files created by implementation
# sudo cp -a <backup-file> <target-file>
```

Do not use broad flushes such as `iptables -F`, `iptables -t mangle -F`, or wholesale config directory deletion for IKEv2 rollback. They can break the existing Tailscale and TPROXY path.

## Read-only verification after rollback

After rollback, verify that IKEv2 is inactive and Tailscale still works:

```bash
# IKEv2 should be inactive or have no canary SA
sudo swanctl --list-sas
ip -details link show ipsec0 || true
ip xfrm state
ip xfrm policy

# IKEv2-specific rules should be absent or disabled
sudo iptables-save | grep -E 'ipsec0|10\.88\.0\.' || true

# Tailscale and production proxy path should still be active
systemctl is-active tailscaled || true
ip -brief addr show tailscale0 || true
systemctl is-active sing-box-vibe-router || true
systemctl is-active xray || true
sudo vibe-vpn status
```

Expected post-rollback state:

- No active canary IKEv2 SA remains.
- `ipsec0` is absent or administratively disabled, depending on the finalized implementation.
- IKEv2-specific iptables rules are absent or disabled.
- Tailscale remains active.
- `vibe-vpn status` still reports the current selected upstream state.
- The VPS default route is unchanged from before rollback.

## Secret-handling reminders

- Do not print, paste, or commit private keys, PSKs, generated mobileconfig/profile files, VLESS links, or subscription URLs.
- Treat client profiles as secrets if they contain private keys or credentials.
- Redact certificate serials or device identifiers when sharing public logs if they can identify a user/device.
- Backups containing private key material must stay on the VPS or another approved secure location with restrictive permissions.
- Rollback notes should describe filenames and actions, not embed secret file contents.
