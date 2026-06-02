# Plan: Deploy vpnkit compat bypass to VPS and verify VPS-side OpenVPN client

## Task intake
- Goal: deploy current `vpnkit-compat-bypass` branch (`e452f4a` / `origin/vpnkit-compat-bypass`) to VPS host `vibe-practicum` as the running `vpnkit` Docker runtime.
- In scope: preserve `/opt/vpnkit` mounted secret/state/log directories; keep required runtime envs; ensure persisted `/var/lib/vpnkit/sing-box/config.json` has `dns.strategy=ipv4_only`; run an OpenVPN client test container on the VPS itself and explicitly check A and AAAA DNS behavior through OpenVPN, with AAAA returning zero answers; rollback on failure.
- Out of scope: code changes, secret changes, deleting persistent state/logs, native-service rollback unless Docker rollback fails.
- Done-state: VPS `vpnkit` container runs image built from requested branch with required envs and mounts, sing-box persisted config is IPv4-only, VPS-side client test passes A/AAAA/HTTPS checks, exact commands and runtime state are recorded.
- Blocking unknowns: exact current remote image/container state and available client-test image/profile path must be discovered before mutation.

## Repo orientation
- Repo root guidance read: `AGENTS.md`, worktree `AGENTS.md`, `README.md`.
- Relevant docs: `docs/plans/2026-06-02-vpnkit-compat-bypass/verification/live-vps.md`, `docs/plans/2026-06-01-steamdeck-podman-vpnkit/verification/vps-docker-cutover-2026-06-01.md`.
- Likely remote root: `/opt/vpnkit`; container image/tag: `vpnkit:vps`; container name: `vpnkit`.
- Verification commands: `ssh vibe-practicum ... docker inspect/logs/exec/run`, `jq` on persisted config, OpenVPN client container with `dig` A/AAAA and curl.

## Reuse discovery
- Reuse existing remote deployment layout and tags from previous live-vps evidence.
- Reuse repo `docker/vpnkit/Dockerfile` and existing `/opt/vpnkit/src` source checkout.
- Reuse current remote mounted directories under `/opt/vpnkit` by inspecting current container mounts before restart.
- Reuse VPS-hosted client profile under mounted secrets instead of copying/committing secrets.

## Missing pieces
- Snapshot current remote state and tag previous image for rollback.
- Update remote source to requested branch/head.
- Rebuild `vpnkit:vps` and restart with required envs/mounts/ports/capabilities.
- Force/rerender persisted sing-box config so `/var/lib/vpnkit/sing-box/config.json` uses `dns.strategy=ipv4_only`.
- Run VPS-side OpenVPN client container and record DNS A/AAAA evidence.

## Plan tasks

### Task 1: Snapshot and prepare remote rollback
Acceptance criteria:
- Current image/container configuration recorded.
- Previous image tagged for rollback.
- `/opt/vpnkit` secret/state/log directories not removed.
Test plan:
- `docker inspect`, `docker image tag`, `find/ls` key dirs.
Executor: owner ops (live SSH, no code edits).
Status: pending.

### Task 2: Deploy requested branch as Docker runtime
Acceptance criteria:
- `/opt/vpnkit/src` is on `vpnkit-compat-bypass` at `e452f4a` or current origin branch.
- `vpnkit:vps` is rebuilt from that source.
- Container `vpnkit` runs with required envs and existing mounts/ports/caps.
- persisted `/var/lib/vpnkit/sing-box/config.json` has `dns.strategy=ipv4_only`.
Test plan:
- `git rev-parse`, `docker inspect`, `docker exec`, `jq`.
Executor: owner ops.
Status: pending.

### Task 3: VPS-side OpenVPN client acceptance test
Acceptance criteria:
- Client container runs on `vibe-practicum`, connects to running `vpnkit`, gets `10.89.0.x/24`.
- A query through OpenVPN returns answers.
- AAAA query through OpenVPN returns `NOERROR` with zero answers.
- HTTPS and literal IPv4 HTTPS checks pass or any external-site instability is explicitly classified.
Test plan:
- `docker run --rm --cap-add NET_ADMIN --device /dev/net/tun ... openvpn ... dig ... curl ...` from VPS.
Executor: owner ops.
Status: pending.

