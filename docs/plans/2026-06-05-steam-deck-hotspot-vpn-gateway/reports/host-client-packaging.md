## Task
- Mission: Package a Git-ready Steam Deck host-network OpenVPN client runtime.
- Target: `steam-deck/hotspot-client/` plus repo docs/gitignore.
- Boundaries: Repo changes only; no Steam Deck/router mutation; no real profiles, endpoints, secrets, or logs committed.
- Done when: Operator can pull the branch on Deck, place a local `.ovpn`, run install/up/test/down scripts, and get durable redacted logs.
- Expected evidence: Files added, syntax/runtime-readiness checks, and exact operator commands.

## Context
- Thread: Steam Deck one-adapter hotspot VPN gateway.
- Slice: Host-namespace VPN egress packaging.
- Task package: `docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway`
- Report path: `docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway/reports/host-client-packaging.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn`
- Branch: `feat/steam-deck-hotspot-client`
- Verify scope: Local syntax/static checks only; no Deck mutation.

## Spec compliance
- Requirement / AC: Separate Steam Deck folder with compose/runtime packaging.
  - Status: done
  - Evidence: `steam-deck/hotspot-client/compose.yaml`, `Containerfile`, `README.md`, `.env.example`.
  - Gap if any: none.
- Requirement / AC: Host-network OpenVPN client creates host `tun0`.
  - Status: prepared
  - Evidence: compose/run config uses `network_mode: host`, `NET_ADMIN`, `NET_RAW`, and `/dev/net/tun`; `scripts/up.sh` waits for configured `tun0`.
  - Gap if any: actual Deck run not performed in this repo-only step.
- Requirement / AC: Existing `vpnkit` container is not touched.
  - Status: done
  - Evidence: default container name is `vpnkit-host-ovpn-client`; `scripts/up.sh` only logs if `vpnkit` exists and removes/replaces only `$CONTAINER`.
  - Gap if any: none.
- Requirement / AC: Operator workflow is git pull on Deck then run scripts.
  - Status: done
  - Evidence: `steam-deck/hotspot-client/README.md` documents `git switch`, `git pull`, profile placement, `install/up/test/down`.
  - Gap if any: none.
- Requirement / AC: Public-safe config.
  - Status: done
  - Evidence: `.env.example` contains placeholders only; `.gitignore` ignores local `.env`, `local/`, `logs/`, `reports/`; scripts redact IPs/endpoints.
  - Gap if any: none.

## Acceptance verification
- AC1: Shell scripts are syntactically valid.
  - Covered by: `bash -n scripts/*.sh steam-deck/hotspot-client/scripts/*.sh`
  - Result: passed
  - Evidence: command exited 0.
- AC2: Python control panel still compiles after earlier default-host safety edit.
  - Covered by: `python3 -m py_compile scripts/vpnkit-control-panel.py`
  - Result: passed
  - Evidence: command exited 0.
- AC3: Compose file contains required host VPN runtime wiring.
  - Covered by: static token check for `network_mode: host`, `NET_ADMIN`, `/dev/net/tun:/dev/net/tun`, `vpnkit-host-ovpn-client`.
  - Result: passed
  - Evidence: `compose_sanity=ok`.
- AC4: Install script exposes operator help without mutation.
  - Covered by: `steam-deck/hotspot-client/scripts/install.sh --help`
  - Result: passed
  - Evidence: help text printed.

## System readiness
- Routes / registration: not applicable for repo-only packaging.
- Services / APIs: not applicable.
- Config / env / secrets: done; `.env.example` only, real `.env` and `.ovpn` ignored.
- Permissions / access: prepared; runtime supports `VPNKIT_DECK_PODMAN="sudo podman"` if rootless Podman cannot create host TUN.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: prepared; actual Deck runtime verification remains required after pull.

## Verification run
- Local / targeted checks:
  - `bash -n scripts/*.sh steam-deck/hotspot-client/scripts/*.sh`: passed.
  - `python3 -m py_compile scripts/vpnkit-control-panel.py`: passed.
  - compose static sanity check: passed.
  - `steam-deck/hotspot-client/scripts/install.sh --help`: passed.
- Local / full checks:
  - `go test ./...`: not run; packaging-only shell/container change, no Go code changed.
- Remote checks / CI:
  - Status: not available before push.
  - Evidence: branch not pushed during this report.

## Issues
### Issue U-01: Actual host `tun0` not yet proven on Steam Deck
- Description: The package is ready, but no mutating Deck run was performed here.
- Evidence: Scope explicitly repo-only/no Deck mutation.
- Why unresolved: Requires operator-provided profile on Deck and a runtime start there.
- Needed next: Pull branch on Deck, place `local/client.ovpn`, run `./scripts/install.sh`, `./scripts/up.sh`, `./scripts/test.sh`.
- Depends on: operator profile placement and Deck Podman permissions.

## Side findings
- Blocking findings folded into active work: none.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: success
- Goal state: repo packaging achieved; live Deck runtime proof pending.
- Final readiness: ready for operator Deck pull/install; not yet ready to apply hotspot NAT until Deck `tun0` test passes.
- Summary: Steam Deck host OpenVPN client packaging is in git-ready form with public-safe config and rollback scripts.

## Next-agent brief
- Objective: Prove host `tun0` on Steam Deck, then proceed to hotspot dry-run.
- Target: `steam-deck/hotspot-client/` on the Deck.
- Settled already: Use separate `vpnkit-host-ovpn-client`; do not touch existing `vpnkit`; one-adapter hotspot remains primary.
- Boundaries: Do not commit real `.ovpn`, `.env`, logs, or private endpoint values.
- Verification target: `./scripts/test.sh` shows `vpn_iface=present`, route/ICMP/DNS/HTTPS/IP checks pass; then repo-root `scripts/deck-hotspot-vpn-up.sh --ssh-target deck --dry-run` no longer blocks on missing `tun0`.
- Expected output: Redacted report paths and pass/fail summary.
