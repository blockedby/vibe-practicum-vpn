## Task
- Mission: Deploy the completed RU-direct sing-box Docker/vpnkit change to the live VPS Docker runtime and prove readiness.
- Target: VPS `vibe-practicum`, `/opt/vpnkit`, image `vpnkit:vps`, container `vpnkit`, OpenVPN `45.12.74.211:1194/udp`.
- Boundaries: VPS Docker runtime only; no Steam Deck mutation; no native service changes/rollback; no committed secrets/logs/generated configs/profiles.
- Done when: live persisted sing-box config includes RU rule sets routed to `direct-out`, container is healthy with OpenVPN/sing-box/vibe-vpn daemon, and live OpenVPN client regression passes.
- Expected evidence: branch/predeploy state, deploy commands/actions, live config/process/log excerpts, client-test output, and acceptance verdict.

## Context
- Thread: root task live deployment slice.
- Slice: stayed whole; no implementer or sub-slice delegation was needed because this was one live deployment acceptance story.
- Task name: RU direct sing-box routing / VPS deploy.
- Task package: `docs/plans/2026-06-02-ru-direct-singbox`.
- Report path: `docs/plans/2026-06-02-ru-direct-singbox/reports/aad-slice-owner-vps-deploy.md`.
- Verification artifact: `docs/plans/2026-06-02-ru-direct-singbox/verification/vps-deploy.md`.
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/ru-direct-singbox`.
- Branch: `ru-direct-singbox` @ `d342683`.
- Verify scope: live VPS Docker vpnkit runtime readiness.

## Spec compliance
- Requirement / AC: Deploy from ready branch to VPS Docker runtime only.
  - Status: done.
  - Evidence: synced `/opt/vpnkit/src` to current branch source, wrote `.deployed-git-rev=d342683`, rebuilt `vpnkit:vps`, recreated only Docker container `vpnkit` on `vibe-practicum`.
  - Gap if any: none.
- Requirement / AC: Persisted live sing-box config intentionally refreshed.
  - Status: done.
  - Evidence: installed regenerated config to `/opt/vpnkit/state/sing-box/config.json`; container `/var/lib/vpnkit/sing-box/config.json` grep shows `geoip-ru`, `geosite-category-ru`, and `direct-out` rule-set routes.
  - Gap if any: none.
- Requirement / AC: Runtime remains healthy with expected services.
  - Status: done.
  - Evidence: `docker ps` shows `vpnkit vpnkit:vps 0.0.0.0:1194->1194/udp`; `docker exec ps` shows `sing-box`, `openvpn`, `vibe-vpn daemon`.
  - Gap if any: none.
- Requirement / AC: Live client path works.
  - Status: done.
  - Evidence: local `scripts/vpnkit-steamdeck-client-test.sh --endpoint 45.12.74.211 --port 1194 --runtime docker ...` output showed `10.89.0.2/24`, DNS `NOERROR`, `https-test http_code=200`, `literal-ip-test http_code=200`.
  - Gap if any: none.

## Acceptance verification
- AC1: Predeploy branch state clean and local Docker lab evidence fresh enough or targeted predeploy check passes.
  - Covered by: `git status --porcelain=v1`, existing same-day local final report, and fresh `go test ./...`.
  - Result: passed.
  - Evidence: worktree clean; `go test ./...` all packages passed/cached.
- AC2: VPS Docker runtime updated from this branch without touching Steam Deck/native runtime.
  - Covered by: source sync/build/recreate on `vibe-practicum` only.
  - Result: passed.
  - Evidence: `/opt/vpnkit/src/.deployed-git-rev=d342683`; `docker build -t vpnkit:vps`; `docker run -d --name vpnkit ... vpnkit:vps` with existing Docker runtime env/mounts.
- AC3: Persisted live sing-box config replaced/rerendered and verified to include RU rule sets routed to `direct-out`.
  - Covered by: regenerated and installed `/opt/vpnkit/state/sing-box/config.json`; verified inside container.
  - Result: passed.
  - Evidence: grep showed `rule_set: geoip-ru -> direct-out`, `rule_set: geosite-category-ru -> direct-out`, and both rule-set tags/download detours.
- AC4: Container running safely after recreate, logs healthy enough, expected processes alive.
  - Covered by: `docker ps`, `docker exec ps`, `docker logs`.
  - Result: passed.
  - Evidence: container up on `0.0.0.0:1194->1194/udp`; logs showed rule-set updates, sing-box inbounds ready, OpenVPN initialization complete, and vibe-vpn daemon started.
- AC5: Live OpenVPN client regression passes.
  - Covered by: local client-test helper against `45.12.74.211:1194`.
  - Result: passed.
  - Evidence: client received `inet 10.89.0.2/24`; dig returned `status: NOERROR`; HTTPS and literal-IP tests both returned `http_code=200`.
- AC6: Task package has concise deploy evidence and final slice verdict.
  - Covered by: `verification/vps-deploy.md` and this report.
  - Result: passed.
  - Evidence: both files written in task package.

## System readiness
- Routes / registration: done; Docker port publish remains `0.0.0.0:1194->1194/udp` and `[::]:1194->1194/udp`.
- Services / APIs: done; OpenVPN, sing-box, and vibe-vpn daemon are alive in the container.
- Config / env / secrets: done; reused existing live gitignored `/opt/vpnkit/secrets` and `/opt/vpnkit/state`; did not print or commit secret values.
- Permissions / access: done; deployment used SSH/sudo access to `vibe-practicum` only.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: done; preserved existing live bind-mount Docker runtime rather than switching to a new named-volume compose state during this live deploy.

## Verification run
- Local / targeted checks:
  - `git status --porcelain=v1`: passed.
    - Evidence: no output; branch `ru-direct-singbox`.
  - `go test ./...`: passed.
    - Evidence: all Go packages passed/cached.
- Remote checks / live runtime:
  - `ssh vibe-practicum 'sudo docker ps --filter name=^/vpnkit$ ...'`: passed.
    - Evidence: `vpnkit vpnkit:vps 0.0.0.0:1194->1194/udp, [::]:1194->1194/udp Up ...`.
  - `ssh vibe-practicum 'sudo docker exec vpnkit ps auxww | grep -E "[o]penvpn|[s]ing-box|[v]ibe-vpn daemon"'`: passed.
    - Evidence: all three processes listed.
  - `ssh vibe-practicum 'sudo docker exec vpnkit grep -n "geoip-ru\|geosite-category-ru\|direct-out" /var/lib/vpnkit/sing-box/config.json'`: passed.
    - Evidence: RU rule-set routes and rule-set definitions present.
  - `scripts/vpnkit-steamdeck-client-test.sh --endpoint 45.12.74.211 --port 1194 --runtime docker --profile secrets/vps/openvpn/client/test-client.ovpn --log-file logs/vps-client-test-45.12.74.211.log`: passed.
    - Evidence: `10.89.0.2/24`, DNS `NOERROR`, HTTPS `200`, literal-IP HTTPS `200`. The script could not tee to the requested log path due local log-file permission, so raw log artifact was not retained; the copied gitignored profile and attempted log were removed.
- Remote checks / CI:
  - Status: not applicable for this live-deploy slice; no PR/CI action requested here.

## Issues
### Issue R-01: Live persisted sing-box config needed manual replacement rather than relying on container image template
- Description: The running VPS container used host bind mounts under `/opt/vpnkit/state` for `/var/lib/vpnkit/sing-box`, so rebuilding the image alone would not update the persisted runtime config.
- Evidence: `docker inspect vpnkit` showed `/opt/vpnkit/state/sing-box -> /var/lib/vpnkit/sing-box`.
- Resolution: Regenerated the sing-box config from the new template using the existing live `selected-native-out`, installed it to `/opt/vpnkit/secrets/vps/rendered/sing-box/config.json` and `/opt/vpnkit/state/sing-box/config.json`, then verified the live container file after recreate.
- Depends on: none.

### Issue R-02: Existing live Docker runtime was not compose-labelled and used host bind mounts
- Description: `docker inspect vpnkit` had no compose labels and existing mounts were `/opt/vpnkit/secrets`, `/opt/vpnkit/state`, and `/opt/vpnkit/logs`; the branch compose file would otherwise create named state volumes and require source-local secrets.
- Evidence: `docker inspect vpnkit --format '{{json .Config.Labels}}'` returned `{}`; mount list showed host bind paths.
- Resolution: Recreated the container with an explicit `docker run` matching the existing live env/mount/port conventions to avoid changing runtime state topology during this deploy.
- Depends on: none.

## Side findings
- Blocking findings folded into active work: R-01 and R-02.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: success.
- Goal state: fully achieved.
- Final readiness: ready.
- Summary: RU-direct sing-box routing is live on `vibe-practicum` Docker vpnkit; persisted config and runtime health are verified, and the live OpenVPN client regression passed.

## Next-agent brief
- Objective: Root owner can integrate this live-deploy result into the root final decision.
- Target: `docs/plans/2026-06-02-ru-direct-singbox/verification/vps-deploy.md` and this report.
- Settled already: VPS Docker runtime deployed from `d342683`; no Steam Deck/native services touched; live client regression green.
- Boundaries: keep secrets/logs/generated profiles out of commits.
- Verification target: optional root owner re-check of `docker ps`/client path if desired; otherwise acceptance evidence is complete.
- Expected output: root final done-state/report.
