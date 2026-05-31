## Task package
- Task name: Issue #9 OpenVPN dynamic clients through sing-box TPROXY/VLESS
- Task package: `docs/plans/2026-05-31-issue-9-openvpn-singbox-tproxy`
- Report path: `docs/plans/2026-05-31-issue-9-openvpn-singbox-tproxy/reports/acceptance-auditor.md`
- Acceptance plan path: `docs/plans/2026-05-31-issue-9-openvpn-singbox-tproxy/verification/acceptance-plan.md`

## Acceptance verdict
- Status: accepted with limitations
- Summary: Slice B is acceptable and the gated Slice C plan is safe to start, but root issue #9 is not fixed yet because AC3-AC6 still lack fresh active-client proof.

## Acceptance coverage
- AC1: Dynamic OpenVPN client `ignat` connects and receives a dynamic-pool IP.
  - Evidence present: live discovery + root verification reports.
  - Result: partial.
  - Gap: current lease known as `10.89.0.23`, but no active session during capture.

- AC2: Dynamic-pool OpenVPN traffic is captured by scoped TPROXY rules and locally delivered to `sing-box-vibe-router` on `:2082`; INPUT accepts marked packets from the pool.
  - Evidence present: iptables/routing/listener checks in live discovery.
  - Result: wiring passed, live traffic proof partial.
  - Gap: counters stayed at zero because the client was not active.

- AC3: DNS for the client is handled under sing-box rules in the final design; no hidden permanent direct/NAT DNS leak.
  - Evidence present: live config inspection + Slice B docs/runbook.
  - Result: partial.
  - Gap: live config still had direct DNS elements (`yandex-basic`, pushed DNS); no client DNS packets were observed.

- AC4: UDP-over-VLESS / DNS transport behavior is verified.
  - Evidence present: native VLESS outbound shape and Slice C proof map.
  - Result: partial.
  - Gap: no live packet proof that DNS transport works on the active path; TCP/DoH/DoT fallback only documented, not exercised.

- AC5: TCP/HTTPS is verified after DNS.
  - Evidence present: tcpdump attempt on `tun-asus` and Slice C proof map.
  - Result: not proven.
  - Gap: zero packets captured during the active-session window.

- AC6: Non-DNS internet traffic uses `tun-asus -> TPROXY :2082 -> sing-box -> native VLESS -> internet`, not broad plain VPS NAT.
  - Evidence present: dynamic-pool TPROXY rules, `route.final = selected-native-out`, and Slice B documentation.
  - Result: partial.
  - Gap: broad `10.89.0.0/24 -> eth0 MASQUERADE` remains as fallback and is not final-success evidence.

- AC7: Only the intended sing-box service remains active; package `sing-box.service` is not restart-storming.
  - Evidence present: systemctl/ps/ss checks.
  - Result: mostly passed.
  - Gap: legacy `xray.service` is still active separately on `10808`.

- AC8: Final state is documented and reproducible from repo scripts/docs, including rollback/emergency notes and any diagnostic-only bypass removal.
  - Evidence present: updated docs, script/config example, and gated live runbook in the task package.
  - Result: passed for repo-side reproducibility; live state still pending.
  - Gap: none for Slice B; root acceptance still needs live confirmation.

## System readiness coverage
- Routes / registration: covered for TPROXY/table 100 and dynamic-pool chain.
- Services / APIs: covered for `sing-box-vibe-router`; legacy `xray` remains a separate side service.
- Config / env / secrets: partially covered; repo-side examples and docs are updated, no secrets committed, but live DNS config still needs final sing-box-only confirmation.
- Docker / containers: not relevant.
- Permissions / access: covered; read-only SSH/sudo discovery worked.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: partially covered; native VLESS routing is wired, but broad NAT fallback and live DNS behavior still need gated proof.

## Check freshness
- Targeted checks: fresh.
- Full local checks: fresh.
- Remote checks / CI: not available before push.

## Required before done
- Capture a fresh active `ignat` (or equivalent dynamic client) session and rerun AC3-AC6 proof under traffic.
- Decide whether live direct DNS elements are temporary diagnostics or must be removed from the final sing-box config.
- If any live config is changed in Slice C, record backup/rollback and rerun validation before acceptance.

## Files written
- `docs/plans/2026-05-31-issue-9-openvpn-singbox-tproxy/verification/acceptance-plan.md`: created
- `docs/plans/2026-05-31-issue-9-openvpn-singbox-tproxy/reports/acceptance-auditor.md`: created
