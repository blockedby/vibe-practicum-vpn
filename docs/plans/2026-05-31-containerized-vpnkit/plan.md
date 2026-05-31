# Plan: containerized vpnkit OpenVPN -> sing-box lab

## Intake
- Goal: add safe repo scaffolding for a Dockerized `vpnkit` gateway running OpenVPN server plus one sing-box TPROXY/VLESS config, with a separate `ovpn-client-test` container for validation.
- In scope: Dockerfiles, compose, entrypoints/routing/test scripts, sanitized templates, docs/runbook, operator-bound secret copy/render/profile generation workflow.
- Out of scope: committing real secrets, xray runtime paths for this lab, broad permanent NAT bypass for `10.89.0.0/24`, mutating VPS or running production SSH/SCP automatically, unrelated Go behavior changes.
- Done state: repo contains executable scaffolding and runbook; safe local syntax/compose checks pass; live VLESS ACs are either evidenced or explicitly pending operator-provided secrets/live run.
- Blocking unknowns: real copied VPS config/secrets are unavailable in this worktree; live privileged Docker run may be unsafe/unavailable, so runtime acceptance may remain pending with exact commands.

## Repo orientation and reuse
- Repo is Go CLI/tooling plus operational docs/scripts. Existing shell scripts use `#!/usr/bin/env bash` and `set -euo pipefail`.
- `.gitignore` already ignores `secrets/`, `*.key`, `*.conf`; sanitized templates should avoid `.conf` suffix if they need tracking or be force-added only if safe.
- Existing relevant docs: `docs/OPENVPN_ASUS_TPROXY_CANARY.md`, `docs/TPROXY_CANARY.md`, `configs/sing-box/tproxy-canary.json` (tracked sample; inspect before reuse to avoid secrets).
- Verification defaults: `bash -n`, `docker compose config` if available, `grep` for forbidden NAT/secret patterns, optional `go test ./...` because Go should not change.

## Missing pieces
- `docker/vpnkit` image, entrypoint, routing setup, render/helper scripts.
- `docker/ovpn-client-test` image, entrypoint, validation runner.
- Compose file linking gateway and test client via Docker networking.
- Sanitized config templates for OpenVPN server/client and sing-box lab shape.
- Operator runbook/scripts for copying from documented VPS paths into gitignored `secrets/vps/...`, rendering local configs, generating client profile, running and collecting validation evidence.

## Plan tasks

### Task 1: Container lab scaffolding and safe operator workflow
Goal:
- Make the Dockerized gateway/test-client lab runnable by an operator with local secrets while keeping committed files sanitized.
Boundary:
- System area: Docker/runtime wiring and shell scripts/docs.
- Primary verification: shell syntax, compose config validation, static inspection for forbidden NAT and secrets.
Existing pattern / reuse:
- Follow existing script style in `scripts/*.sh`; reuse plan's OpenVPN/TPROXY commands; avoid xray paths.
Missing change:
- Add Dockerfiles, entrypoints, routing/test/render/copy scripts, templates, compose, and runbook/report evidence mapping.
Scope / likely files:
- `docker/vpnkit/**`, `docker/ovpn-client-test/**`, `config/**` or `templates/**`, `scripts/*vpnkit*`, `docker-compose.yml`, `docs/*VPNKIT*`.
Acceptance criteria:
- AC 1-11 are mapped to implemented artifact or pending live/operator action.
- No committed real secrets or full profiles; real inputs stay under `secrets/`.
- No permanent broad NAT bypass for `10.89.0.0/24`.
- Test client uses `remote vpnkit 1194 udp` and runs in separate container.
- sing-box config path uses native VLESS outbound from local rendered secrets, one process, inbound/tproxy `:2082`, DNS rules.
Test plan:
- Positive: `bash -n` on new scripts; `docker compose config` when available; template/static grep checks.
- Negative: grep for forbidden broad NAT and committed secret-looking UUID/private key markers; grep for xray in lab runtime files.
- Manual: live Docker/VLESS validation after operator copies secrets.
Dependencies:
- Depends on: none.
- Blocks: final report.
- Can run parallel with: none (single coherent runtime scaffold).
Executor:
- `aad-implementer`.
Report path:
- `docs/plans/2026-05-31-containerized-vpnkit/reports/aad-implementer-task-1.md`
Progress path:
- `docs/plans/2026-05-31-containerized-vpnkit/progress/aad-implementer-task-1.md`



