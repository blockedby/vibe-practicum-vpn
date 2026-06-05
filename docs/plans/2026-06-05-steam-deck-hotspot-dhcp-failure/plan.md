# Steam Deck hotspot DHCP failure plan

## Task intake
- Goal: hotspot clients can join the Deck AP and receive IPv4 DHCP from the Deck hotspot service.
- In scope: script fixes for `scripts/deck-hotspot-vpn-up.sh`, `scripts/deck-hotspot-vpn-test.sh`, `scripts/deck-hotspot-vpn-down.sh`, `steam-deck/hotspot-client/Containerfile.hotspot`, `steam-deck/hotspot-client/scripts/hotspot-entrypoint.sh`; live Deck state mutation via approved `deck` SSH alias; redacted evidence only.
- Out of scope: revealing private endpoint/profile/log contents, changing ASUS/router, touching existing production `vpnkit`, or deleting rollback path.
- Done state: committed/pushed branch has script/runtime fixes; live Deck has fixed hotspot state or a documented blocker; rollback command remains usable; evidence identifies DHCP binding/listening/log status and safe tests.
- Blocking unknowns: actual dnsmasq bind/listen failure mode, whether host networking + container privileges permit DHCP broadcast on ap0, whether nft/firewalld is dropping DHCP, and whether ap0 is addressed/up when dnsmasq starts.

## Repo orientation
- Repo root guidance: public-safe redaction, private endpoints only in gitignored local env, Deck deployment is Podman-only, no generated logs/profiles committed.
- Likely files: `scripts/deck-hotspot-vpn-up.sh`, `scripts/deck-hotspot-vpn-down.sh`, `scripts/deck-hotspot-vpn-test.sh`, `steam-deck/hotspot-client/Containerfile.hotspot`, `steam-deck/hotspot-client/scripts/hotspot-entrypoint.sh`, `steam-deck/hotspot-client/README.md` if docs need command updates.
- Verification commands: `bash -n scripts/*.sh steam-deck/hotspot-client/scripts/*.sh`; dry-run/apply/test/down scripts against `deck` with redacted reports; targeted remote checks for `ip addr show ap0`, `ss -lunp`, `ps`, `podman logs`, dnsmasq/hostapd logs, nft rules, DHCP packet visibility if available.

## Reuse discovery
- Existing up script creates `ap0`, assigns `10.42.0.1/24`, writes hostapd/dnsmasq configs, starts a privileged host-network Podman container, and installs nft NAT/forward rules.
- Existing entrypoint starts hostapd, sleeps 2 seconds, then execs dnsmasq with a mounted config.
- Existing down script removes only this hotspot container/table/interface and must remain the rollback path.
- Existing report redaction replaces IPv4/MAC/IPv6/UUID and password values; keep or improve it.

## Missing pieces
- Concrete live failure evidence for dnsmasq binding/listening and DHCP request handling.
- Script/runtime fix for the observed failure (likely dnsmasq binding capability/interface readiness/listen-address/except-interface/logging or host/container networking details).
- Post-fix live apply/test evidence, including a client-DHCP proof if available or a server-side DHCP readiness proof if no client can be exercised.

## Plan tasks

### Task 1: Diagnose and fix DHCP service readiness
Goal:
- Make the hotspot DHCP service reliably bind to `ap0` and serve leases in the host-network container.
Boundary:
- System area: Deck hotspot runtime scripts/container entrypoint.
- Primary verification: live Deck apply/test evidence plus shell syntax checks.
Existing pattern / reuse:
- Reuse up/down/test scripts and redaction/report style.
Missing change:
- Patch only the minimal script/container configuration needed by the observed failure.
Scope / likely files:
- `scripts/deck-hotspot-vpn-up.sh`, `scripts/deck-hotspot-vpn-test.sh`, `scripts/deck-hotspot-vpn-down.sh`, `steam-deck/hotspot-client/scripts/hotspot-entrypoint.sh`, `steam-deck/hotspot-client/Containerfile.hotspot`.
Acceptance criteria:
- `dnsmasq` starts and remains running with `ap0` addressed/up.
- DHCP UDP 67 listens on the intended interface/address or equivalent dnsmasq evidence shows it is ready.
- Hostapd remains up and AP remains visible/up.
- Rollback via `scripts/deck-hotspot-vpn-down.sh --ssh-target deck` remains idempotent.
- No secrets/private endpoint/generated profile/log contents are printed or committed.
Test plan:
- Positive: run `bash -n` on changed shell scripts; run `scripts/deck-hotspot-vpn-up.sh --ssh-target deck --apply --yes` with password supplied from environment; run server-side checks for `ap0`, dnsmasq/hostapd process/logs/listeners; run `scripts/deck-hotspot-vpn-test.sh --ssh-target deck`.
- Negative: run rollback down and confirm container/table/ap0 removal; re-apply after rollback if needed.
- Manual/client: if a test client is available, verify it receives an address; otherwise record server-side DHCP readiness and remaining client-side check.
Dependencies:
- Depends on: host VPN container/tun0 already running per task intake.
- Blocks: final owner verification/report.
- Can run parallel with: none.
Executor:
- aad-implementer.

## Dependency graph / execution ledger
- Wave 1: Task 1 via aad-implementer (single coherent verification story; slice stays whole, no sub-slices).
- Wave 2: owner reviews report/diff, runs or requests acceptance audit if evidence is ambiguous, commits/pushes final branch.

## Issues
- none yet.