## Dependency graph
- Task 1 must complete before mutation.
- Task 2 depends on Task 1.
- Task 3 depends on Task 2.
- Rollback path: if Task 2/3 fails in current-goal way, restore previous image/config/container settings and report unresolved evidence.

## Execution ledger

### Task 1: Snapshot and prepare remote rollback
Status: done.
Evidence:
- Previous `vpnkit:vps` tagged as `vpnkit:vps-pre-compat-bypass-vps-test-20260602T042125Z`.
- Backup tar created at `/root/vpnkit-pre-compat-bypass-vps-test-20260602T042125Z.tar.gz`.
- Persisted sing-box config backup copied before IPv4-only rewrite.

### Task 2: Deploy requested branch as Docker runtime
Status: done.
Evidence:
- `/opt/vpnkit/src/.deployed-git-rev` = `e452f4a029d9e3dfa8a28761a77fa28ec89c276f`.
- `vpnkit:vps` rebuilt on VPS; image id `sha256:edf889b08567dd3580146f98f78d072f5a0891fd642ae76adc433cfe688d999d`.
- Running container `0478c6408769` exposes `0.0.0.0:1194->1194/udp` and has required envs/mounts.
- `/opt/vpnkit/state/sing-box/config.json` has `.dns.strategy = ipv4_only`.

### Task 3: VPS-side OpenVPN client acceptance test
Status: done.
Evidence:
- VPS-built client-test image `vpnkit-ovpn-client-test:vps` ran on `vibe-practicum`.
- OpenVPN client received `10.89.0.2/24` and default split routes through `10.89.0.1`.
- A query for `api.openai.com` via `@8.8.8.8` returned `NOERROR` with 2 A answers.
- AAAA query for `api.openai.com` via `@8.8.8.8` returned `NOERROR` with 0 answers.
- HTTPS `example.com` returned 200; literal IPv4 HTTPS to `1.1.1.1` returned 200.

## Acceptance verification

- AC1: Deploy current `vpnkit-compat-bypass` branch/head to VPS Docker runtime.
  - Result: passed.
  - Evidence: `/opt/vpnkit/src/.deployed-git-rev` and rebuilt `vpnkit:vps` image in `verification/vps-deploy.md`.
- AC2: Preserve mounted secret/state/log directories under `/opt/vpnkit`.
  - Result: passed.
  - Evidence: Docker inspect mounts list in `verification/vps-deploy.md`.
- AC3: Required runtime envs set exactly, including IPv6 policy and compat bypass controls.
  - Result: passed.
  - Evidence: Docker inspect env list in `verification/vps-deploy.md`.
- AC4: Persisted sing-box config uses `dns.strategy=ipv4_only`.
  - Result: passed.
  - Evidence: `sudo jq -r '.dns.strategy' /opt/vpnkit/state/sing-box/config.json` => `ipv4_only`.
- AC5: VPS-side OpenVPN client container verifies A and AAAA behavior through OpenVPN.
  - Result: passed.
  - Evidence: client container output: tun `10.89.0.2/24`, A `NOERROR` with 2 answers, AAAA `NOERROR` with 0 answers.
- AC6: Rollback if failure.
  - Result: not needed; rollback artifacts available.

## Issues

### R-01: Persisted sing-box config initially lacked dns.strategy
- Description: `/opt/vpnkit/secrets/vps/rendered/sing-box/config.json` did not include `.dns.strategy`; copying it directly would not satisfy the current deployment requirement.
- Evidence: initial `jq -e '.dns.strategy == "ipv4_only"'` returned false.
- Resolution: wrote persisted `/opt/vpnkit/state/sing-box/config.json` from rendered config with `jq '.dns.strategy = "ipv4_only"'`, then verified `ipv4_only` before/after container start.

## Final done-state

Done. VPS runtime is deployed and verified. No unresolved current-goal blockers. No GitHub follow-up issues required for this deploy.
