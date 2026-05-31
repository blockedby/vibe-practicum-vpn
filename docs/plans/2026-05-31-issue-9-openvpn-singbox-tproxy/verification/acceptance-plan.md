# Acceptance plan: Issue #9 OpenVPN dynamic clients through sing-box TPROXY/VLESS

## Decision target
- Decide whether current evidence is enough to accept the root issue, and whether live Slice C is safe to start.

## Evidence map
- AC1: current `ignat` lease/IP
  - Proof: OpenVPN ipp/status/journal showing current CN and pool IP.
- AC2: dynamic-pool TPROXY + INPUT + local delivery
  - Proof: iptables mangle/filter counters, `fwmark 0x1 lookup 100`, `local default dev lo`, `ss` on `:2082`.
- AC3: DNS handled under sing-box rules
  - Proof: sing-box DNS/routing config + `tun-asus` DNS packet capture during active client session.
- AC4: UDP-over-VLESS / DNS transport behavior
  - Proof: live DNS transport observation; if needed, documented TCP/DoH/DoT fallback under sing-box rules.
- AC5: TCP/HTTPS after DNS
  - Proof: client HTTPS request plus `tun-asus` capture of SYN/response.
- AC6: non-DNS traffic uses sing-box/native VLESS, not broad NAT
  - Proof: sing-box route/outbound logs and counters; NAT fallback explicitly excluded as success.
- AC7: intended sing-box service state only
  - Proof: `systemctl`, process, and listener checks; legacy xray recorded separately.
- AC8: reproducible docs + rollback/emergency notes
  - Proof: updated repo docs/runbook and recorded rollback path.

## Current expectation
- Slice B documentation/runbook evidence should be sufficient to proceed to live Slice C.
- Root issue should not be marked fixed until AC3-AC6 have fresh live evidence from an active dynamic client session.
