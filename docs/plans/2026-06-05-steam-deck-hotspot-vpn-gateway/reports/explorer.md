## Task
- Mission: Read-only Steam Deck discovery for the one-adapter hotspot VPN gateway plan.
- Target: Steam Deck SSH alias `deck`, existing Podman/runtime state, Wi-Fi capability, routing/tooling availability, and reuse candidates in this repo.
- Boundaries: Do not mutate Deck, ASUS, firewall, NetworkManager, containers, or configs.
- Done when: We know whether one-adapter STA+AP appears viable, what existing deployment should be reused, and the main blockers/risks.
- Expected evidence: Redacted local discovery report with exact commands/output excerpts and a clear reuse/risks summary.

## Context
- Thread: Steam Deck hotspot VPN gateway planning.
- Slice: Phase 1 discovery and reuse mapping.
- Task name: Steam Deck one-adapter hotspot VPN gateway discovery.
- Task package: `docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway`
- Report path: `docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway/reports/explorer.md`
- Worktree: repo root `/home/kcnc/code/tools/vibe-practicum-vpn`
- Branch: not checked / not required for discovery.
- Verify scope: read-only SSH inventory, Wi-Fi capability, Podman/container state, routing/kernel toggles.
- Review target: `docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway/plan.md`, `scripts/vpnkit-steamdeck-podman.sh`, `scripts/vpnkit-steamdeck-client-test.sh`.

## Spec compliance
- Requirement / AC: Determine whether one-adapter STA+AP appears viable.
  - Status: done
  - Evidence: `iw list` on Deck shows `Supported interface modes: managed, AP, P2P-client, P2P-GO, P2P-device`; `valid interface combinations` includes `#{ managed } <= 2, #{ AP, P2P-client, P2P-GO } <= 1 ... total <= 3, #channels <= 2, STA/AP BI must match`.
  - Gap if any: not yet proven under live NetworkManager hotspot activation.
- Requirement / AC: Identify existing deployment to reuse.
  - Status: done
  - Evidence: `podman ps` on Deck shows `vpnkit` running for 4 days from `localhost/vpnkit:steamdeck`; `podman inspect vpnkit` confirms image `localhost/vpnkit:steamdeck` and UDP 1194 publish.
  - Gap if any: none for discovery; runtime internals not inspected further.
- Requirement / AC: Collect read-only environment evidence and redact private values.
  - Status: done
  - Evidence: commands run over `ssh deck` with IP/MAC redaction in captured output.
  - Gap if any: none.

## Acceptance verification
- AC1: Read-only host inventory collected.
  - Covered by: `hostnamectl`, `uname -a`, `ip -br link`, `ip -br addr`, `ip route`, `nmcli dev status`, `nmcli con show` on Deck.
  - Result: passed
  - Evidence: Deck has `wlan0` connected, `tailscale0` present, and default route via `wlan0`.
- AC2: One-adapter Wi-Fi capability assessed.
  - Covered by: `iw dev` and `iw list` sections on Deck.
  - Result: passed
  - Evidence: `wlan0` is `managed`; `AP` mode is supported; valid interface combinations permit concurrent managed+AP with `#channels <= 2` and `STA/AP BI must match`.
- AC3: Reuse candidates identified.
  - Covered by: `podman ps`, `podman inspect vpnkit`, and repo script inspection.
  - Result: passed
  - Evidence: running `vpnkit` Podman container; `scripts/vpnkit-steamdeck-podman.sh` already has `check-ssh`, `deploy`, `verify`, `logs`, `stop`, `cleanup`; `scripts/vpnkit-steamdeck-client-test.sh` already exists for external validation.

## System readiness
- Routes / registration: not relevant for discovery; current host routing visible and stable.
- Services / APIs: partially ready; existing `vpnkit` container is running.
- Config / env / secrets: not touched; no secrets read or printed.
- Permissions / access: SSH alias `deck` works read-only; no privileged mutation attempted.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: reuse path exists via `scripts/vpnkit-steamdeck-podman.sh`; Deck is Podman-only and currently has `vpnkit` deployed.

## Verification run
- Local / targeted checks:
  - `ssh -G deck | grep -E '^(hostname|user|port|identityfile|proxyjump) '`: passed
    - Evidence: alias resolves to `user deck`, `port 22`.
  - `ssh deck '...hostnamectl; ip -br link; nmcli dev status; iw list; podman ps; sysctl net.ipv4.ip_forward; ...'`: passed
    - Evidence: redacted stdout captured in the shell session.
- Local / full checks:
  - Not run: no mutations or client-side hotspot exercise performed.
- Remote checks / CI:
  - Status: not available before push
  - Evidence: no PR/CI for this discovery-only report.

## Issues
### Issue U-01: One-adapter hotspot still needs live activation proof
- Description: The hardware/driver advertises concurrent managed+AP support, but discovery did not actually enable a hotspot while keeping uplink and VPN stable.
- Evidence: `valid interface combinations` requires matching STA/AP beacon interval and shared-channel constraints; `net.ipv4.ip_forward = 0` by default.
- Why unresolved: Safe discovery scope did not include live mutation.
- Needed next: implement a bounded bring-up script and run it on Deck with fail-closed rollback.
- Depends on: Deck operator approval for mutation.

### Issue U-02: Forwarding is disabled by default
- Description: The Deck reports `net.ipv4.ip_forward = 0`.
- Evidence: `sysctl net.ipv4.ip_forward` output on Deck.
- Why unresolved: must be intentionally enabled as part of gateway setup.
- Needed next: hotfix/bring-up step to set forwarding and NAT with rollback.
- Depends on: gateway implementation step.

## Side findings
- Blocking findings folded into active work: U-01, U-02.
- Non-blocking findings tracked separately: Deck also has `tailscale0` present and the Wi-Fi uplink is currently on channel 12; these are relevant to channel-sharing/stability but not blocking the plan.

## Verdict
- Status: partial
- Goal state: not achieved yet
- Final readiness: ready for implementation planning
- Summary: Steam Deck one-adapter STA+AP appears viable on paper from driver capabilities, and the existing Podman `vpnkit` deployment should be reused; actual hotspot bring-up and fail-closed gateway behavior still need a bounded implementation/test pass.

## Next-agent brief
- Objective: Implement and validate a bounded Deck hotspot/VPN bring-up/down path with durable logs and rollback.
- Target: `scripts/vpnkit-steamdeck-podman.sh` reuse or new Deck hotspot scripts under `scripts/`, plus plan updates under this task package.
- Settled already: one-adapter mode is the primary target; Deck already runs Podman `vpnkit`; no ASUS/router changes are needed for this phase.
- Boundaries: do not expose secrets or mutate ASUS; keep all Deck changes fail-closed and reversible.
- Verification target: a fresh Deck run showing hotspot up, VPN tunnel up, client connectivity through VPN, and cleanup/down restoring normal state.
- Expected output: implementation/update report with command logs and a redacted verification artifact.
