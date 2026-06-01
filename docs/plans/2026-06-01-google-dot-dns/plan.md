# Google DoT DNS for containerized vpnkit sing-box

## Task intake
- Goal: change containerized vpnkit sing-box DNS from Cloudflare DoT to Google DoT with `8.8.8.8` primary and `8.8.4.4` secondary/fallback.
- In scope: generated/template sing-box DNS config for containerized vpnkit; committed rendered config if present and non-secret-safe; docs/evidence/runbook references that describe `1.1.1.1` as the DNS resolver.
- Out of scope: do not alter HTTPS literal-IP tests/references unless they are incorrectly describing DNS; do not print or commit secrets; no live VPS mutation.
- Done state: config uses Google DoT servers detoured through `selected-native-out`, relevant docs/evidence no longer claim `1.1.1.1` is DNS resolver, minimal config validation passes, branch is committed and pushed.
- Blocking unknowns: whether rendered config under `secrets/` is tracked/safe; must inspect without printing secrets.

## Repo orientation
- Worktree: `.worktrees/containerized-vpnkit-openvpn-singbox`.
- Branch: `pi/containerized-vpnkit-openvpn-singbox` tracking origin branch.
- Source config: `config/sing-box/config.json.template`; implementation updates it to Google DoT primary/fallback detoured through `selected-native-out`.
- Generated/rendered config under `secrets/vps/rendered/sing-box/config.json` is gitignored; render/check it locally without committing or printing secrets.
- Relevant prior evidence in `docs/plans/2026-05-31-containerized-vpnkit/verification/implementation-run-2026-06-01.md` is historical and should not be read as the current resolver; literal-IP HTTPS references to `1.1.1.1:443` should remain unless needed.
- Validation commands to try: render/generate command if present; `jq` JSON syntax on template/rendered JSON; `sing-box check -c <rendered config>` if sing-box binary and non-secret rendered config are available.

## Reuse discovery
- Preserve existing sing-box DNS object shape and `detour: selected-native-out`.
- Use sing-box DNS server list/fallback conventions already present in repo configs if available; otherwise add distinct primary/fallback DNS server entries with final/fallback strategy compatible with existing sing-box config schema.
- Do not change OpenVPN client literal-IP HTTPS smoke test (`--resolve example.com:443:1.1.1.1`) unless a validation proves it must change.

## Missing pieces
- Done: replace the previous Cloudflare DoT resolver with Google DoT primary `tls://8.8.8.8` and fallback/secondary `tls://8.8.4.4` while preserving detour through `selected-native-out`.
- Done: update DNS-specific evidence/runbook text so prior Cloudflare resolver evidence is explicitly historical; leave literal-IP HTTPS tests intact.
- Done/pending finalization: run minimal validation and record results.

## Plan tasks

### Task 1: Google DoT DNS config and references
Goal:
- Containerized vpnkit sing-box config uses Google DoT primary/fallback through `selected-native-out`, and current docs/evidence references are consistent.

Boundary:
- System area: containerized vpnkit sing-box config/docs.
- Primary verification: JSON/config syntax and `sing-box check` where available.

Existing pattern / reuse:
- `config/sing-box/config.json.template` DNS section and existing detour field.
- Existing docs/runbook wording around DNS and literal-IP tests.

Missing change:
- Replace Cloudflare resolver with Google primary/fallback; update current DNS-resolver references only.

Scope / likely files:
- `config/sing-box/config.json.template`
- tracked rendered sing-box config if safe/applicable
- task evidence docs that could otherwise be read as current Cloudflare DoT resolver claims

Acceptance criteria:
- AC1: sing-box DNS has primary `tls://8.8.8.8` and secondary/fallback `tls://8.8.4.4`.
- AC2: each Google DoT server is detoured through `selected-native-out`.
- AC3: no current docs/evidence/runbook reference incorrectly describes `1.1.1.1` as the DNS resolver; literal-IP HTTPS tests remain unchanged unless necessary.
- AC4: minimal syntax/config validation runs without exposing secrets.
- AC5: changes are committed and pushed to `pi/containerized-vpnkit-openvpn-singbox`.

Test plan:
- Positive: `jq` on changed JSON/template/rendered JSON; run repo render/generation command if discoverable; run `sing-box check -c <rendered config>` if sing-box and safe rendered config are available.
- Negative/edge: grep for `tls://1.1.1.1` and current DNS resolver claims; verify remaining `1.1.1.1` references are literal-IP tests or historical evidence.
- Manual: inspect no secrets printed/committed.

Dependencies:
- Depends on: none.
- Blocks: final report.
- Can run parallel with: none; small single task.

Executor:
- `aad-implementer`.

## Dependency graph
- Task 1 only; keep slice whole, delegate implementation to one `aad-implementer`.

## Execution ledger
- 2026-06-01: Slice owner created plan and prepared delegation.
- 2026-06-01: Implementer updated `config/sing-box/config.json.template` with Google DoT primary/fallback, marked prior Cloudflare DoT evidence as historical, rendered gitignored local configs, and ran targeted validation.

## Verification summary
- Template assertion: `python3` parsed the template with placeholder replaced and confirmed `remote-dns` -> `tls://8.8.8.8`, `remote-dns-fallback` -> `tls://8.8.4.4`, and both detours are `selected-native-out`.
- Render/check: `./scripts/vpnkit-render-local-configs.sh` rendered gitignored local configs; `jq` confirmed both Google DoT entries in `secrets/vps/rendered/sing-box/config.json`; `sing-box check` passed with existing deprecation compatibility env vars.
- Grep: `tls://1.1.1.1`/`1.1.1.1:853` matches are limited to historical prior-run evidence or task plan context, not current resolver claims; literal-IP HTTPS `1.1.1.1:443` tests were not changed.
