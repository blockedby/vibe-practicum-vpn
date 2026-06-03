FAILURE_ID: local-tproxy-udp
TASK_PACKAGE: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit
REPORT_PATH: docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/aad-failure-classifier-local-tproxy-udp.md
CLASSIFICATION: CODE_BUG
CONFIDENCE: high
ROOT_CAUSE: The local isolated lab shows the implementation reaches the UDP TPROXY rule but does not produce a response back to the OpenVPN client. That points to an incomplete/incorrect runtime wiring issue in the tproxy UDP path (sing-box inbound/routing/readiness/kernel delivery), not a test or environment failure.
EVIDENCE:
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/slice-owner-tproxy-udp-nested.md`: OpenVPN client connects and receives routes, but UDP DNS times out while the server-side UDP TPROXY mangle counter increments.
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/slice.md`: `vpnkit_tproxy_udp_nested_lab` starts with tproxy listeners/rules present; `dig @8.8.8.8 example.com` times out; no live tests attempted.
- `docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/plan.md`: local Docker lab was the required first gate; it failed before any live-host mutation.
NEXT_OWNER_ACTION: Route back to the implementation owner (`aad-implementer` / slice owner) to debug the UDP tproxy runtime path in the isolated local lab only, focusing on sing-box UDP handling, DNS interception path, and kernel TPROXY delivery; do not move to live-host testing until this passes.
RETRY_ALLOWED: yes
MODEL_ESCALATION: none