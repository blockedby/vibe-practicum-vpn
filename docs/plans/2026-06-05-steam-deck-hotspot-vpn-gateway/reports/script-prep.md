## Task
- Mission: Prepare Steam Deck one-adapter hotspot VPN gateway scripts with durable logs and rollback.
- Target: `scripts/deck-hotspot-vpn-*.sh`, README, and task-package plan updates.
- Boundaries: No mutating Deck hotspot/firewall/VPN changes; no ASUS/router changes; no secrets/profiles/private endpoints in output.
- Done when: discover/up/test/down scripts exist, default safe behavior is non-mutating, apply path has confirmation/rollback, and syntax/help/read-only smoke pass.
- Expected evidence: script files, redacted discovery/dry-run reports, bash syntax checks.

## Context
- Thread: Steam Deck internal Wi-Fi one-adapter hotspot gateway replacing fragile ASUS path.
- Slice: Steam Deck hotspot script preparation.
- Task package: `docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway`
- Report path: `docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway/reports/script-prep.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn`
- Verify scope: shell syntax, help output, read-only discovery, up dry-run.

## Spec compliance
- Requirement / AC: One-adapter internal Wi-Fi is primary; dongle only fallback.
  - Status: done
  - Evidence: README and plan describe one-adapter path as primary; scripts default `--uplink-iface wlan0 --hotspot-iface wlan0`.
  - Gap if any: live hotspot activation not attempted.
- Requirement / AC: Reuse existing Deck deployment and do not blindly overwrite it.
  - Status: done
  - Evidence: `deck-hotspot-vpn-up.sh` does not recreate `vpnkit`; it expects an existing host egress interface and reports missing `tun0` in dry-run.
  - Gap if any: existing `vpnkit` container appears not to expose host `tun0`, so a host-namespace egress path remains needed.
- Requirement / AC: Durable logs/reports from start.
  - Status: done
  - Evidence: all four scripts create report paths under `reports/` by default and tee redacted output; verification artifacts written under task-package `verification/`.
  - Gap if any: generated reports are untracked artifacts and should not be committed if they contain environment details.
- Requirement / AC: Rollback/down cleanup.
  - Status: done
  - Evidence: `deck-hotspot-vpn-down.sh` idempotently deletes only this tool's NetworkManager connection and nft table; `up --apply` has failure trap that invokes cleanup for those resources.
  - Gap if any: apply path not live-tested.

## Acceptance verification
- AC1: Scripts parse and help works.
  - Covered by: `bash -n scripts/*.sh` and `--help` for all four Deck scripts.
  - Result: passed
  - Evidence: commands completed successfully.
- AC2: Read-only discovery writes redacted report.
  - Covered by: `scripts/deck-hotspot-vpn-discover.sh --ssh-target deck --report docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway/verification/discover-smoke.md`
  - Result: passed
  - Evidence: report path exists and output states `Mutation: none/read-only`.
- AC3: Up dry-run is non-mutating and identifies blockers.
  - Covered by: `scripts/deck-hotspot-vpn-up.sh --ssh-target deck --dry-run --report docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway/verification/up-dry-run-smoke.md`
  - Result: passed with blocker
  - Evidence: dry-run completed and reported `vpn iface missing: tun0` plus dry-run planned NM/nft/sysctl changes.

## System readiness
- Routes / registration: prepared scripts only; live gateway not ready until host VPN egress exists.
- Services / APIs: existing Deck `vpnkit` should be reused; not modified.
- Config / env / secrets: hotspot password accepted through env/arg and redacted; no profile contents read.
- Permissions / access: SSH alias `deck` worked for read-only discovery/dry-run.
- Runtime / deployment wiring: partial; scripts prepared, but host-namespace `tun0` blocker prevents safe apply.

## Verification run
- Local / targeted checks:
  - `bash -n scripts/*.sh`: passed.
  - `scripts/deck-hotspot-vpn-*.sh --help`: passed.
  - `scripts/deck-hotspot-vpn-discover.sh --ssh-target deck --report .../discover-smoke.md`: passed.
  - `scripts/deck-hotspot-vpn-up.sh --ssh-target deck --dry-run --report .../up-dry-run-smoke.md`: passed, reported missing host `tun0`.
- Remote checks / CI:
  - Status: not available before push.

## Issues
### Issue U-01: Host-namespace VPN egress missing on Deck
- Description: `deck-hotspot-vpn-up.sh --dry-run` found no `tun0` in the Deck host namespace.
- Evidence: `verification/up-dry-run-smoke.md` reports `warning: vpn iface missing: tun0` and notes the existing container may keep TUN inside the container.
- Why unresolved: Mutating/reworking the Deck VPN runtime was outside this preparation slice and needs a bounded decision.
- Needed next: choose host-network OpenVPN/vpnkit client runtime or expose a host-routable egress path from the existing container before `up --apply`.

## Verdict
- Status: partial
- Goal state: scripts prepared; live gateway not achieved.
- Final readiness: ready for next implementation step, not ready for mutating hotspot apply.
- Summary: The safe script framework is in place with durable reports and rollback, but Deck host egress must be fixed before applying hotspot NAT/kill-switch.

## Next-agent brief
- Objective: Make a Deck host-namespace VPN egress interface available without disrupting existing `vpnkit` unnecessarily.
- Target: existing `scripts/vpnkit-steamdeck-podman.sh`/Deck Podman runtime or a new host-network client container path.
- Settled already: one-adapter `wlan0` hotspot is primary; do not touch ASUS; prepared gateway scripts should be reused.
- Boundaries: no secrets/log contents in output; no generated reports committed; rollback required for runtime mutation.
- Verification target: `ip link show tun0` on Deck host, Deck route/ping/curl through VPN, then `deck-hotspot-vpn-up.sh --dry-run` without the `tun0` blocker.
