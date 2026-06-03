# Public non-DNS UDP vpnkit TPROXY variants matrix

Date: 2026-06-03
Owner: aad-slice-owner
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-tproxy-udp-nested`
Branch: `vpnkit-tproxy-udp-nested`

## Safety and scope

- `config/private-endpoints.local.env` is readable, but no values are printed here.
- Nested `aad-implementer` delegation was blocked by Pi max subagent depth, so this owner could not hand the command-heavy live variant matrix to an implementer.
- No new live resources were started by this continuation. Therefore there were no new isolated containers/networks/volumes/temp paths to clean up.
- Steam Deck, production `vpnkit`, and `current-vpnkit-1` were not touched by this continuation.
- This artifact reuses prior committed baseline public echo evidence only where explicitly marked; it does not claim a fresh seven-variant live run.

## Prior baseline evidence reused for Variant 1

Source artifact: `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/live-validation-after-private-bypass.md`.

- Reduced public echo resource names/ports from prior run: outer project `vpnkit_public_echo_outer_21473`, outer OpenVPN port `21473/udp`, same-host client `vpnkit-public-echo-client-21473_21475`, echo process on moscow-tiger `21475/udp`; all were cleaned up in that prior run.
- Result: route to echo endpoint was via outer `tun0`; public UDP echo timed out.
- Counters: generic non-private UDP TPROXY incremented `1 packet / 44 bytes`; private UDP bypass counters stayed zero.
- Interpretation: generic public UDP entered the TPROXY path and failed to produce a response; this is distinct from the passing private UDP bypass path.

## Variant matrix

| # | Variant | Config delta / implementation mode | Live echo result | Route proof | Counters / packet evidence | Sing-box / tcpdump summary | Cleanup | Status |
|---:|---|---|---|---|---|---|---|---|
| 1 | Current tproxy public UDP baseline | Existing source behavior; prior live reduced public echo evidence reused, not a fresh run in this continuation. | Timeout. | Prior run recorded route to public echo endpoint via client `tun0`. | Generic public UDP TPROXY incremented `1 packet / 44 bytes`; private bypass zero. | Prior artifact summarized no successful echo response; raw logs not committed. | Prior resources removed. | FAIL / evidenced by prior committed run. |
| 2 | Explicit tproxy inbound `network: [tcp, udp]` + `udp_timeout` | Temp-only config syntax probe against sing-box 1.13.12; not deployed live. | Not run live. | Not captured. | Not captured. | Local `sing-box check` accepts the added fields when repo's existing deprecation env allowances are set, so this variant remains feasible but untested live. | Temp local rendered config removed. | NOT COMPLETED. |
| 3 | Route-options `udp_connect` / `udp_timeout` before route | Prior local private-echo investigation tried route-options and it did not fix private TPROXY; no fresh public live run. | Not run live. | Not captured for public target. | Not captured for public target. | Prior artifact says route-options did not make reduced private echo pass. | No new resources. | NOT COMPLETED for public UDP. |
| 4 | Force UDP route to `direct-out` vs `selected-native-out` | Not run in this continuation. | Not run. | Not captured. | Not captured. | Not captured. | No new resources. | NOT COMPLETED. |
| 5 | nftables TPROXY variant | Not run in this continuation. | Not run. | Not captured. | Not captured. | Not captured. | No new resources. | NOT COMPLETED. |
| 6 | Sing-box TUN-mode canary for UDP | Not run in this continuation. | Not run. | Not captured. | Not captured. | Not captured. | No new resources. | NOT COMPLETED. |
| 7 | Pragmatic port-based UDP bypass for common tunnel ports | Not run in this continuation. | Not run. | Not captured. | Not captured. | Not captured. | No new resources. | NOT COMPLETED. |

## Fresh source checks run by owner

All checks below passed after docs/progress changes only:

```text
bash tests/vpnkit-setup-routing-test.sh: pass
bash tests/vpnkit-singbox-template-test.sh: pass
bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh: pass
go test ./...: pass
git diff --check: pass
```

## Open blocker

### U-PUBLIC-UDP-01: Fresh full public UDP variants matrix not executed

- Description: The requested seven-variant live investigation was not completed. Only the prior baseline timeout evidence is available, plus a local syntax check that Variant 2's tproxy inbound field delta is accepted by sing-box 1.13.12.
- Why unresolved: Pi subagent max-depth blocked delegation to `aad-implementer`, and the owner did not safely reproduce the full live harness directly within this continuation.
- Needed next: run the seven variants from a top-level owner/implementer context or a shallower AAD invocation that can execute the command-heavy isolated live harness, then replace this partial matrix with fresh per-variant evidence.
