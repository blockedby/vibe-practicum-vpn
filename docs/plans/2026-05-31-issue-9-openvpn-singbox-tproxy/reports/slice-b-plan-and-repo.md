## Task
- Mission: Produce Slice B implementation/live-verification plan and safe repo-side reproducibility docs/config improvements for issue #9.
- Target: task package plan/verification plus narrow OpenVPN ASUS TPROXY docs/script/example config.
- Boundaries: No live VPS mutations; no secrets/full VLESS links/UUIDs/private keys/profiles; do not use xray or broad NAT as final success path.
- Done when: AC1-AC8 are mapped to live evidence, repo docs/examples distinguish native sing-box VLESS from legacy xray, DNS/dynamic-pool local delivery policy is documented, and local checks pass.
- Expected evidence: changed files, local checks, Slice C runbook, and next-agent brief.

## Context
- Thread: GitHub issue #9 root flow.
- Slice: Slice B — plan and repo-side persistence/docs improvements after read-only live discovery.
- Task name: Issue #9 OpenVPN dynamic clients through sing-box TPROXY/VLESS.
- Task package: `docs/plans/2026-05-31-issue-9-openvpn-singbox-tproxy`
- Report path: `docs/plans/2026-05-31-issue-9-openvpn-singbox-tproxy/reports/slice-b-plan-and-repo.md`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-9-openvpn-singbox-tproxy`
- Branch: `issue-9-openvpn-singbox-tproxy`
- Verify scope: local repo checks only; live runbook prepared but not executed.

## Spec compliance
- AC1 refined plan maps dynamic client/IP proof.
  - Status: done for Slice B.
  - Evidence: `verification/slice-b-local.md` AC1 commands for status/journal current pool IP.
- AC2 dynamic-pool TPROXY/local delivery documented.
  - Status: done for Slice B.
  - Evidence: `docs/OPENVPN_ASUS_TPROXY_CANARY.md`, `docs/ASUS_OPENVPN_SITE_TO_SITE.md`, and AC2 proof map require `10.89.0.20-10.89.0.254` INPUT accept for mark `0x1`, not only `10.89.0.3/32`.
- AC3 DNS policy documented.
  - Status: done for Slice B.
  - Evidence: docs state pushed public DNS IPs are client targets only; final handling must be sing-box `hijack-dns` and DNS rules/detours; direct/NAT DNS is diagnostic/emergency only.
- AC4 UDP/VLESS DNS behavior planned.
  - Status: done for Slice B planning; live proof pending.
  - Evidence: runbook requires DNS transport proof and TCP/DoH/DoT fallback if raw UDP is unsafe for selected VLESS transport.
- AC5 TCP/HTTPS after DNS planned.
  - Status: done for Slice B planning; live proof pending.
  - Evidence: runbook includes client HTTPS action and `tun-asus` tcpdump proof.
- AC6 broad NAT not success criterion.
  - Status: done for Slice B docs/planning.
  - Evidence: docs/runbook classify broad `10.89.0.0/24 -> eth0 MASQUERADE` as emergency fallback, not acceptance evidence.
- AC7 service state proof planned.
  - Status: done for Slice B planning.
  - Evidence: runbook includes `systemctl`, unit list, and process checks; xray is legacy side service only.
- AC8 reproducibility/rollback documented.
  - Status: done for Slice B.
  - Evidence: `verification/slice-b-local.md` includes backup, validation, rollback, and proof map.

## Acceptance verification
- AC1: Plan maps dynamic client discovery.
  - Covered by: `verification/slice-b-local.md` AC1 proof commands.
  - Result: passed for plan; live proof not run in this slice.
- AC2: Dynamic-pool TPROXY/local INPUT requirement documented.
  - Covered by: doc updates and AC2 proof commands.
  - Result: passed.
- AC3: DNS sing-box policy documented.
  - Covered by: doc updates and config example changing final DNS to detoured resolvers plus `hijack-dns`.
  - Result: passed.
- AC4: UDP/VLESS DNS behavior verification path exists.
  - Covered by: Slice C runbook.
  - Result: passed for planning; live proof pending.
- AC5: TCP/HTTPS verification path exists.
  - Covered by: Slice C runbook.
  - Result: passed for planning; live proof pending.
- AC6: No broad NAT final success.
  - Covered by: doc/runbook language and proof requirements.
  - Result: passed.
- AC7: Service cleanup/state verification path exists.
  - Covered by: Slice C runbook.
  - Result: passed for planning; live proof pending.
- AC8: Repo docs/runbook reproducibility.
  - Covered by: changed docs, config example, task package verification.
  - Result: passed.

## System readiness
- Routes / registration: not changed live; repo docs now require dynamic-pool mangle + INPUT local delivery.
- Services / APIs: not changed live; service proof commands prepared.
- Config / env / secrets: repo example uses placeholder VLESS values only; no secrets committed.
- Permissions / access: not relevant for local docs/config slice.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: ready for a gated live Slice C, preferably with active client present.

## Verification run
- Local / targeted checks:
  - `jq . configs/sing-box/tproxy-canary.json >/dev/null`: passed.
  - `bash -n scripts/openvpn-asus-tproxy-canary-rules.sh`: passed.
  - grep over touched issue #9 docs/script/config for stale xray path terms: passed; remaining hits are explicit legacy/not-success-path notes.
- Local / full checks:
  - `go test ./...`: passed.
  - `go vet ./...`: passed.
  - `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`: passed.
- Remote checks / CI:
  - Status: not available before push.
  - Evidence: branch not pushed/PR not checked in this slice.

## Issues
### R-01: Repo docs implied xray for dynamic-pool TPROXY success
- Description: OpenVPN ASUS docs described dynamic/full-tunnel paths as sing-box/xray or xray/VLESS.
- Evidence: prior text in `docs/ASUS_OPENVPN_SITE_TO_SITE.md` and `docs/OPENVPN_ASUS_TPROXY_CANARY.md`.
- Resolution: Updated issue #9-relevant docs to native sing-box VLESS; xray references are legacy/not-success-path notes.
- Depends on: none.

### R-02: Dynamic-pool local INPUT delivery was not prominent enough
- Description: Existing fixed canary docs emphasized `10.89.0.3/32`; issue #9 needs dynamic-pool `10.89.0.20-10.89.0.254` marked packets accepted locally.
- Evidence: Slice A found live dynamic-pool rules; acceptance required persistence/docs.
- Resolution: Docs now explicitly require dynamic-pool PREROUTING and filter INPUT accept for mark `0x1`.
- Depends on: none.

### R-03: DNS policy and live-change proof path were missing
- Description: Slice A found pushed public DNS plus a direct resolver in live sing-box config; final policy needed sing-box-owned DNS and reversible proof steps.
- Evidence: `reports/live-discovery.md` U-02.
- Resolution: Added DNS policy to docs and a gated Slice C runbook mapping AC1-AC8 to proof commands, backup, validation, and rollback.
- Depends on: none.

### U-01: Live end-to-end proof still needs an active dynamic client
- Description: Slice B did not mutate live VPS and cannot prove DNS/UDP/TCP behavior without active client traffic.
- Evidence: Slice A tcpdump saw `0 packets`; Slice B boundaries prohibit live mutation.
- Why unresolved: safe scope boundary and missing active session.
- Needed next: run Slice C when `ignat` or another dynamic client is connected, then execute the gated live proof/change plan.
- Depends on: active client session and live-change approval.

## Side findings
- Blocking findings folded into active work: none.
- Non-blocking findings tracked separately: none created in this slice; legacy xray side service remains a known Slice A side finding.

## Verdict
- Status: success for Slice B; root issue remains partial.
- Goal state: Slice B achieved.
- Final readiness: ready for live Slice C when a dynamic client session is available; if root owner only wants repo-side prep, this slice is complete now.
- Summary: Repo docs/config examples now point issue #9 dynamic OpenVPN TPROXY at native sing-box VLESS with sing-box DNS handling, and the next live slice has a reversible AC1-AC8 proof/runbook.

## Next-agent brief
- Objective: Execute live Slice C safely.
- Target: `vibe-practicum`, `tun-asus`, `/etc/sing-box-vibe/tproxy-canary.json`, `sing-box-vibe-router`, OpenVPN dynamic client `ignat`/current pool IP.
- Settled already: xray is not success path; final DNS belongs to sing-box `hijack-dns`/DNS rules; dynamic-pool INPUT accept is required; broad NAT is emergency/diagnostic only.
- Boundaries: no secrets in reports; backup before config edits; validate sing-box config before service action; rollback ready; do not count NAT-only connectivity as success.
- Verification target: AC1-AC8 proof matrix in `verification/slice-b-local.md`.
- Expected output: live evidence report with commands/output, exact changes/rollback path, and final acceptance status.

Root owner proceed/wait recommendation: wait for an active `ignat`/dynamic-client session if end-to-end AC3-AC6 proof is the next goal. If the goal is only to stage reversible DNS config changes, Slice C can start earlier but must still reserve final acceptance until client traffic is captured.
