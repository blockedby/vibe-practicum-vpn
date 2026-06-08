# Acceptance audit plan

Audit the completed urgent production full-tunnel TUN fix against the plan and existing evidence, focusing on:

1. Durable source support for TUN/full-tunnel mode.
2. Both production servers (`vibe-practicum`, `moscow-tiger`) running `VPNKIT_ROUTING_MODE=tun`.
3. Safe mutation/rollback handling and `OVPN_CIDR` correction.
4. Runtime checks: SSH, container, UDP 1194, OpenVPN, sing-box, `sb-tun0`, policy routing, route table.
5. Failover DNS: 2 A records and both endpoints reachable.
6. Failover `phone.ovpn` isolated-client checks for domain, endpoint1, endpoint2 including route via `tun0`, DNS, HTTPS, literal-IP HTTPS, `ping 1.1.1.1`, and `ping 8.8.8.8`.
7. Secret/private endpoint leakage review across provided reports.

Evidence sources to inspect:
- `reports/full-tunnel-fix-slice.md`
- `final-report.md`
- `verification/source-local.md`
- `verification/production-runtime.out`
- `verification/failover-dns.md`
- `verification/profile-domain.out`
- `verification/profile-endpoint1.out`
- `verification/profile-endpoint2.out`
- `verification/root-final-profile-rerun.out`
