# Phase 1 vpnkit IPv4-only / IPv6-block policy plan

## Task intake
- Goal: make current containerized vpnkit explicitly IPv4-only so clients/processes such as Codex/Node do not receive or attempt IPv6/AAAA blackhole paths.
- In scope:
  - Add configurable `VPNKIT_IPV6_POLICY=block` default.
  - Configure sing-box DNS for IPv4-only lookups (`strategy: ipv4_only` by default, with safe configurable equivalent if possible).
  - Explicitly block IPv6 traffic in vpnkit routing where applicable.
  - Document that current vpnkit is IPv4-only and how to operate/verify it.
  - Preserve existing compat bypass behavior and no secrets.
  - Verify with shell syntax checks, docker compose config, sing-box check if possible.
  - Commit and push to existing `vpnkit-compat-bypass` PR branch if appropriate.
- Out of scope:
  - Live deploy to VPS/Steam Deck unless explicitly safe with evidence.
  - Adding real IPv6 support; this is Phase 1 block/IPv4-only policy.
  - Touching gitignored secrets or generated profiles/logs.
- Done state: branch contains committed implementation/docs/tests, local verification is recorded, branch pushed, and report includes commits, changed files, tests, and live-deploy instructions.
- Blocking unknowns: availability of local `sing-box` binary and Docker daemon; if unavailable, record command failure/waiver and provide deploy-time check.

## Repo orientation
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-compat-bypass` on `vpnkit-compat-bypass` tracking `origin/vpnkit-compat-bypass`.
- Local guidance: `AGENTS.md` says Steam Deck deployment is Podman only; Docker okay for local lab/client-test; do not commit secrets/profiles/logs.
- Runtime files likely in scope:
  - `docker-compose.yml` env propagation.
  - `docker/vpnkit/setup-routing.sh` netfilter/sysctl routing setup.
  - `docker/vpnkit/entrypoint.sh` sing-box config startup/restart validation.
  - `config/sing-box/config.json.template` default generated sing-box config.
  - `scripts/vpnkit-render-local-configs.sh` if rendered config should inherit template policy.
  - `docs/CONTAINERIZED_VPNKIT_RUNBOOK.md` and possibly `README.md` for docs.
- Verification commands:
  - `bash -n docker/vpnkit/entrypoint.sh docker/vpnkit/setup-routing.sh scripts/vpnkit-render-local-configs.sh scripts/vpnkit-routing-compat-bypass-test.sh`
  - `scripts/vpnkit-routing-compat-bypass-test.sh`
  - `docker compose config`
  - `sing-box check -c <rendered-or-temp-config>` if sing-box available and config can be rendered safely.

## Reuse discovery
- Existing env defaults and truthy helpers in `docker/vpnkit/setup-routing.sh` should be reused.
- Existing compat bypass dry-run test `scripts/vpnkit-routing-compat-bypass-test.sh` can be extended to assert IPv6 block rules while preserving bypass assertions.
- Existing sing-box template already has `dns.final` and route rules; add DNS strategy there rather than inventing new config layout.
- Existing compose environment block is the source for container env propagation.

## Missing pieces
- `VPNKIT_IPV6_POLICY` default and validation.
- Optional/configurable sing-box DNS strategy variable, default `ipv4_only`, applied to source config before `sing-box check` if needed.
- IPv6 block/drop rules (`ip6tables`) for OpenVPN client CIDR/tun0 path in supported routing modes; dry-run-safe and tolerant if IPv6 tooling unavailable under block policy.
- Docs for IPv4-only policy, override/disable behavior if any, and deployment-time checks.
- Verification evidence and commit/push.

## Plan tasks

### Task 1: IPv4-only runtime policy and docs
Goal:
- vpnkit defaults to IPv4-only DNS and explicitly blocks IPv6 traffic from OpenVPN clients without breaking compat bypass.

Boundary:
- System area: container runtime config, sing-box DNS template/startup, netfilter routing, docs.
- Primary verification: shell checks, dry-run routing assertions, compose config, sing-box config check where available.

Existing pattern / reuse:
- `docker/vpnkit/setup-routing.sh` env defaults/helpers/dry-run pattern.
- `docker/vpnkit/entrypoint.sh` config copy + `sing-box check` startup pattern.
- `config/sing-box/config.json.template` DNS section.
- `docs/CONTAINERIZED_VPNKIT_RUNBOOK.md` lab/runbook format.

Missing change:
- Add/propagate `VPNKIT_IPV6_POLICY=block` and DNS strategy default `ipv4_only`.
- Add `ip6tables` block rules for `tun0`/OpenVPN client traffic when policy is `block`, with validation for supported values.
- Document policy and operator verification/deploy instructions.

Scope / likely files:
- `docker-compose.yml`
- `docker/vpnkit/entrypoint.sh`
- `docker/vpnkit/setup-routing.sh`
- `config/sing-box/config.json.template`
- `scripts/vpnkit-routing-compat-bypass-test.sh`
- `docs/CONTAINERIZED_VPNKIT_RUNBOOK.md`
- `README.md` if a top-level note is useful

Acceptance criteria:
- Default config exposes `VPNKIT_IPV6_POLICY=block` and sing-box DNS defaults to IPv4-only (`ipv4_only`).
- IPv6 client traffic is explicitly blocked/dropped where applicable via container routing setup.
- Existing compat bypass dry-run behavior remains covered.
- Docs state current vpnkit is IPv4-only and give safe verification/deploy steps.
- No secrets/generated profiles/logs are committed.

Test plan:
- Positive:
  - `bash -n` on touched shell scripts passes.
  - Dry-run routing test asserts IPv6 block rules and existing bypass rules.
  - `docker compose config` renders env defaults including IPv6 policy.
  - `sing-box check` on a safe temp/rendered config if local binary available.
- Negative:
  - Invalid `VPNKIT_IPV6_POLICY` fails with clear error in setup script.
- Edge cases:
  - If `ip6tables` is unavailable under block policy, setup warns/continues only if IPv6 is absent? Implementer should choose safest non-breaking behavior and document.
- Manual:
  - No live deploy; provide operator commands for VPS/Deck validation.

Dependencies:
- Depends on: none.
- Blocks: final verification/report.
- Can run parallel with: none; keep slice whole.

Executor:
- `aad-implementer`.

## Dependency graph / execution ledger
- Slice stays whole: one runtime policy boundary and one acceptance story.
- Wave 1: delegate Task 1 to `aad-implementer`.
- Wave 2: owner reviews report/diff, runs/records final verification, commits if implementer did not, pushes branch if safe.

## Execution status
- 2026-06-02: plan created; pre-dispatch gate passed for Task 1.
