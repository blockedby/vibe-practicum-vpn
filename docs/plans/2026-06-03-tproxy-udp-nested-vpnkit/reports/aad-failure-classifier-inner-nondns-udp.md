FAILURE_ID: inner-nondns-udp
TASK_PACKAGE: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit
REPORT_PATH: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/aad-failure-classifier-inner-nondns-udp.md
CLASSIFICATION: CODE_BUG
CONFIDENCE: high
ROOT_CAUSE: The nested harness proved the inner OpenVPN UDP traffic was routed through the established outer tunnel and hit the outer server's non-DNS UDP TPROXY path, but the inner OpenVPN session never established and the inner server accepted no client. That points to a defect in the non-DNS UDP TPROXY forwarding/runtime wiring for arbitrary UDP handshake traffic, not a test failure or missing environment.
EVIDENCE:
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/inner-nested.md`: outer tunnel came up, `ip route get <inner-endpoint>` showed `dev tun0`, inner `tun1` never appeared, outer non-DNS UDP TPROXY counter incremented `9` packets / `738` bytes, and the inner server saw no accepted OpenVPN session.
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/slice-owner-tproxy-udp-nested.md`: records the same blocker as a concrete isolated nested attempt, with full inner VPN-over-VPN blocked by non-DNS UDP TPROXY transport.
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/tproxy-udp-debug.md`: the existing local UDP TPROXY path passes for DNS/HTTPS, so this failure is specifically in the nested non-DNS UDP OpenVPN transport case rather than a general lab outage.
NEXT_OWNER_ACTION: Route to the implementation owner (`aad-implementer` / slice owner) to debug the non-DNS UDP TPROXY forwarding path for OpenVPN handshake traffic, then rerun the isolated nested validation; do not treat this as an infra or test issue.
RETRY_ALLOWED: yes
MODEL_ESCALATION: none