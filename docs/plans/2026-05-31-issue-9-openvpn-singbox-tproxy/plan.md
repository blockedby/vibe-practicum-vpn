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
