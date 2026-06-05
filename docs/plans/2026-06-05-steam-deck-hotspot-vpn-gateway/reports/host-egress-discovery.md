## Task
- Mission: Read-only discovery of Steam Deck host-namespace VPN egress options.
- Target: Existing Deck `vpnkit` Podman runtime and host-network reuse candidates.
- Boundaries: No mutations; no secrets/config contents/logs; redact IPs/endpoints and unrelated local service details.
- Done when: We know what runtime can expose host-routable VPN egress and the safest next step.
- Expected evidence: Redacted commands/output summary and options/recommendation.

## Context
- Thread: Steam Deck hotspot VPN gateway planning.
- Slice: Host-namespace VPN egress blocker discovery.
- Task package: `docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway`
- Report path: `docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway/reports/host-egress-discovery.md`
- Worktree: repo root `/home/kcnc/code/tools/vibe-practicum-vpn`
- Verify scope: read-only Deck runtime inspection, repo reuse candidates.

## Evidence summary
- Deck is SteamOS with `wlan0` as current Wi-Fi uplink and `tailscale0` present.
- Existing Podman `vpnkit` container is running from `localhost/vpnkit:steamdeck` and publishes UDP 1194.
- `podman inspect vpnkit` reports network mode `pasta`, not host network.
- Inside the `vpnkit` container:
  - `openvpn --config /etc/openvpn/server.conf` is running.
  - `sing-box run -c /var/lib/vpnkit/sing-box/config.json` is running.
  - `tun0` exists inside the container namespace.
  - sing-box has a selected outbound configured.
- On the Deck host:
  - no host `tun0` was observed.
  - `deck-hotspot-vpn-up.sh --dry-run` blocks on missing host VPN interface.

## Options considered

### Option A: Dedicated host-network OpenVPN client
- Description: Start a separate OpenVPN client on Deck with host networking so `tun0` appears in the Deck host namespace.
- Pros: Most directly matches hotspot NAT script expectations.
- Cons: Requires a client profile/runtime on Deck and careful coexistence with existing `vpnkit` server container.
- Safety requirement: separate container/name/state; do not stop/recreate existing `vpnkit`.

### Option B: Host-network sing-box/TUN runtime
- Description: Run or adapt sing-box in host namespace to create host-routable VPN/proxy egress.
- Pros: May reuse current selected outbound logic.
- Cons: More integration complexity; must avoid config drift and protect existing deployment.

### Option C: Forward hotspot traffic into existing container namespace
- Description: Keep current `vpnkit` as-is and route/proxy host hotspot traffic into it.
- Pros: Avoids a second VPN client.
- Cons: Current container egress is not host-routable; would require additional proxy/NAT plumbing and likely more fragile DNS/kill-switch behavior.

## Recommendation
- Safest next implementation: create a **dedicated, separately named host-network VPN egress runtime** on Deck, preferably an OpenVPN client or sing-box/TUN client, without disturbing the existing `vpnkit` container.
- Verification target before hotspot apply:
  - `ip link show tun0` or configured VPN iface succeeds on Deck host;
  - Deck host route/ping/curl through VPN works;
  - `scripts/deck-hotspot-vpn-up.sh --ssh-target deck --dry-run` no longer reports the missing VPN interface blocker.

## Acceptance verification
- AC1: Deck runtime inventory collected.
  - Result: passed.
  - Evidence: read-only SSH `podman inspect`, `podman port`, and `podman exec` process/interface/socket inspection.
- AC2: Host-namespace egress blocker understood.
  - Result: passed.
  - Evidence: existing `vpnkit` has container-internal `tun0`; Deck host does not.
- AC3: Safe next step identified.
  - Result: passed.
  - Evidence: recommendation favors a separate host-network egress runtime before any hotspot mutation.

## Issues
### Issue U-01: Host VPN interface absent
- Description: Prepared hotspot NAT/kill-switch cannot safely apply until a Deck host-namespace VPN egress interface exists.
- Evidence: dry-run report and runtime inspection.
- Why unresolved: creating the host egress runtime is a mutating implementation step not yet executed.
- Needed next: implement/run a bounded host egress bring-up with separate names, durable logs, and rollback.

## Verdict
- Status: partial.
- Goal state: blocker clarified, not yet resolved.
- Final readiness: ready for next implementation step, not ready for hotspot apply.
