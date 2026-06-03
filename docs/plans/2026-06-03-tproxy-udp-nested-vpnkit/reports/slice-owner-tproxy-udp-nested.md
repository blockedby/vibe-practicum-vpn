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

---

# Slice owner continuation: matching-bundle nested validation

## Task
- Mission: continue TPROXY/UDP nested VPN-over-VPN validation using only the matching gitignored local bundle already present in the worktree.
- Target: isolated vibe-practicum outer+inner vpnkit servers and isolated moscow-tiger nested client.
- Boundaries: no production container mutation; no Steam Deck; no broad secret probing; no profile/PKI/rendered config/private endpoint contents printed or committed; rewrite only `remote` lines in temp copied profiles.

## Context
- Task package: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit`.
- Worktree/branch: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-tproxy-udp-nested` / `vpnkit-tproxy-udp-nested`.
- Delegated execution: `aad-implementer` report `reports/aad-implementer-matching-bundle-nested.md`.
- Verification artifact: `verification/inner-nested-matching-bundle.md`.

## Spec compliance
- Matching-material constraint: done. The rerun used only the specified gitignored bundle and rewrote only temporary profile `remote` lines.
- Isolated live validation: done with fresh isolated names/ports/resources: `vpnkit_match_outer_21342` on `21342/udp`, `vpnkit_match_inner_21343` on `21343/udp`, shared network `vpnkit_match_net_21342_21343`, and moscow-tiger client `nested-match-21342`.
- Full inner OpenVPN-over-OpenVPN: failed/not achieved. Outer tunnel established and inner route used `tun0`, but inner `tun1` did not appear.
- Production safety and cleanup: done. Production `vpnkit` safe metadata stayed unchanged before/after, and all isolated resources/temp paths were removed.

## Acceptance verification
- AC2 / nested UDP OpenVPN-over-OpenVPN:
  - Covered by: matching-bundle isolated live nested harness.
  - Result: failed with decisive blocker evidence.
  - Evidence: `OUTER_UP`; `ip route get <inner-container-ip>` showed `dev tun0`; inner OpenVPN logged TLS handshake timeout; outer non-DNS UDP TPROXY counter reached `15 packets / 1230 bytes`; outer-to-inner and inner `udp/1194` tcpdump captures had no packet lines; no inner server accepted client.
- AC5/AC6 / isolated live-host validation without production mutation:
  - Covered by: before/after Docker metadata and cleanup checks.
  - Result: passed for safety/isolation, failed for inner tunnel behavior.
  - Evidence: production `vpnkit` remained `status=running restart=0 started=2026-06-02T13:47:35.235471647Z`; isolated projects/containers/network/image/temp paths removed.
- AC8 / secret safety:
  - Covered by: report/artifact review and scoped execution report.
  - Result: passed.
  - Evidence: no secret/profile/PKI/private endpoint values recorded; only sanitized directives/counters/log status included.

## System readiness
- Runtime / deployment wiring: not ready for a claim of full nested OpenVPN-over-OpenVPN support.
- Config / env / secrets: sufficient matching test material existed for this rerun; no remaining material-mismatch blocker.
- Production readiness: production untouched, but AC2 failure is a current-goal runtime blocker.

## Verification run
- Matching-bundle isolated live nested harness: FAIL at inner tunnel establishment.
- Production untouched check: PASS.
- Cleanup check: PASS.
- Source checks: not rerun in this continuation because no production source/config files changed; only task-package evidence files were updated.

## Issues
### U-1: Non-DNS UDP TPROXY packets do not egress toward the inner OpenVPN server
- Description: With matching server/client material, the inner OpenVPN UDP attempt enters the outer tunnel and hits the outer TPROXY rule, but no packet lines are observed leaving the outer container toward the inner container or arriving at the inner OpenVPN server.
- Evidence: `verification/inner-nested-matching-bundle.md`: outer `OUTER_UP`; route to inner via `dev tun0`; outer non-DNS UDP TPROXY counter `15 packets / 1230 bytes`; outer-to-inner and inner `udp/1194` tcpdump captured no packet lines; inner client TLS handshake timed out and `tun1` never appeared.
- Why unresolved: current runtime behavior still fails after the earlier route-policy correction; further debugging/fix is needed in sing-box TPROXY UDP association/egress or vpnkit routing policy.
- Needed next: investigate why sing-box/tproxy consumes or fails to forward non-DNS UDP associations; a reduced UDP echo harness on the shared network may isolate sing-box egress before another full OpenVPN nested run.

## Side findings
- Non-blocking follow-up candidates from implementer: reduced UDP echo harness and sing-box TPROXY UDP association/egress investigation. These are not separate follow-ups yet because they are directly part of resolving U-1.

## Verdict
- Status: blocked/failed for AC2, with decisive evidence.
- Goal state: not achieved for full inner OpenVPN-over-OpenVPN.
- Final readiness: not ready for merge as proven nested UDP support; safe to continue from the recorded blocker.

## Next-agent brief
- Objective: fix or decisively classify the non-DNS UDP TPROXY egress failure.
- Target: outer vpnkit TPROXY UDP path after packets match `OVPN_TO_SINGBOX` and enter sing-box `vpnkit-tproxy-in`.
- Settled already: matching profile material is no longer the blocker; outer tunnel works; route to inner goes via `tun0`; packets increment outer TPROXY counter; no egress/ingress to inner is observed.
- Boundaries: keep using isolated resources only; do not touch production containers; do not print/commit secrets/logs/generated profiles.
- Verification target: either inner `tun1` establishes through outer `tun0`, or packet-level evidence proves the precise failing component/protocol behavior.
