## Task
- Mission: Read-only live discovery for Issue #9; collect current evidence for OpenVPN dynamic client `ignat`, sing-box TPROXY/VLESS, DNS handling, routing, and service cleanup.
- Target: Repo docs plus live host `vibe-practicum` (`openvpn-server@vibe-asus`, `sing-box-vibe-router`, iptables/routing, sing-box config, packet visibility).
- Boundaries: No source/config changes, no service restarts/reloads, no iptables/nft/systemd mutation, no secrets in output.
- Done when: Current state is evidenced for AC1-AC8 and the remaining blockers/follow-ups are explicit.
- Expected evidence: Exact commands, short outputs, and a compact handoff report.

## Context
- Thread: AAD root flow for GitHub issue #9.
- Slice: Read-only live discovery.
- Task name: Issue #9 OpenVPN dynamic clients through sing-box TPROXY/VLESS.
- Task package: `docs/plans/2026-05-31-issue-9-openvpn-singbox-tproxy`
- Report path: `docs/plans/2026-05-31-issue-9-openvpn-singbox-tproxy/reports/live-discovery.md`
- Verification artifact path: `docs/plans/2026-05-31-issue-9-openvpn-singbox-tproxy/verification/live-discovery.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-9-openvpn-singbox-tproxy`
- Branch: `issue-9-openvpn-singbox-tproxy`
- Verify scope: live host status, packet/rule visibility, sing-box config shape, and current client visibility.
- Review target: acceptance refinement for AC1-AC8.

## Spec compliance
- AC1: Dynamic OpenVPN client `ignat` receives a dynamic-pool IP.
  - Status: partial
  - Evidence: `/var/lib/openvpn/vibe-asus-ipp.txt` maps `ignat,10.89.0.23`; `journalctl -u openvpn-server@vibe-asus --since '6 hours ago' -g 'ignat|10.89.0.23|PUSH_REPLY|MULTI: primary virtual IP'` shows `MULTI_sva: pool returned IPv4=10.89.0.23` and `MULTI: primary virtual IP ... 10.89.0.23`.
  - Gap: no current live client session; latest log ends with disconnect at 00:14 UTC.

- AC2: Dynamic-pool traffic is captured by scoped TPROXY and locally delivered to sing-box on :2082; INPUT accepts marked packets from the pool.
  - Status: done for rules/wiring, partial for live packet proof
  - Evidence: `iptables -t mangle -S` shows `-A PREROUTING -i tun-asus -m iprange --src-range 10.89.0.20-10.89.0.254 -j VIBE_OVPN_ASUS_TP`; `-A VIBE_OVPN_ASUS_TP ... -p tcp/-p udp ... -j TPROXY --on-port 2082 --tproxy-mark 0x1/0x1`; `iptables -t filter -S INPUT` shows `-A INPUT -i tun-asus -m iprange --src-range 10.89.0.20-10.89.0.254 -m mark --mark 0x1/0x1 -j ACCEPT`; `ip rule show` includes `fwmark 0x1 lookup 100`; `ip route show table 100` is `local default dev lo scope host`; `ss -lntup` shows sing-box listening on TCP/UDP 2082.
  - Gap: live INPUT accept counter stayed 0 during observation because no current client traffic was visible.

- AC3: DNS is handled under sing-box rules in the final design; no hidden permanent direct/NAT DNS leak.
  - Status: partial / not yet proven final
  - Evidence: live sing-box config has `route.rules` entry `action: hijack-dns, port: 53`; DNS servers include detoured resolvers (`google-8`, `google-8844`, `google-8888-backup`, `quad9-9` with `detour: selected-native-out`) and `yandex-basic`; OpenVPN server still pushes `dhcp-option DNS 8.8.8.8` and `8.8.4.4`.
  - Gap: `yandex-basic` is still direct in live config, and no client DNS packets were visible on `tun-asus`, so sing-box-only DNS behavior was not proven.

- AC4: UDP-over-VLESS / DNS transport behavior is verified.
  - Status: partial
  - Evidence: live sing-box outbound `selected-native-out` is `type: vless` to `185.192.22.159:8444` with UUID redacted; `route.final` is `selected-native-out`; DNS servers can detour via `selected-native-out`.
  - Gap: no live DNS/client UDP traffic to prove the chosen transport path under load; no packet-level observation of VLESS DNS transport from `ignat`.

