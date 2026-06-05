## Task
- Mission: Own Steam Deck one-adapter hotspot VPN gateway preparation through discovery, script prep, and integration.
- Target: Steam Deck SSH alias `deck`, repo scripts, and task package `docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway`.
- Boundaries: Do not touch ASUS/router; do not mutate Deck hotspot/firewall/VPN until bounded evidence supports it; do not reveal secrets/private endpoints/profile contents.
- Done when: Phase 1 discovery is recorded, implementation scripts are prepared with durable logs/rollback, and current blocker/next action are explicit.
- Expected evidence: Redacted reports, prepared scripts, syntax/read-only/dry-run verification.

## Context
- Thread: User requested agents to proceed per Steam Deck hotspot VPN gateway plan.
- Slice: Root integration of discovery + script preparation.
- Task package: `docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway`
- Report path: `docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway/reports/root-owner.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn`
- Verify scope: shell syntax, Python syntax, read-only Deck discovery, Deck up dry-run.

## Spec compliance
- Requirement / AC: Primary target is one-adapter internal Wi-Fi STA+AP; dongle only fallback.
  - Status: done for planning/prep.
  - Evidence: plan and README updated; scripts default to `wlan0` uplink/hotspot.
  - Gap if any: live AP activation not attempted yet.
- Requirement / AC: Reuse existing Deck deployment.
  - Status: partial.
  - Evidence: reports confirm existing `vpnkit` Podman deployment; scripts do not recreate it.
  - Gap if any: existing `vpnkit` keeps TUN in container namespace; host egress still needed.
- Requirement / AC: Durable logs and rollback.
  - Status: done for prepared scripts.
  - Evidence: `deck-hotspot-vpn-discover/up/test/down` write reports from start; `down` removes only this tool's NM connection and nft table; `up` has cleanup trap for apply failure.
- Requirement / AC: No ASUS/router mutation.
  - Status: done.
  - Evidence: only Deck read-only commands and dry-run were executed in this phase.

## Acceptance verification
- AC1: Discovery evidence captured.
  - Covered by: `scripts/deck-hotspot-vpn-discover.sh --ssh-target deck --report .../verification/discover-smoke.md`
  - Result: passed.
  - Evidence: report written with `Mutation: none/read-only`.
- AC2: Scripts are syntactically valid.
  - Covered by: `bash -n scripts/*.sh` and `python3 -m py_compile scripts/vpnkit-control-panel.py`.
  - Result: passed.
- AC3: Up path is safe by default and finds blockers without mutation.
  - Covered by: `scripts/deck-hotspot-vpn-up.sh --ssh-target deck --dry-run --report .../verification/up-dry-run-smoke.md`
  - Result: passed with blocker.
  - Evidence: dry-run reports missing host `tun0`; no apply performed.
- AC4: Host egress blocker classified.
  - Covered by: read-only host egress discovery report.
  - Result: passed.
  - Evidence: current `vpnkit` uses Podman `pasta`; `tun0` is inside container, not on Deck host.

## System readiness
- Routes / registration: not ready for live hotspot; host VPN egress missing.
- Services / APIs: existing Deck `vpnkit` service remains untouched and should be reused cautiously.
- Config / env / secrets: not read or printed; hotspot password is accepted only at apply time and redacted.
- Permissions / access: SSH alias `deck` works for read-only checks.
- Runtime / deployment wiring: prepared but blocked on host-routable VPN egress.

## Verification run
- Local / targeted checks:
  - `bash -n scripts/*.sh`: passed.
  - `python3 -m py_compile scripts/vpnkit-control-panel.py`: passed.
  - `scripts/deck-hotspot-vpn-discover.sh --ssh-target deck --report docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway/verification/discover-smoke.md`: passed.
  - `scripts/deck-hotspot-vpn-up.sh --ssh-target deck --dry-run --report docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway/verification/up-dry-run-smoke.md`: passed with blocker.
- Local / full checks:
  - `go test ./...`: not run; current changes are shell/docs/scripts and live Deck discovery.
- Remote checks / CI:
  - Status: not available before push.

## Issues
### Issue U-01: Deck host VPN egress is missing
- Description: Prepared hotspot NAT/kill-switch expects a Deck host VPN interface, but `tun0` is only inside the existing `vpnkit` container.
- Evidence: `up-dry-run-smoke.md` reports `vpn iface missing: tun0`; `host-egress-discovery.md` records container-internal `tun0` and Podman `pasta` networking.
- Why unresolved: Fixing it requires a mutating runtime implementation decision.
- Needed next: create a separately named host-network VPN egress runtime or adapt a host-routable egress path, then rerun dry-run.
- Depends on: operator approval for bounded Deck mutation.

## Side findings
- Blocking findings folded into active work: U-01.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: partial.
- Goal state: planning/discovery/script preparation achieved; live gateway not achieved.
- Final readiness: not ready for `up --apply`.
- Summary: One-adapter Deck hotspot remains viable on paper and scripts are prepared, but host-namespace VPN egress must be implemented before live hotspot/NAT.

## Next-agent brief
- Objective: Implement Deck host-namespace VPN egress without disrupting existing `vpnkit`.
- Target: new or adapted script around host-network OpenVPN/sing-box runtime; then `deck-hotspot-vpn-up.sh --dry-run`.
- Settled already: no ASUS changes; internal Wi-Fi one-adapter is primary; existing `vpnkit` server container should not be overwritten.
- Boundaries: separate container/name/state; durable logs and rollback; no secrets/profile contents in output.
- Verification target: Deck host has VPN interface; Deck host route/ping/curl through VPN; up dry-run no longer blocks on missing VPN iface.
- Expected output: implementation report and redacted verification artifacts.
