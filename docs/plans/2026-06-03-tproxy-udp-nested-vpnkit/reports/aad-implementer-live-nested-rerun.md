## Task
- Mission: Rerun isolated live nested OpenVPN-over-OpenVPN validation after UDP pre-sniff route fix.
- Target: vibe-practicum isolated vpnkit servers + moscow-tiger isolated client harness.
- Boundaries: no production container mutation; no Steam Deck; no secrets/profile contents/private endpoints in tracked artifacts.

## Acceptance verification
- AC2 nested UDP/OpenVPN-over-OpenVPN:
  - Result: blocked/not proven.
  - Evidence: `verification/inner-nested.md` rerun section. Isolated servers started on `21224/udp` and `21225/udp`, but outer `tun0` did not establish; no route-to-inner or `tun1` proof was possible.

## System readiness
- Production safety: passed. `vpnkit` stayed running with restart count `0` and unchanged start time before/after.
- Cleanup: passed. Isolated resources and temp paths removed; nothing intentionally retained.

## Issues
### U-01: Matching live test profile unavailable for rerun harness
- Description: The rerun could not establish the outer tunnel using the available generated local profile against isolated live servers bootstrapped from live rendered config.
- Evidence: outer `tun0` never appeared; attempted safe reconstruction of matching test-client material encountered a rendered PKI path without `ignat.crt`/`ignat.key`.
- Why unresolved: continuing broad private secret-path probing would risk exposing/handling private material beyond the narrow validation scope.
- Needed next: operator/slice owner should provide or generate a matching isolated live test-client profile through the repo's gitignored secret workflow, then rerun the same isolated nested harness.

## Verdict
- Status: blocked.
- Goal state: AC2 not achieved in this rerun.
- Final readiness: not ready for AC2 closure; production untouched and cleanup complete.