- AC5: TCP/HTTPS is verified after DNS.
  - Status: not proven
  - Evidence: `timeout 8 tcpdump -ni tun-asus 'src net 10.89.0.0/24 and (port 53 or tcp port 80 or tcp port 443)' -c 20` captured `0 packets`.
  - Gap: no active client traffic during capture, so no TCP/HTTPS verification possible.

- AC6: Non-DNS internet traffic uses tun-asus -> TPROXY :2082 -> sing-box -> native VLESS -> internet, not broad plain VPS NAT.
  - Status: partial
  - Evidence: dynamic-pool PREROUTING TPROXY rule and sing-box `selected-native-out` final are in place; `sing-box` is the only active router process on :2082.
  - Gap: broad fallback NAT/forwarding still exists: `iptables -t nat -S` shows `-A POSTROUTING -s 10.89.0.0/24 -o eth0 -j MASQUERADE` and `iptables -t filter -L FORWARD` shows `10.89.0.0/24` ACCEPT rules; this is diagnostic/emergency only, not a success criterion.

- AC7: Only the intended sing-box service remains active; package `sing-box.service` is not restart-storming.
  - Status: mostly done
  - Evidence: `systemctl list-units 'sing-box*' --all` shows only `sing-box-vibe-router.service` active; `systemctl is-active sing-box-vibe-router sing-box openvpn-server@vibe-asus` returned `active / inactive / active`; `sing-box.service` is masked; `ps -ef | grep '[s]ing-box'` shows one sing-box PID.
  - Gap: legacy `xray.service` is still active separately and listening on 10808.

- AC8: Final state is documented and reproducible from repo scripts/docs, including rollback/emergency notes.
  - Status: partial
  - Evidence: repo docs already document OpenVPN ASUS TPROXY canary, dynamic pool range, and rollback/install scripts (`docs/OPENVPN_ASUS_TPROXY_CANARY.md`, `docs/ASUS_OPENVPN_SITE_TO_SITE.md`, `scripts/openvpn-asus-*`).
  - Gap: no implementation/update was made in this discovery pass; repo copy of `configs/sing-box/tproxy-canary.json` is still stale versus live VPS config.

## Acceptance verification
- AC1: Current `ignat` pool identity/IP discovered
  - Covered by: OpenVPN ipp/status/journal evidence
  - Result: partial
  - Evidence: `ignat -> 10.89.0.23`; latest connection logs show `MULTI: primary virtual IP ... 10.89.0.23`.

- AC2: Dynamic pool TPROXY + INPUT + local delivery exists
  - Covered by: iptables/rule/route/ss evidence
  - Result: passed for wiring, partial for live traffic
  - Evidence: PREROUTING/INPUT rules, `fwmark 0x1 lookup 100`, `local default dev lo`, sing-box listening on 2082.

- AC3: DNS under sing-box rules
  - Covered by: sing-box config inspection
  - Result: partial
  - Evidence: `hijack-dns` rule exists, but `yandex-basic` is direct and OpenVPN still pushes external DNS servers.

- AC4: UDP-over-VLESS/DNS transport path
  - Covered by: live sing-box outbound inspection
  - Result: partial
  - Evidence: `selected-native-out` is VLESS; no live packet proof from client.

- AC5: TCP/HTTPS after DNS
  - Covered by: tcpdump observation
  - Result: not run successfully for an active client session
  - Evidence: tcpdump saw `0 packets`.

- AC6: No broad NAT as success path
  - Covered by: NAT/FORWARD inspection
  - Result: partial
  - Evidence: broad `10.89.0.0/24 -> eth0 MASQUERADE` and `FORWARD ACCEPT` rules still exist as fallback.

- AC7: Sing-box service cleanup
  - Covered by: systemctl/ps/ss
  - Result: mostly passed
  - Evidence: one sing-box PID; `sing-box-vibe-router` active; `sing-box.service` masked.

- AC8: Reproducible documentation/rollback state
  - Covered by: repo doc scan
  - Result: partial
  - Evidence: dedicated OpenVPN ASUS TPROXY docs and scripts exist; live config divergence remains.

## System readiness
- Routes / registration: done for TPROXY mark/table 100 and dynamic-pool chain; live rules present.
- Services / APIs: partial; `sing-box-vibe-router` healthy, `openvpn-server@vibe-asus` active, `xray.service` still active as legacy.
- Config / env / secrets: partial; live sing-box config is VLESS-based with redacted UUID, but DNS path still contains direct elements.
- Permissions / access: done; SSH + sudo read-only access worked.
- Runtime / deployment wiring: partial; sing-box route final is native VLESS, but broad NAT fallback is still installed.

