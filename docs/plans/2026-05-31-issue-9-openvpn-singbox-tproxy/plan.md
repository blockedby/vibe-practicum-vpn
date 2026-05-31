# Plan: Issue #9 OpenVPN dynamic clients through sing-box TPROXY/VLESS

## Intake

GitHub issue #9 tracks dynamic OpenVPN client `ignat` (observed `10.89.0.23`) failing to get usable internet through the intended path:

```text
OpenVPN client -> tun-asus -> TPROXY :2082 -> sing-box rules/DNS/native VLESS -> internet -> tun-asus OUT -> client
```

Root constraints from the user / issue:

- Do not rely on xray; xray is deprecated.
- Do not accept broad direct VPS NAT as final success.
- DNS must be handled under sing-box rules in the final design.
- Direct/NAT DNS is diagnostic/emergency only, temporary, and must be documented if used.
- Current known cleanup: duplicate package `sing-box.service` is masked; `/etc/sing-box/config_backup.json` moved to `/etc/sing-box-disabled`; only `sing-box-vibe-router.service` should remain active.
- Make only scoped/reversible VPS/repo changes after read-only discovery justifies them.

## Acceptance criteria

AC1. Dynamic OpenVPN client `ignat` connects and receives a dynamic-pool IP (observed `10.89.0.23`; re-discover current IP).

AC2. Dynamic-pool OpenVPN traffic is captured by scoped TPROXY rules for `10.89.0.20-10.89.0.254` and locally delivered to `sing-box-vibe-router` on `:2082`; filter INPUT accepts marked TPROXY packets from the pool.

AC3. DNS for the client is handled under sing-box rules in the final design; no hidden permanent direct/NAT DNS leak. DNS query/reply are visible on `tun-asus` for the client.

AC4. UDP-over-VLESS / DNS transport behavior is verified. If raw UDP is unsafe for the selected native VLESS transport, DNS uses a proven TCP/DoH/DoT path under sing-box rules and generic UDP limitations are documented.

AC5. TCP/HTTPS is verified after DNS: client sends SYN/traffic and response returns on `tun-asus OUT`; public path matches expected sing-box/native VLESS policy.

AC6. Non-DNS internet traffic uses `tun-asus -> TPROXY :2082 -> sing-box -> native VLESS -> internet`, not broad plain VPS NAT.

AC7. Only the intended sing-box service remains active; package `sing-box.service` is not restart-storming.

AC8. Final state is documented and reproducible from repo scripts/docs, including rollback/emergency notes and any diagnostic-only bypass removal.

## Initial repo orientation

- Repo has no root `AGENTS.md`; README documents local checks and warns not to run live VPS-mutating commands unless intentionally operating on the VPS.
- Existing docs include `docs/OPENVPN_ASUS_TPROXY_CANARY.md`, which records a prior fixed-client TPROXY INPUT drop root cause and persistence expectations.
- Repo `configs/sing-box/tproxy-canary.json` is stale relative to issue target: it still has `xray-socks-out` as final and UDP DNS servers. Live discovery must inspect current VPS config before changing repo or VPS.

## Slice structure and execution waves

Use read-only live discovery first, then choose implementation slice(s) from evidence.

### Slice A: Read-only live discovery and acceptance refinement

- Goal: collect current live state for services, client IP, iptables/policy routing, sing-box config/DNS/outbounds, logs, and non-mutating packet/path checks.
- Owner/agent: `aad-explorer` (supporting discovery agent under root ownership).
- Report: `reports/live-discovery.md`.
- Acceptance covered: informs all ACs; no mutations.
- Blocks: implementation planning.

### Slice B: Scoped implementation plan and reversible change proposal

- Goal: based on Slice A, propose exact repo/VPS changes needed, with rollback, verification, and do-not-touch boundaries.
- Owner/agent: `aad-slice-owner` after Slice A.
- Report: TBD.
- Blocks: actual implementation.

### Slice C: Implementation and persistence (conditional)

- Goal: make only justified scoped/reversible changes to repo and, if necessary and safe, VPS state; verify DNS/TCP/HTTPS and service state.
- Owner/agent: `aad-slice-owner`.
- Report: TBD.
- Depends on: Slice B approval/decision by root owner.