### Task 2: End-to-end live debug/fix for OpenVPN -> sing-box
Goal:
- Make the containerized lab pass AC1-AC11 end-to-end, or implement the best non-TPROXY architecture with falsifiable evidence that TPROXY local delivery is blocked in this Docker/kernel environment.
Boundary:
- System area: Docker gateway runtime routing, sing-box lab config, client verification scripts, runbook/evidence.
- Primary verification: fresh privileged Docker run showing OpenVPN client IP, tun0 ingress, sing-box/TUN equivalent handling, selected-native-out use, DNS success under sing-box rules, HTTPS/literal-IP success, static safety checks, and commit hash.
Existing pattern / reuse:
- Reuse `docker/vpnkit/setup-routing.sh`, `docker/ovpn-client-test/run-tests.sh`, `scripts/vpnkit-collect-evidence.sh`, existing templates, and prior live evidence in `verification/live-docker-2026-05-31.md`.
Missing change:
- Follow the required ordered debug sequence: (1) add/test scoped INPUT accept for marked local-delivery TPROXY packets; (2) add/run minimal `IP_TRANSPARENT` listener proof; (3) canonicalize iptables/nft policy routing if needed; (4) if TPROXY remains impossible, switch to a sing-box TUN `auto_route`/`auto_redirect` fallback or equivalent that preserves DNS under sing-box and avoids broad MASQUERADE.
Scope / likely files:
- `docker/vpnkit/**`, `docker/ovpn-client-test/**`, `scripts/vpnkit-collect-evidence.sh`, `config/sing-box/config.json.template`, `docker-compose.yml`, `docs/CONTAINERIZED_VPNKIT_RUNBOOK.md`, task package reports/verification.
Acceptance criteria:
- AC1-AC11 from routing packet are proven with fresh redacted evidence, or rejected TPROXY path has concrete blocker evidence and fallback proves equivalent AC4-AC8 behavior.
- Final config has no broad permanent `10.89.0.0/24` MASQUERADE bypass and no xray dependency.
- No secrets are committed or included unredacted in reports/log excerpts.
Test plan:
- Positive: `docker compose build`; `docker compose up -d vpnkit`; `docker compose --profile test up ovpn-client-test`; collect container status, OpenVPN IP, routes/rules/sysctls, netfilter counters/traces, sing-box logs, `dig`, domain HTTPS, literal-IP HTTPS.
- Negative: static grep for broad MASQUERADE, xray dependency, full VLESS/UUID/private-key secret patterns in git/docs; prove DNS is not direct bypass.
- Manual: if TPROXY fails, save minimal transparent listener commands/results and the exact fallback decision evidence.
Dependencies:
- Depends on: Task 1 and available local Docker/secrets already present or operator-provided.
- Blocks: final slice report and PR readiness.
- Can run parallel with: none; ordered debug loop.
Executor:
- `aad-implementer`.
Report path:
- `docs/plans/2026-05-31-containerized-vpnkit/reports/aad-implementer-task-2-end-to-end.md`
Progress path:
- `docs/plans/2026-05-31-containerized-vpnkit/progress/aad-implementer-task-2-end-to-end.md`
Verification artifact:
- `docs/plans/2026-05-31-containerized-vpnkit/verification/implementation-run-2026-06-01.md`

## Dependency graph
- Task 1 -> Task 2 -> final owner verification/report.

## Execution ledger
- 2026-06-01: Plan created; Task 1 ready for `aad-implementer`.
- 2026-06-01: Task 1 implemented directly by slice owner because nested implementer dispatch was unavailable at max subagent depth. Local syntax/compose/static checks passed. Live acceptance remains pending operator secrets/runtime.

- 2026-06-01: Task 2 added for live end-to-end debug/fix following required Opus sequence; ready for `aad-implementer`.

## 2026-06-01 integration update: end-to-end lab fixed

Task 2 status: done with a REDIRECT architecture after TPROXY and TUN fallback diagnostics.

Outcome:
- TPROXY was tested with scoped INPUT accept and a minimal `IP_TRANSPARENT` Perl listener. TPROXY counters matched, but no transparent listener accept occurred, so this Docker/kernel path was rejected with blocker evidence.
- sing-box TUN `auto_route`/`auto_redirect` fallback was tested; tcpdump showed packets leaving `sb-tun0` toward the TUN peer address instead of preserving original destination, so it was rejected for this lab.
- Final working path uses iptables `REDIRECT` (not broad MASQUERADE): TCP from `10.89.0.0/24` to sing-box `redirect` inbound `:2082`, and UDP/53 to sing-box `direct` inbound `:5353` with route action `hijack-dns`.
- DNS and TCP both leave through `outbound/vless[selected-native-out]`.

Fresh verification artifact:
- `docs/plans/2026-05-31-containerized-vpnkit/verification/implementation-run-2026-06-01.md`

Acceptance status:
- AC1-AC10: passed with fresh local Docker evidence.
- AC11: passed; committed as `Fix containerized vpnkit lab routing`.

Caveats:
- sing-box 1.13.11 still requires `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true` for the current DNS object syntax and emits a warning.
- `privileged: true` remains in compose for the local lab harness.
