## Task
- Mission: Implement/debug the containerized vpnkit lab until OpenVPN client traffic reaches sing-box and exits via `selected-native-out` with DNS and HTTPS succeeding.
- Target: Docker lab in `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/containerized-vpnkit-openvpn-singbox`.
- Boundaries: no VPS mutation; no committed/printed secrets; no xray dependency; no broad permanent OpenVPN-pool MASQUERADE bypass; DNS must stay under sing-box rules.
- Done when: containers build/start, `ovpn-client-test` gets `10.89.0.x`, DNS/domain HTTPS/literal-IP HTTPS pass, and evidence is saved under the task package.
- Expected evidence: fresh Docker run, netfilter counters/logs, TPROXY blocker evidence if fallback used, static safety checks, changed files, commit.

## Context
- Thread: user requested no-stop implementation/debug using prior Opus analysis sequence.
- Slice: single end-to-end runtime slice.
- Task name: containerized vpnkit OpenVPN -> sing-box lab.
- Task package: `docs/plans/2026-05-31-containerized-vpnkit/`
- Report path: `docs/plans/2026-05-31-containerized-vpnkit/reports/end-to-end-fix-slice-owner.md`
- Worktree: `.worktrees/containerized-vpnkit-openvpn-singbox`
- Branch: `pi/containerized-vpnkit-openvpn-singbox`
- Verify scope: Docker lab runtime and static safety checks.
- Review target: Docker/sing-box/OpenVPN lab files and task-package evidence.

## Spec compliance
- Ordered TPROXY investigation: done. Scoped INPUT accept was added for tproxy mode; minimal `IP_TRANSPARENT` listener did not accept despite matching TPROXY counters.
- Fallback selection: done. sing-box TUN fallback was tested and rejected because routed packets arrived at the TUN peer destination; final fallback uses scoped REDIRECT into sing-box.
- OpenVPN client end-to-end: done. Client receives `10.89.0.2/24` and split default routes via `10.89.0.1`.
- Traffic reaches sing-box: done. Logs show `vpnkit-redirect-in` and `vpnkit-dns-in` from `10.89.0.2`.
- selected-native-out VLESS: done. Logs show `outbound/vless[selected-native-out]` for DNS-over-TLS and HTTPS.
- DNS under sing-box: done. UDP/53 is REDIRECTed to sing-box direct inbound and matched by `hijack-dns`, then DoT exits via `selected-native-out`.
- HTTPS/literal-IP: done. Client test returns `https-test http_code=200` and `literal-ip-test http_code=200`.
- No broad NAT/xray: done. Static checks found no runtime broad MASQUERADE and no lab xray dependency.

## Acceptance verification
- AC1 containers build/start:
  - Covered by: `docker compose build`, `docker compose up -d vpnkit`.
  - Result: passed.
  - Evidence: `verification/implementation-run-2026-06-01.md`.
- AC2 OpenVPN client gets `10.89.0.x`:
  - Covered by: `docker compose --profile test run --rm ovpn-client-test`.
  - Result: passed (`inet 10.89.0.2/24`).
- AC3 traffic enters vpnkit tun0:
  - Covered by: OpenVPN server/client tunnel plus REDIRECT counters; earlier tcpdump in artifact.
  - Result: passed.
- AC4 traffic reaches sing-box:
  - Covered by: sing-box inbound logs from `10.89.0.2`.
  - Result: passed.
- AC5 selected-native-out used:
  - Covered by: `outbound/vless[selected-native-out]` log lines.
  - Result: passed.
- AC6 DNS succeeds under sing-box:
  - Covered by: `dig` NOERROR plus `vpnkit-dns-in => hijack-dns => selected-native-out` logs.
  - Result: passed.
- AC7 HTTPS succeeds:
  - Covered by: `https-test http_code=200`.
  - Result: passed.
- AC8 literal-IP HTTPS succeeds:
  - Covered by: `literal-ip-test http_code=200 remote_ip=1.1.1.1`.
  - Result: passed.
- AC9 no broad MASQUERADE/no xray:
  - Covered by: static grep commands.
  - Result: passed.
