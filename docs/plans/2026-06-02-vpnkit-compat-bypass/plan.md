# Plan: vpnkit compatibility bypass

## Task intake
Goal: add compatibility-mode support so OpenVPN/router clients behind vpnkit can reach a nested work OpenVPN endpoint directly (`vpn.proofix.tv:1194`, UDP by default, explicit proto supported), with optional direct ICMP, while preserving redirect-mode TCP and DNS through sing-box and avoiding broad direct VPS NAT.

In scope:
- Configurable env vars in vpnkit routing for scoped direct bypass destinations/protocols.
- Default compatibility endpoint docs for `vpn.proofix.tv:1194/udp`.
- Tests/static checks proving shell syntax and compose config.

Out of scope:
- Broad MASQUERADE/NAT for all OpenVPN client traffic.
- Secret/generated OpenVPN profiles.
- Live VPS mutation or runtime validation.

Done state: branch pushed with coherent commit, docs and tests updated, acceptance commands run and recorded.

Blocking unknowns: endpoint protocol unspecified; assumption is UDP default with explicit proto config supported.

## Repo orientation
- `docker/vpnkit/setup-routing.sh` owns routing modes. Redirect mode currently redirects TCP to sing-box and UDP/53 to sing-box; no broad POSTROUTING NAT.
- `docker-compose.yml` sets `VPNKIT_ROUTING_MODE=redirect` and vpnkit env.
- `docs/CONTAINERIZED_VPNKIT_RUNBOOK.md` documents redirect mode and no broad NAT.
- Verification commands: `bash -n docker/vpnkit/setup-routing.sh`, shellcheck where available, `docker compose config`.

## Reuse discovery
- Existing scoped chains: `OVPN_REDIRECT_TO_SINGBOX` in nat PREROUTING.
- Existing env style: shell defaults via `${VAR:-default}`; compose passes env with defaults.
- Existing docs emphasize scoped redirect and no broad NAT; preserve that language.

## Missing pieces
- Env vars for compatibility bypass enablement/host/port/proto and optional ICMP direct.
- DNS resolution of configured bypass hosts into exact destination IP rules at container startup.
- Scoped NAT/forward rules only for matching endpoint/proto and optional ICMP.
- Docs explaining defaults and how to configure `vpn.proofix.tv:1194`.
- Static tests/check scripts if no test harness exists.

## Plan tasks

### Task 1: Scoped compatibility bypass in vpnkit routing
Goal:
- Redirect mode installs exact direct-bypass rules for configured nested OpenVPN endpoints and optional ICMP without broad direct NAT.

Boundary:
- System area: Docker vpnkit routing script, compose env docs.
- Primary verification: shell syntax/static checks plus inspection of deterministic script behavior.

Existing pattern / reuse:
- `docker/vpnkit/setup-routing.sh` env defaults, iptables chain setup, redirect-mode no-broad-NAT policy.

Missing change:
- Add parse/resolve/install logic for endpoint specs with proto support, defaulting to `vpn.proofix.tv:1194/udp` when compatibility mode is enabled.
- Add optional ICMP direct rules controlled by env.

Scope / likely files:
- `docker/vpnkit/setup-routing.sh`
- `docker-compose.yml`
- docs/tests as needed

Acceptance criteria:
- TCP and UDP/53 redirect rules remain in redirect mode.
- Direct rules only apply to resolved configured endpoint IP + protocol + port, and optional ICMP destinations, not all client traffic.
- `vpn.proofix.tv:1194` can be enabled/configured with UDP default and explicit proto override.

Test plan:
- Positive: bash -n setup-routing; shellcheck if available; docker compose config.
- Negative: inspect code/docs for no broad `POSTROUTING -s $OVPN_CIDR -j MASQUERADE`.
- Edge: explicit proto tcp/udp accepted, invalid proto rejected.

Dependencies:
- Depends on: none.
- Blocks: final verification.
- Can run parallel with: none.
Executor: aad-implementer.
Report: `reports/aad-implementer-routing.md`.

## Dependency graph
- Wave 1: Task 1 via aad-implementer.
- Wave 2: owner verifies, updates ledger, commits/pushes if not already done.

## Execution ledger
- 2026-06-02: created worktree and initial task package.
- 2026-06-02: aad-implementer implemented Task 1 scoped compatibility bypass in progress; local evidence recorded in `verification/local.md`, final report pending in `reports/aad-implementer-routing.md`.
