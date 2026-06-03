# Slice owner report: non-DNS UDP TPROXY forwarding continuation

## Task
- Mission: fix non-DNS UDP TPROXY forwarding for nested OpenVPN handshakes.
- Target: sing-box tproxy routing/template and vpnkit isolated validation.
- Boundaries: no production container mutation, no Steam Deck, no generated profiles/logs/secrets/private endpoint values committed or reported.
- Done when: inner OpenVPN-over-OpenVPN passes, or safe continuation stops on a concrete external/safety blocker.

## Context
- Slice: Fix non-DNS UDP TPROXY forwarding so inner OpenVPN-over-OpenVPN succeeds.
- Task package: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit`.
- Worktree/branch: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-tproxy-udp-nested` / `vpnkit-tproxy-udp-nested`.
- PR: https://github.com/blockedby/vibe-practicum-vpn/pull/18.
- Verification artifacts: `verification/inner-nested.md`, `verification/tproxy-udp-debug-2026-06-03-nondns.md`.

## Spec compliance
- Non-DNS UDP route defect: resolved in code for the identified sing-box route policy risk. TPROXY UDP traffic now bypasses sniffing and routes directly to `selected-native-out`, avoiding protocol sniff delay/consumption on opaque UDP such as OpenVPN handshakes.
- Default redirect mode unchanged: done; only `config/sing-box/config.tproxy.json.template` and its template test changed.
- Local tproxy DNS/TCP smoke preserved: done; isolated Docker lab project `vpnkit_tproxy_udp_nested_lab2` on `21196/udp` passed OpenVPN connect, UDP DNS, HTTPS hostname, and literal-IP HTTPS.
- Full live nested validation: not rerun; local private endpoint file currently contains placeholder SSH host data for the VPS alias, so live-host mutation/validation is unsafe and blocked before any remote changes.
- Production untouched: done for this continuation; no production containers were touched locally or remotely.
- Secrets safety: done; no private values/profile/log contents recorded.

## Acceptance verification
- AC1 / tproxy runtime wiring:
  - Covered by: `bash tests/vpnkit-singbox-template-test.sh`; `sing-box check` on rendered tproxy config.
  - Result: passed.
  - Evidence: template test printed `vpnkit sing-box templates ok`; `sing-box check` exited 0 with deprecation warnings only.
- AC2 / nested VPN-over-VPN:
  - Covered by: pending live nested rerun after endpoint access is valid.
  - Result: blocked.
  - Evidence: `config/private-endpoints.local.env` loaded but `ssh` to configured VPS alias failed because it is still placeholder/unresolvable; no live test was attempted.
- AC3 / default production mode remains unchanged:
  - Covered by: diff review; redirect template untouched.
  - Result: passed.
  - Evidence: changes are limited to tproxy template/test plus task-package docs.
- AC4 / local Docker lab before live mutation:
  - Covered by: isolated project `vpnkit_tproxy_udp_nested_lab2`.
  - Result: passed.
  - Evidence: OpenVPN connected; UDP DNS `NOERROR`; HTTPS hostname `200`; literal-IP HTTPS `200`; cleanup removed project containers/volumes/network.
- AC7/AC8 / reporting and public safety:
  - Covered by: this report and verification artifact.
  - Result: passed for local continuation; live exact names not allocated because blocked before live start.

## System readiness
- Runtime / deployment wiring: partially ready; local tproxy smoke and config checks pass, but full live nested AC2 remains unproven after the new fix.
- Config / env / secrets: blocked for live validation by placeholder/unresolvable VPS SSH host in gitignored local endpoint file.
- Production safety: production untouched; no remote Docker commands succeeded or mutated state.

## Verification run
- Local checks:
  - `bash tests/vpnkit-singbox-template-test.sh` — PASS.
  - `bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh` — PASS.
  - `go test ./...` — PASS.
  - `go vet ./...` — PASS.
  - `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn` — PASS.
  - Rendered tproxy `sing-box check` — PASS with deprecation warnings only.
- Local Docker lab:
  - `vpnkit_tproxy_udp_nested_lab2` on `21196/udp` — PASS for OpenVPN, UDP DNS, HTTPS hostname, literal-IP HTTPS; cleanup done.
- Live validation:
  - Not run; endpoint SSH host from local private env is placeholder/unresolvable.
- Remote checks / CI:
  - Push pending after this report update.

## Issues
### R-1: Opaque/non-DNS UDP was sent through sniffing before routing
- Description: The tproxy route policy sniffed `vpnkit-tproxy-in` traffic before routing. For opaque UDP such as OpenVPN, sniffing is unnecessary and can delay or consume first packets before outbound association.
- Evidence: Previous nested failure had packets reaching the tproxy rule but not the inner server; route policy had no UDP-specific route before the sniff rule.
- Resolution: Added a tproxy inbound UDP route rule before sniffing: `{ "inbound": "vpnkit-tproxy-in", "network": "udp", "action": "route", "outbound": "selected-native-out" }`; added template assertion for rule presence/order.

### U-1: Full live inner OpenVPN-over-OpenVPN rerun blocked by invalid local endpoint config
- Description: The new code path has not been proven by isolated live nested validation because the gitignored private endpoint file available in this worktree currently points the VPS SSH host to an unresolved placeholder alias.
- Evidence: After sourcing `config/private-endpoints.local.env` without printing values, `ssh -o BatchMode=yes -o ConnectTimeout=5 "$VPNKIT_VPS_SSH_HOST" ...` failed with unresolved placeholder hostname; no live Docker mutation was attempted.
- Why unresolved: live validation requires valid private endpoint/SSH values, and using placeholders would violate the approved live-test safety path.
- Needed next: provide/fix the local private endpoint file or run from an environment where `VPNKIT_VPS_SSH_HOST` and the remote client host are valid, then rerun the isolated nested harness.

## Side findings
- No non-blocking follow-up issues were created.

## Verdict
- Status: blocked after scoped fix and local verification.
- Goal state: partially achieved; code/config fix is in place and local tproxy smoke passes, but AC2 full inner VPN-over-OpenVPN remains unverified live due to endpoint access blocker.
- Final readiness: not ready for merge as a proven nested OpenVPN-over-OpenVPN support claim.

## Next-agent brief
- Objective: rerun isolated live nested validation after private endpoint config is corrected.
- Target: PR #18 branch `vpnkit-tproxy-udp-nested`; verify `config/sing-box/config.tproxy.json.template` UDP pre-sniff route carries inner OpenVPN handshakes.
- Settled already: automated checks pass; local Docker tproxy smoke passes; production must remain untouched.
- Boundaries: no production containers, no Steam Deck, isolated names/ports/resources only, no secrets/log/profile contents in tracked artifacts.
- Verification target: outer `tun0` active, route to inner endpoint via `tun0`, inner `tun1` active, UDP DNS/HTTPS through inner where feasible, counters/listeners captured, cleanup complete.