### Slice D: Integration, acceptance audit, and final report

- Goal: integrate reports/results into this task package, run fresh verification, optionally use `aad-acceptance-auditor`, and decide root done-state.
- Owner: root owner.

## Execution ledger

- 2026-05-31: Root owner created isolated worktree `issue-9-openvpn-singbox-tproxy` from `origin/main` under `.worktrees/`.
- 2026-05-31: Task package created at `docs/plans/2026-05-31-issue-9-openvpn-singbox-tproxy/`.
- 2026-05-31: Next action is read-only live discovery.

## Integrated discovery summary (Slice A)

Source: `reports/live-discovery.md`, `verification/live-discovery.md`.

- `ignat` still maps to `10.89.0.23` in OpenVPN ipp/journal evidence, but was not connected during discovery; no current DNS/TCP packets were visible on `tun-asus`.
- Dynamic-pool TPROXY plumbing exists live: PREROUTING `10.89.0.20-10.89.0.254 -> VIBE_OVPN_ASUS_TP`, TCP/UDP TPROXY to `:2082`, INPUT accept for mark `0x1`, `fwmark 0x1 lookup 100`, `local default dev lo`.
- Active router is `sing-box-vibe-router.service`; package `sing-box.service` is masked/inactive and only one sing-box process is running.
- Live sing-box default outbound is native VLESS `selected-native-out`, not xray, but legacy `xray.service` remains active separately on `10808`.
- Live DNS has a `hijack-dns` route rule and detoured resolvers, but still includes direct `yandex-basic`; OpenVPN pushes `8.8.8.8` / `8.8.4.4` to dynamic clients.
- Broad OpenVPN `10.89.0.0/24 -> eth0 MASQUERADE` and FORWARD accept rules remain present as fallback; they must not count as final success.

Decision after Slice A:

- Do not mutate live VPS yet because no active client traffic was available to prove the failure mode or validate a fix.
- Proceed with Slice B: produce an implementation plan and repo-side reproducibility changes that are safe without an active client, while preserving a separate gated live-change plan for when the client can reconnect.

## Slice B execution plan: repo-side reproducibility and gated live plan

### Slice B intake gate

Goal: refine the issue #9 plan from Slice A evidence and make safe repo-only documentation/script/config-example improvements so the next live slice can act reversibly when an active dynamic OpenVPN client is available.

In scope:
- Update issue #9 task package plan/report/verification artifacts.
- Update narrow docs/scripts/config examples that currently imply `xray` is the intended dynamic OpenVPN TPROXY success path.
- Document native sing-box VLESS, sing-box-owned DNS (`hijack-dns` plus DNS rules), dynamic-pool INPUT delivery, broad NAT as diagnostic/emergency only, and a gated live runbook.

Out of scope / do-not-touch:
- No live VPS mutations, service restarts/reloads, iptables changes, `/etc/*` edits, or log-level changes.
- No secrets, full VLESS links, UUIDs, private keys, subscription URLs, or generated profiles.
- No broad NAT removal in this slice; only document later gated disable/removal criteria.
- Do not revive xray as a solution; only label legacy xray side findings.

Blocking unknowns:
- Active `ignat` client session is unavailable; AC3-AC6 cannot be fully proven live until Slice C.
- Live sing-box DNS/VLESS behavior must be verified under traffic after any gated config change.

### Repo orientation / reuse for Slice B

Likely repo areas:
- `docs/OPENVPN_ASUS_TPROXY_CANARY.md`
- `docs/ASUS_OPENVPN_SITE_TO_SITE.md`
- `scripts/openvpn-asus-tproxy-canary-rules.sh`
- `configs/sing-box/tproxy-canary.json`
- This task package: `docs/plans/2026-05-31-issue-9-openvpn-singbox-tproxy/`

Reuse / patterns:
- Existing OpenVPN ASUS docs already separate dry-run vs apply/export gates and warn against secret/profile commits.
- Existing canary doc already explains TPROXY local INPUT delivery; extend it from fixed `10.89.0.3` to dynamic pool `10.89.0.20-10.89.0.254`.
- Existing script is idempotent and dry-run-first; update its text/defaults safely if needed, but no live execution.
- Existing README local checks: `go test ./...`, `go vet ./...`, `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`, and `bash -n` for modified scripts.

