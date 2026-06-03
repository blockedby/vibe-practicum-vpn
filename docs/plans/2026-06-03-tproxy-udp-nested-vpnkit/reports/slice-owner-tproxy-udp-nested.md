# Slice owner report: AC2 inner/nested TPROXY/UDP validation

## Task
- Mission: close or concretely block AC2 full inner VPN-over-VPN validation.
- Target: isolated vpnkit outer/inner servers on vibe-practicum plus isolated nested client on moscow-tiger.
- Boundaries: no production container mutation, no Steam Deck, no generated profiles/logs/secrets/private endpoint values committed or reported.
- Done when: full inner OpenVPN-over-OpenVPN passes, or a concrete blocker is proven after a real isolated attempt.

## Context
- Slice: AC2 full inner VPN-over-VPN validation.
- Task package: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit`.
- Worktree/branch: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-tproxy-udp-nested` / `vpnkit-tproxy-udp-nested`.
- PR: https://github.com/blockedby/vibe-practicum-vpn/pull/18.
- Verification artifacts: `verification/live-isolated.md`, `verification/inner-nested.md`.

## Spec compliance
- Focused inner validation attempt: done; ran an actual nested harness rather than relying on the prior one-profile limitation alone.
- Isolated resources only: done; outer `vpnkit_tproxy_nested_outer_21202` on `21202/udp`, inner `vpnkit_tproxy_nested_inner_21203` on `21203/udp`, client `vpnkit_tproxy_nested_moscow_client_21202_21203`.
- Inner routed through outer: done; client route to the inner endpoint after outer tunnel establishment showed `dev tun0`.
- Full inner VPN-over-VPN: blocked; inner `tun1` did not establish.
- UDP path evidence: partial/blocking; outer non-DNS UDP TPROXY rule incremented `9` packets / `738` bytes during the inner OpenVPN attempt, but the inner server accepted no OpenVPN client.
- Production untouched: done; production `vpnkit` stayed running with restart count `0` and unchanged start time before/after.
- Cleanup: done; isolated containers/projects/volumes/networks/temp paths removed.
- Secrets safety: done; endpoints/profile contents/logs remain untracked and sanitized.

## Acceptance verification
- AC2 full inner VPN-over-VPN:
  - Covered by: isolated nested harness with outer OpenVPN active, inner endpoint routed via outer `tun0`, and second OpenVPN client attempt on `tun1` to a second isolated server.
  - Result: blocked.
  - Evidence: `verification/inner-nested.md`; outer came up, inner route used `tun0`, outer UDP TPROXY counter incremented, but `tun1` never appeared and inner server showed no client acceptance.
- AC7 reporting/cleanup/production untouched:
  - Covered by: `verification/inner-nested.md` resource list, cleanup status, production metadata.
  - Result: passed.
  - Evidence: production `vpnkit` metadata unchanged before/after/after-cleanup; all isolated resources removed.
- AC8 no secrets committed/revealed:
  - Covered by: sanitized verification docs and git status review before commit.
  - Result: passed.
  - Evidence: no profile/log/private env contents are tracked or included.

## System readiness
- Runtime / deployment wiring: not final-ready for full nested UDP OpenVPN claim; outer UDP smoke remains validated, but non-DNS UDP TPROXY did not carry an inner OpenVPN handshake in the nested harness.
- Config / env / secrets: private inputs used only locally; no tracked secret changes.
- Production safety: production untouched by evidence.

## Verification run
- Live targeted checks:
  - Outer isolated OpenVPN tunnel from moscow-tiger to vibe-practicum `21202/udp`: passed (`OUTER_UP`).
  - Route to inner endpoint while outer tunnel was active: passed (`dev tun0`).
  - Inner OpenVPN tunnel over outer to isolated server `21203/udp`: failed/blocked (`tun1` absent).
  - Outer non-DNS UDP TPROXY rule during inner attempt: observed (`9` packets / `738` bytes).
  - Cleanup and production metadata: passed.
- Local automated checks: not rerun; this continuation changed task-package docs only.
- Remote checks / CI: branch push pending in this continuation.

## Issues
### U-1: Full inner OpenVPN-over-OpenVPN blocked by non-DNS UDP TPROXY transport
- Description: A real nested attempt routed the inner OpenVPN UDP transport through the established outer tunnel, but the inner OpenVPN handshake did not complete.
- Evidence: `ip route get <inner-endpoint>` showed `dev tun0`; outer server non-DNS UDP TPROXY counter incremented `9` packets / `738` bytes; inner `tun1` never appeared; inner server had no accepted client session.
- Why unresolved: safe continuation now requires debugging/fixing non-DNS UDP TPROXY forwarding semantics for OpenVPN handshake traffic, not merely rerunning the available profile.
- Needed next: inspect sing-box tproxy UDP handling and route/outbound policy for arbitrary UDP, add targeted harness/tests for non-DNS UDP over TPROXY, then rerun the nested validation.

## Side findings
- No non-blocking follow-up issues were created; U-1 is a current-goal blocker for AC2 closure.

## Verdict
- Status: blocked.
- Goal state: AC2 full inner VPN-over-VPN not achieved.
- Final readiness: not ready for a full nested OpenVPN-over-OpenVPN support claim; ready only for the previously proven outer UDP smoke scope.
- Summary: The slice made a concrete isolated inner validation attempt and proved the inner OpenVPN packets reached the outer non-DNS UDP TPROXY path, but the inner tunnel did not establish.

## Next-agent brief
- Objective: fix or explain non-DNS UDP TPROXY forwarding for OpenVPN handshake traffic, then rerun isolated nested validation.
- Target: `docker/vpnkit/setup-routing.sh`, sing-box tproxy template/route/outbound policy, and isolated nested harness.
- Settled already: local and live outer UDP smoke pass; inner route via outer can be achieved with distinct endpoint spelling; production must remain untouched.
- Boundaries: no production mutation, no Steam Deck, all generated profiles/logs/endpoints stay private and temporary.
- Verification target: outer `tun0` active, route to inner endpoint via `tun0`, inner `tun1` active, UDP DNS/HTTPS through inner, counters/listeners captured, cleanup complete.