## Verification run
- Local / targeted checks:
  - `ssh vibe-practicum 'hostname; date; uname -a'`: passed
    - Evidence: host `awsbbbuslw`, `Sun May 31 03:08:36 AM UTC 2026`, Ubuntu 6.8 kernel.
  - `ssh vibe-practicum 'systemctl list-units "sing-box*" --all ...'`: passed
    - Evidence: only `sing-box-vibe-router.service` loaded/active; `sing-box.service` masked.
  - `ssh vibe-practicum 'sudo ps -ef | grep "[s]ing-box"; sudo ss -lntup ...'`: passed
    - Evidence: one sing-box PID; listeners on 2082 and 2080.
  - `ssh vibe-practicum 'sudo iptables -t mangle -S; sudo iptables -t filter -S INPUT; sudo iptables -t nat -S; sudo ip rule show; sudo ip route show table 100'`: passed
    - Evidence: dynamic-pool TPROXY, INPUT ACCEPT for marked pool, fwmark 0x1 lookup 100, local default route, broad NAT fallback present.
  - `ssh vibe-practicum 'sudo jq ... /etc/sing-box-vibe/tproxy-canary.json'`: passed
    - Evidence: outbound `selected-native-out` is VLESS; DNS servers include detoured resolvers; `hijack-dns` rule present.
  - `ssh vibe-practicum 'sudo timeout 8 tcpdump -ni tun-asus ... -c 20'`: passed as observation
    - Evidence: `0 packets captured`.

- Local / full checks:
  - Not run (read-only discovery only).

- Remote checks / CI:
  - Status: not available before push
  - Evidence: no code changes or PR push in this discovery pass.

## Issues
### U-01: No active client traffic to prove end-to-end DNS/TCP/HTTPS
- Description: The latest `ignat` assignment is known (`10.89.0.23`), but the client was not currently connected during observation; tcpdump on `tun-asus` saw zero packets for ports 53/80/443.
- Evidence: `openvpn-status.log` had no client rows; journal showed the last `ignat` disconnect at `May 31 00:14:16`; tcpdump reported `0 packets captured`.
- Why unresolved: the required live session was absent, so packet-level proof for AC3-AC5 cannot be completed safely in read-only mode.
- Needed next: re-capture a fresh `ignat` session and repeat packet/rule checks while the client is active.
- Depends on: fresh client connection.

### U-02: Live DNS path is not yet strictly sing-box-only
- Description: The live sing-box config still has a direct resolver (`yandex-basic`) and OpenVPN pushes external DNS servers (`8.8.8.8`, `8.8.4.4`).
- Evidence: `/etc/sing-box-vibe/tproxy-canary.json` DNS section; `/etc/openvpn/server/vibe-asus.conf` push lines.
- Why unresolved: final design requires DNS to be under sing-box rules; the current live config still includes direct DNS elements.
- Needed next: decide whether those direct DNS elements are temporary diagnostics or must be removed/retargeted in the final config.
- Depends on: implementation decision.

## Side findings
- Blocking findings folded into active work: none.
- Non-blocking findings tracked separately: `xray.service` remains active as a legacy process listening on 10808; repo `configs/sing-box/tproxy-canary.json` is stale versus live VPS config.

## Verdict
- Status: partial
- Goal state: not achieved
- Final readiness: not ready
- Summary: The live VPS now shows the intended dynamic-pool TPROXY/VLESS wiring and a known `ignat` pool assignment, but no active client traffic was visible and the DNS path still contains direct elements, so end-to-end proof is incomplete.

## Next-agent brief
- Objective: Prove or adjust the end-to-end OpenVPN dynamic-pool -> sing-box -> native VLESS -> DNS/TCP/HTTPS path with a fresh client session.
- Target: live host `vibe-practicum`, especially `tun-asus`, `/etc/sing-box-vibe/tproxy-canary.json`, `/etc/openvpn/server/vibe-asus.conf`, and `iptables` TPROXY/NAT/INPUT rules.
- Settled already: `ignat` currently maps to `10.89.0.23`; dynamic-pool TPROXY rules/table 100 exist; `sing-box-vibe-router` is the active sing-box service; `sing-box.service` is masked.
- Boundaries: read-only until an owner explicitly authorizes reversible changes.
- Verification target: active-client tcpdump on `tun-asus`, sing-box logs showing handled DNS, and proof that no permanent direct/NAT DNS path is required.
- Expected output: a narrowed implementation/verification plan or a confirmed blocker list with exact required changes.