- AC10 evidence recorded:
  - Covered by: `verification/implementation-run-2026-06-01.md`.
  - Result: passed.
- AC11 commit coherent changes:
  - Covered by: commit `Fix containerized vpnkit lab routing`.
  - Result: passed.

## System readiness
- Routes / registration: done; compose default `VPNKIT_ROUTING_MODE=redirect`, REDIRECT chain installed after OpenVPN `tun0` exists.
- Services / APIs: done; sing-box and OpenVPN start in `vpnkit`, test client runs separately.
- Config / env / secrets: done; real configs remain under gitignored `secrets/`; render script pre-resolves VLESS dial host without committing rendered config.
- Permissions / access: done for local Docker; compose uses `privileged: true`, `NET_ADMIN`, `NET_RAW`, `/dev/net/tun`.
- Database / migrations: not applicable.
- Frontend-backend integration: not applicable.
- Runtime / deployment wiring: ready for local lab; not a VPS deployment change.

## Verification run
- Local / targeted checks:
  - `bash -n ...`: passed.
  - `sing-box check -c /etc/sing-box/config.json`: passed with legacy DNS warning.
  - `docker compose config`: passed.
  - `docker compose build && docker compose up -d vpnkit && docker compose --profile test run --rm ovpn-client-test`: passed.
  - `iptables -t nat -L OVPN_REDIRECT_TO_SINGBOX`: passed; counters `tcp=2`, `udp dpt:53=1` after test.
  - `git diff --check`: passed.
  - `grep -R "POSTROUTING.*10.89.0.0/24.*MASQUERADE" docker config scripts`: no matches.
  - `grep -R "xray" docker config scripts/vpnkit-* docs/CONTAINERIZED_VPNKIT_RUNBOOK.md`: no matches.
- Local / full checks:
  - `go test ./...`: not run; no Go files changed.
- Remote checks / CI:
  - Status: not checked; branch not pushed after current local commit step yet.

## Issues
### Issue R-01: TPROXY local delivery failure in Docker lab
- Description: TPROXY counters matched, but neither sing-box TPROXY inbound nor a minimal transparent listener accepted packets.
- Evidence: `verification/implementation-run-2026-06-01.md` records TPROXY counters and listener output with no `PROBE_ACCEPT`.
- Resolution: kept tproxy mode as diagnostic and implemented REDIRECT architecture for the working lab.
- Depends on: none.

### Issue R-02: DNS redirect initially bypassed hijack action
- Description: UDP/53 redirected to a direct inbound was routed to `0.0.0.0:5353` via VLESS until the route rule matched the inbound tag.
- Evidence: prior logs showed `outbound/vless[selected-native-out]: outbound packet connection to 0.0.0.0:5353`; final logs show `router: match[0] inbound=vpnkit-dns-in => hijack-dns`.
- Resolution: added `{ "inbound": "vpnkit-dns-in", "action": "hijack-dns" }` before the protocol DNS route rule.
- Depends on: none.

## Side findings
- Blocking findings folded into active work: TPROXY failure and DNS hijack rule ordering.
- Non-blocking findings tracked separately: sing-box legacy DNS syntax warning and privilege reduction remain caveats; no GitHub follow-up created in this run.

## Verdict
- Status: success.
- Goal state: fully achieved with REDIRECT architecture after TPROXY/TUN blocker evidence.
- Final readiness: ready for PR update; ready for local lab reproduction with gitignored secrets.
- Summary: The lab now passes OpenVPN, DNS, selected-native-out VLESS, HTTPS, and literal-IP HTTPS checks without broad MASQUERADE or xray.

## Next-agent brief
- Objective: If continuing, migrate sing-box DNS config away from legacy DNS server syntax and reduce compose privileges.
- Target: `config/sing-box/config.json.template`, `docker-compose.yml`, runbook/evidence.
- Settled already: REDIRECT architecture is the working route; do not re-open TPROXY unless changing host/kernel/container assumptions.
- Boundaries: no secrets, no VPS mutation, no broad MASQUERADE.
- Verification target: preserve `docker compose --profile test run --rm ovpn-client-test` success and DNS `hijack-dns` logs.
- Expected output: focused follow-up PR/report if those caveats are addressed.