Missing pieces to add now:
- Explicit native sing-box VLESS issue #9 success path in docs/config examples, with xray labelled legacy-only.
- DNS policy note: OpenVPN can push public DNS target IPs to clients, but final handling must be intercepted by sing-box `hijack-dns` and resolved via sing-box DNS rules/detours; direct/NAT DNS is diagnostic/emergency only.
- Dynamic-pool TPROXY local delivery persistence requirement: mangle capture and filter INPUT accept for marked `10.89.0.20-10.89.0.254`, not only `10.89.0.3/32`.
- Gated live-change runbook for Slice C: backup, reversible sing-box DNS config adjustment/logging/captures, rollback, and proof commands for DNS, UDP/VLESS behavior, TCP/HTTPS after DNS, service state, and broad NAT not counting as final success.

### Slice B tasks

#### Task B1: Update repo docs/config examples for native sing-box dynamic-pool path
Goal:
- Make repo docs/examples distinguish native sing-box VLESS from legacy xray for issue #9 dynamic OpenVPN TPROXY.

Boundary:
- System area: docs/scripts/config examples only.
- Primary verification: grep/read checks plus local syntax checks for any changed shell scripts/JSON.

Acceptance criteria:
- Docs no longer describe dynamic-pool issue #9 success as `sing-box -> xray`.
- Dynamic-pool `10.89.0.20-10.89.0.254` uses `sing-box :2082 -> native VLESS selected-native-out` as intended final path.
- Any xray references are labelled legacy / separate / not issue #9 success path.

Test plan:
- `grep -R "dynamic.*xray\|sing-box/xray\|xray/VLESS" docs scripts configs` and inspect remaining hits.
- `jq . configs/sing-box/tproxy-canary.json` if JSON changed.
- `bash -n` for changed shell scripts.

Dependencies: none.
Executor: `aad-implementer`.
Report: `reports/aad-implementer-b1-docs.md`.

#### Task B2: Add gated live-change and verification runbook to task package
Goal:
- Create a concrete next-step runbook that maps AC1-AC8 to commands/evidence and is safe for a future live slice.

Boundary:
- System area: task package plan/report/verification docs; optional cross-link from public docs if useful.
- Primary verification: read-through against AC1-AC8 and no live-mutating commands run now.

Acceptance criteria:
- AC1-AC8 each have concrete proof commands/evidence targets.
- Runbook includes backup, reversible sing-box DNS adjustment/log/capture steps, rollback path, and proof for DNS, UDP/VLESS, TCP/HTTPS after DNS, service state, and broad NAT not counting as final success.
- Runbook states that Slice C should wait for active `ignat` if end-to-end proof is required.

Test plan:
- Manual read-through of `verification/slice-b-local.md` / plan AC matrix.
- Local grep to ensure no secrets/full links/UUIDs were added.

Dependencies: Task B1 can run in parallel but final owner integration updates status after B1.
Executor: slice owner or `aad-implementer`; keep with slice owner if edits are mostly task-package ledger.
Report: `reports/slice-b-plan-and-repo.md`.

### Slice B dependency graph

- Wave 1: B1 delegated to `aad-implementer`; B2 owner-led task-package/runbook update can proceed in parallel.
- Wave 2: owner integrates B1 report/diff, runs local checks, records verification, writes Slice B report, and commits coherent repo changes.

### Slice B completion ledger

- Task B1 status: done by slice owner directly because nested subagent delegation was blocked by max subagent depth. Changes updated issue #9 docs, the canary script comment, and the repo sing-box canary example to native sing-box VLESS / hijack-dns semantics.
- Task B2 status: done. `verification/slice-b-local.md` now contains the AC1-AC8 live proof map, reversible DNS adjustment gate, backup/rollback path, and local verification evidence.
- Verification: `go test ./...`, `go vet ./...`, `go build -o /tmp/vibe-vpn ./cmd/vibe-vpn`, `jq . configs/sing-box/tproxy-canary.json`, and `bash -n scripts/openvpn-asus-tproxy-canary-rules.sh` passed after edits.
- Remaining blocker for root issue: AC3-AC6 still require live Slice C with an active dynamic client session; no live VPS mutations were made in Slice B.
