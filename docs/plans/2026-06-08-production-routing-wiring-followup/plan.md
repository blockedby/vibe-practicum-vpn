# Production routing wiring follow-up plan

## Intake

Goal: commit the production-only vpnkit routing wiring follow-up from a clean branch based on `origin/main`, merge it to `main`, redeploy/update all known vpnkit production servers, and return the primary checkout at `/home/kcnc/code/tools/vibe-practicum-vpn` to branch `main`.

Public-safety constraints:
- Do not commit or print secrets, private endpoints, generated OpenVPN profiles, rendered configs, raw logs, private CIDR values, or private endpoint values.
- Live mutation is explicitly approved for the vpnkit Compose service on the known production servers only.
- Preserve untracked user files in the primary checkout.

## Acceptance criteria

AC1. Repository changes are made on a clean branch from `origin/main`, not the dirty primary checkout.
AC2. `docker/vpnkit/entrypoint.sh` readiness is mode-aware: `tun` waits for the TUN link, `tproxy` waits for TCP 2082, and `redirect`/default waits for TCP 2082 plus UDP 5353.
AC3. `docker-compose.yml` passes `OVPN_CIDR` with a public-safe default matching repo routing defaults and allows production `.env` override.
AC4. Public docs/config examples document redirect-mode consistency without secrets.
AC5. Practical tests/checks cover mode-aware readiness and compose env, plus `bash -n` and existing routing tests where available.
AC6. Branch is committed, pushed, PR-first path used if possible, and merged into `main`.
AC7. Updated `main` is deployed to all known vpnkit production servers with backup/rollback awareness and without mutating unrelated production containers.
AC8. Each server is verified after deploy: vpnkit running, deployed entrypoint has mode-aware wait and setup-routing after sing-box restart, internal sing-box restart works, routing rules present, and safe smoke tests pass.
AC9. Primary repository folder is on branch `main` with user untracked files preserved.
AC10. Final report records files changed, PR/merge commit, servers updated in sanitized form, verification evidence, rollback tags, and checkout state.

## Slice structure

One implementation slice followed by one deployment slice preserves ownership clarity:

### Slice 1: repository implementation, PR, and merge
- Owner: `aad-slice-owner`
- Worktree: `.worktrees/prod-routing-wiring-followup`
- Branch: `prod-routing-wiring-followup`
- Report path: `docs/plans/2026-06-08-production-routing-wiring-followup/reports/repo-implementation-slice.md`
- Goal: implement public-safe repo changes, tests/docs, commit, push, open PR, and merge to `main`.
- Depends on: none.
- Blocks: Slice 2.
- Acceptance: AC1-AC6, plus safe evidence for AC10 repo fields.

### Slice 2: production deploy and verification
- Owner: `aad-slice-owner`
- Worktree: primary checkout or a clean main checkout after Slice 1 merge.
- Report path: `docs/plans/2026-06-08-production-routing-wiring-followup/reports/production-deploy-slice.md`
- Goal: deploy merged `main` to known vpnkit production servers and verify runtime health.
- Depends on: Slice 1 merged `main`.
- Blocks: final root report.
- Acceptance: AC7-AC8 and deploy evidence for AC10.

### Root checkout/finalization
- Owner: `aad-root-owner`
- Goal: put `/home/kcnc/code/tools/vibe-practicum-vpn` on branch `main`, preserving untracked user files; integrate reports and produce final done-state.
- Acceptance: AC9-AC10.

## Slice 1 execution plan

Pre-dispatch gate evidence:
- Task intake: Slice 1 goal is repo-only implementation, tests, PR, merge to `main`; live deploy is out of scope.
- Repo orientation: target files are `docker/vpnkit/entrypoint.sh`, `docker/vpnkit/setup-routing.sh`, `docker-compose.yml`, public Docker docs/examples, and shell tests under `tests/` or `scripts/`; no `Taskfile.yml` exists in this worktree.
- Reuse discovery: `setup-routing.sh` defaults `VPNKIT_ROUTING_MODE=redirect`, `OVPN_CIDR=10.89.0.0/24`, `TPROXY_PORT=2082`, `DNS_REDIRECT_PORT=5353`, and `SINGBOX_TUN_IFACE=sb-tun0`; `entrypoint.sh` already calls `wait_for_singbox_inbounds` and `setup-routing.sh` after `start_singbox` in both initial start and restart paths; existing `scripts/vpnkit-routing-compat-bypass-test.sh` is the shell render-test pattern.
- Missing pieces: mode-aware readiness logic/test coverage; compose `OVPN_CIDR` env; public docs/config example note for redirect-mode consistency; final verification artifact/report/PR/merge evidence.
- Ownership model: keep Slice 1 whole; one `aad-implementer` task is cheaper than sub-slicing because the code, docs, tests, and PR evidence share one runtime wiring acceptance story.

