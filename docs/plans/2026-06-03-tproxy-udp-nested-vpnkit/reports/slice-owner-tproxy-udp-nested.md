# Slice owner report: live isolated TPROXY/UDP validation

## Task
- Mission: run the approved live isolated validation after local TPROXY lab success.
- Target: isolated vpnkit server/client on vibe-practicum and isolated remote client on moscow-tiger.
- Boundaries: no production container mutation, no Steam Deck, no generated profiles/logs/secrets/private endpoint values committed or reported.
- Done when: live isolated OpenVPN/UDP smoke passes or concrete blockers are recorded, cleanup is complete, and production-untouched evidence is captured.

## Context
- Slice: Live isolated validation after local tproxy lab success.
- Task package: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit`.
- Worktree/branch: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-tproxy-udp-nested` / `vpnkit-tproxy-udp-nested`.
- PR: https://github.com/blockedby/vibe-practicum-vpn/pull/18.
- Verification artifact: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/live-isolated.md`.

## Spec compliance
- Private endpoint sourcing: done; `config/private-endpoints.local.env` was sourced with the approved pattern and not printed.
- vibe-practicum isolated server/client: done; project `vpnkit_tproxy_live_21195`, server `vpnkit_tproxy_live_21195-vpnkit-1`, port `21195/udp`, same-host client passed.
- moscow-tiger isolated client: done; project `vpnkit_tproxy_live_21195_moscow_client`, remote client passed against the isolated server.
- Nested/UDP behavior: partial; live outer OpenVPN UDP tunnel and UDP DNS over tunnel passed, and non-DNS UDP TPROXY rule/listener was present. Full inner VPN-over-VPN was not safely performed because the isolated bundle only had one generated test-client identity/profile; simultaneous inner reuse would not prove a clean independent nested client.
- Production untouched: done; production `vpnkit` safe metadata stayed running with restart count `0` and unchanged start time before/after.
- Cleanup: done; isolated containers/volumes/networks/temp paths removed; nothing retained intentionally.
- Secrets safety: done; no generated `.ovpn`, logs, rendered configs, private endpoint values, or real endpoint values are tracked in the report.

## Acceptance verification
- AC5 vibe-practicum isolated test:
  - Covered by: isolated Compose server/client run on vibe-practicum.
  - Result: passed.
  - Evidence: `verification/live-isolated.md` records OpenVPN connected, UDP DNS `NOERROR`, HTTPS hostname `200`, literal-IP HTTPS `200`.
- AC6 moscow-tiger isolated client-test:
  - Covered by: isolated client-test container on moscow-tiger connecting to vibe-practicum test port `21195/udp`.
  - Result: passed.
  - Evidence: `verification/live-isolated.md` records OpenVPN connected, UDP DNS `NOERROR`, HTTPS hostname `200`, literal-IP HTTPS `200`.
- AC2 nested/UDP proof:
  - Covered by: live outer OpenVPN UDP tunnel from two hosts plus UDP DNS/counter/listener evidence.
  - Result: partial with explicit limitation.
  - Evidence: `OVPN_TPROXY_DNS` counter incremented, TCP redirect counter incremented, UDP `2082` TPROXY listener/rule present; full inner tunnel not run due single-client-profile safety limitation.
- AC7 reporting/cleanup/production untouched:
  - Covered by: live verification artifact and production safe metadata.
  - Result: passed.
  - Evidence: exact isolated names/port and cleanup status in `verification/live-isolated.md`; production `vpnkit` unchanged.
- AC8 no secrets committed/revealed:
  - Covered by: sanitized docs and gitignored private env.
  - Result: passed.
  - Evidence: no private env/profile/log/rendered config added to git status; docs redact real endpoint values.

## System readiness
- Runtime / deployment wiring: ready for PR review with local and live isolated validation evidence, except full independent inner tunnel remains unproven.
- Config / env / secrets: private env used only locally; no tracked secret changes.
- Production safety: production untouched by evidence.

## Verification run
- Local automated checks: previously passed after implementation; no code changes were made during live validation.
- Live targeted checks:
  - vibe-practicum isolated server/client: passed.
  - moscow-tiger isolated remote client: passed.
  - isolated server TPROXY/UDP listener/counter check: passed/present.
  - production untouched metadata: passed.
- Remote checks / CI: not checked in this slice continuation after docs update; branch push pending.

## Issues
### U-1: Full independent inner VPN-over-VPN proof not performed
- Description: The live validation proved outer OpenVPN over UDP and UDP traffic through the tunnel, but did not start a separate inner VPN tunnel.
- Evidence: only one generated `test-client.ovpn` identity/profile was available in the isolated bundle.
- Why unresolved: a simultaneous inner tunnel using the same client identity/profile could collide with or invalidate the outer session and would not prove an independent nested client path.
- Needed next: add a safe inner-client harness with a distinct generated client identity/profile, then run inner VPN-over-VPN over the already-established outer tunnel.

## Side findings
- No non-blocking follow-up issue was created in this continuation; U-1 is a current acceptance limitation for full nested proof.

## Verdict
- Status: partial success.
- Goal state: live isolated outer UDP validation achieved on both hosts; full inner VPN-over-VPN remains unproven for a concrete safety/harness reason.
- Final readiness: ready for PR review of TPROXY/UDP runtime plus live isolated smoke evidence, not final-ready for a claim of full independent nested VPN-over-VPN.

## Next-agent brief
- Objective: if full AC2 closure is required, create a distinct inner-client profile/cert and safe harness, then run inner OpenVPN through the established outer tunnel without touching production containers.
- Boundaries: keep all profiles/secrets/logs gitignored and use isolated names/ports/resources only.
- Verification target: outer tunnel active, inner tunnel active over outer path, UDP traffic through inner tunnel, cleanup and production untouched evidence.
