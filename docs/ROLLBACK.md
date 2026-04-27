# Rollback

## Golden rule

Do not change VPS host default route. Experiments must only affect forwarded traffic from `tailscale0`, preferably one canary client first.

## Current safe baseline

```text
Tailscale client -> tailscale0 -> Tailscale iptables NAT -> eth0 -> direct internet
```

If routing experiments fail, return to this baseline by stopping the routing layer and deleting our custom rules.

## Emergency checks

From local machine:

```bash
ssh vibe-practicum 'hostname; tailscale status | head; systemctl is-active tailscaled xray'
```

From a Tailscale client:

- disable/enable exit node in client UI;
- verify external IP is `45.12.74.211`;
- test Telegram/browser.

## Stop experimental services

```bash
ssh vibe-practicum 'printf "%s\n" "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S systemctl stop sing-box-vibe-router 2>/dev/null || true'
```

## Remove canary iptables rules

We will mark custom rules with comments containing `vibe-router`. Rollback command:

```bash
ssh vibe-practicum 'printf "%s\n" "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S bash -lc "iptables-save | grep -v vibe-router | iptables-restore"'
```

If we later use nftables, delete only our table/chain, e.g. `inet vibe_router`.

## Restore Tailscale baseline

Usually Tailscale's own rules remain untouched. If needed:

```bash
ssh vibe-practicum 'printf "%s\n" "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S systemctl restart tailscaled'
```

Do **not** run arbitrary `tailscale up` changes during rollback unless specifically needed.

## Xray fallback

Xray is separate from Tailscale direct exit-node path. If proxy tests fail:

```bash
ssh vibe-practicum 'printf "%s\n" "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S systemctl restart xray'
```

## Last resort

If Tailscale exit node breaks but SSH still works:

```bash
ssh vibe-practicum 'printf "%s\n" "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S bash -lc "systemctl stop sing-box-vibe-router 2>/dev/null || true; systemctl restart tailscaled; systemctl restart xray"'
```

Public SSH `45.12.74.211:22` is the primary recovery path.