### Task 1: mode-aware vpnkit repository wiring

Goal:
- Make the repo public-safe production routing wiring consistent for redirect/default, tproxy, and tun modes, with practical automated evidence.

Boundary:
- System area: vpnkit container startup/routing config, Compose env wiring, public docs/examples, shell render tests.
- Primary verification: targeted shell tests for entrypoint readiness/compose env plus `bash -n` and existing routing test(s).

Existing pattern / reuse:
- Follow defaults and mode names in `docker/vpnkit/setup-routing.sh`.
- Preserve `restart_singbox()` ordering in `docker/vpnkit/entrypoint.sh`: `start_singbox`, `wait_for_singbox_inbounds`, then `/usr/local/bin/setup-routing.sh`.
- Follow shell test style from `scripts/vpnkit-routing-compat-bypass-test.sh` / `tests/*.sh`.
- Public docs should follow `docs/DOCKER_SETUP.md` safety language and avoid private values.

Missing change:
- Implement mode-aware `wait_for_singbox_inbounds`:
  - `tun`: wait for `${SINGBOX_TUN_IFACE:-sb-tun0}` link visibility and do not require redirect ports.
  - `tproxy`: wait for TCP 2082 only.
  - `redirect`/default: wait for TCP 2082 and UDP 5353.
- Add `OVPN_CIDR: "${OVPN_CIDR:-10.89.0.0/24}"` (or equivalent) in `docker-compose.yml` so `.env` can override.
- Document redirect-mode consistency in tracked public docs/config examples without secrets.
- Add/update practical shell tests for mode-aware readiness and compose env if practical.

Scope / likely files:
- `docker/vpnkit/entrypoint.sh`
- `docker-compose.yml`
- `docs/DOCKER_SETUP.md` and/or sanitized config example docs
- `tests/` and/or `scripts/` shell render tests
- task package files under `docs/plans/2026-06-08-production-routing-wiring-followup/`

Acceptance criteria:
- AC1: work remains on branch `prod-routing-wiring-followup` in the delegated worktree.
- AC2: entrypoint readiness is mode-aware as specified.
- AC3: Compose passes `OVPN_CIDR` with public-safe default matching `setup-routing.sh` while allowing `.env` override.
- AC4: public docs/config examples explain redirect-mode consistency and contain no secrets/private endpoint values.
- AC5: practical tests/checks cover the changed readiness and compose env paths plus syntax/existing routing checks.
- AC6: changes are committed, pushed, PR opened/updated, and merged to `main` after acceptable checks.

Test plan:
- Positive:
  - New/updated shell test proves tun readiness waits on interface and skips redirect ports.
  - New/updated shell test proves tproxy readiness waits on TCP 2082 only.
  - New/updated shell test proves redirect/default readiness waits on TCP 2082 and UDP 5353.
  - New/updated check proves Compose includes `OVPN_CIDR` default/override expression.
  - `bash -n docker/vpnkit/entrypoint.sh docker/vpnkit/setup-routing.sh scripts/*.sh tests/*.sh` or narrow equivalent if glob limitations exist.
  - Existing routing render test: `scripts/vpnkit-routing-compat-bypass-test.sh`.
- Negative:
  - Test should fail if tun mode requires redirect ports or if redirect/default omits DNS UDP readiness.
- Manual:
  - Use `gh` to open/view PR and check CI status if available; no production SSH/deploy.

Dependencies:
- Depends on: none.
- Blocks: Slice 2 production deploy.
- Can run parallel with: none; one implementation task is sufficient.

Executor:
- `aad-implementer`, report `reports/aad-implementer-repo-wiring.md`, progress `progress/aad-implementer-repo-wiring.md`.

## Verification ledger

- Slice 1 local implementation: done.
  - Changed `docker/vpnkit/entrypoint.sh`, `docker-compose.yml`, `docs/DOCKER_SETUP.md`, and `tests/vpnkit-production-routing-wiring-test.sh`.
  - Evidence: `verification/repo-local.md` and `reports/aad-implementer-repo-wiring.md`.
  - Fresh checks passed: `bash -n docker/vpnkit/entrypoint.sh docker/vpnkit/setup-routing.sh scripts/*.sh tests/*.sh`; `./tests/vpnkit-production-routing-wiring-test.sh`; `./scripts/vpnkit-routing-compat-bypass-test.sh`; sanitized `docker compose config --format json` assertion for `OVPN_CIDR`.
  - Pending: commit, push, PR, CI if any, merge to `main`, final Slice 1 report.
- Pending Slice 2 report.
- Pending root final verification and checkout state.
