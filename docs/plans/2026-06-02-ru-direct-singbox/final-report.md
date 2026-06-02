## Task
- Mission: Deploy the completed RU-direct sing-box Docker/vpnkit change to the live VPS Docker runtime.
- Target: `vibe-practicum` Docker `vpnkit` runtime from worktree `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/ru-direct-singbox`, branch `ru-direct-singbox` @ `d342683`.
- Boundaries: VPS Docker runtime only; no Steam Deck deployment; no native service rollback/enablement; no committed secrets/logs/generated profiles.
- Done when: live persisted sing-box config contains RU direct rule sets, container is healthy, and live OpenVPN client regression passes.

## Context
- Task package: `docs/plans/2026-06-02-ru-direct-singbox`
- Slice structure: one deployment slice, because the root request had one live runtime ownership boundary and one acceptance story.
- Slice report: `reports/aad-slice-owner-vps-deploy.md`
- Verification artifact: `verification/vps-deploy.md`

## Spec compliance
- Requirement / AC: Verify branch cleanliness and predeploy readiness.
  - Status: done.
  - Evidence: slice reported clean branch plus fresh `go test ./...`; root recheck found only task-package evidence docs modified/untracked after deployment.
  - Gap if any: none.
- Requirement / AC: Deploy to VPS Docker vpnkit runtime only.
  - Status: done.
  - Evidence: `/opt/vpnkit/src` synced to `d342683`, `vpnkit:vps` rebuilt, Docker container `vpnkit` recreated on `vibe-practicum` only.
  - Gap if any: none.
- Requirement / AC: Persisted live sing-box config is intentionally refreshed and contains RU direct rules.
  - Status: done.
  - Evidence: `/opt/vpnkit/state/sing-box/config.json` / container `/var/lib/vpnkit/sing-box/config.json` includes `geoip-ru` and `geosite-category-ru` routed to `direct-out`.
  - Gap if any: none.
- Requirement / AC: Runtime is healthy after restart/recreate.
  - Status: done.
  - Evidence: root recheck showed `vpnkit vpnkit:vps 0.0.0.0:1194->1194/udp` and `sing-box`, `openvpn`, `vibe-vpn daemon` processes alive.
  - Gap if any: none.
- Requirement / AC: Live OpenVPN client regression passes.
  - Status: done.
  - Evidence: slice run and root re-run both passed with `10.89.0.2/24`, DNS `NOERROR`, HTTPS `200`, literal-IP HTTPS `200`.
  - Gap if any: none.

## Acceptance verification
- AC1: Predeploy branch state clean and local acceptance evidence fresh enough / targeted predeploy check passes.
  - Covered by: `git status --porcelain=v1`, same-day local Docker lab final report, and fresh `go test ./...` before deploy.
  - Result: passed.
  - Evidence: `verification/vps-deploy.md` predeploy section.
- AC2: VPS Docker runtime updated from this branch without touching Steam Deck/native runtime.
  - Covered by: deployment slice actions on `vibe-practicum` only.
  - Result: passed.
  - Evidence: `/opt/vpnkit/src/.deployed-git-rev=d342683`; `vpnkit:vps` rebuilt; `vpnkit` recreated with existing Docker bind-mount runtime.
- AC3: Persisted live sing-box config replaced/rerendered and verified to include RU direct rule sets.
  - Covered by: generated config installed to `/opt/vpnkit/state/sing-box/config.json` and verified inside container.
  - Result: passed.
  - Evidence: grep lines for `geoip-ru`, `geosite-category-ru`, `direct-out` in `verification/vps-deploy.md` and root recheck.
- AC4: Container running safely after recreate with expected processes.
  - Covered by: `docker ps`, `docker exec ps`, and logs.
  - Result: passed.
  - Evidence: container up on `0.0.0.0:1194->1194/udp`; OpenVPN, sing-box, and vibe-vpn daemon listed.
- AC5: Live OpenVPN client regression passes.
  - Covered by: `scripts/vpnkit-steamdeck-client-test.sh --endpoint 45.12.74.211 --port 1194 --runtime docker --profile secrets/vps/openvpn/client/test-client.ovpn --log-file /tmp/vps-client-test-ru-direct-root.log`.
  - Result: passed.
  - Evidence: `inet 10.89.0.2/24`, `status: NOERROR`, `https-test http_code=200`, `literal-ip-test http_code=200`.
- AC6: Task package evidence/report updated.
  - Covered by: `reports/aad-slice-owner-vps-deploy.md`, `verification/vps-deploy.md`, this `final-report.md`, and `plan.md` ledger update.
  - Result: passed.
  - Evidence: current task package files.

## System readiness
- Routes / registration: done; live Docker publishes `0.0.0.0:1194->1194/udp` and `[::]:1194->1194/udp`.
- Services / APIs: done; OpenVPN, sing-box, and vibe-vpn daemon are alive in the container.
- Config / env / secrets: done; existing live gitignored `/opt/vpnkit/secrets` and `/opt/vpnkit/state` were reused; no secret values recorded.
- Permissions / access: done for this deploy; SSH/sudo access on `vibe-practicum` worked.
- Database / migrations: not relevant.
- Frontend-backend integration: not relevant.
- Runtime / deployment wiring: done; preserved the existing host bind-mount Docker topology instead of switching to compose named volumes.

## Verification run
- Local / targeted checks:
  - `go test ./...`: passed before deploy per slice report.
  - Root `git status --short`: passed for artifact safety; only task-package docs changed, no `secrets/` present, log artifact removed.
- Remote checks / live runtime:
  - Root `ssh vibe-practicum 'sudo docker ps ...; sudo docker exec vpnkit ps ...; sudo docker exec vpnkit grep ... /var/lib/vpnkit/sing-box/config.json'`: passed.
  - Root live client regression command above: passed.
- Remote checks / CI:
  - Status: not applicable; no PR/CI action requested for this live deployment.

## Issues
### Issue R-01: Persisted live config would not update from image rebuild alone
- Description: VPS container uses host bind mount `/opt/vpnkit/state/sing-box -> /var/lib/vpnkit/sing-box`; image template changes alone do not replace the live config.
- Evidence: slice `docker inspect` evidence and live config path.
- Resolution: regenerated and installed the config into `/opt/vpnkit/state/sing-box/config.json`, then verified the container-mounted file.
- Depends on: none.

### Issue R-02: Existing live runtime was hand-run Docker with bind mounts, not compose-labelled
- Description: Existing `vpnkit` container had no compose labels and used `/opt/vpnkit/{secrets,state,logs}` bind mounts.
- Evidence: slice `docker inspect` evidence.
- Resolution: recreated with explicit `docker run` matching the existing runtime topology to avoid accidental state/volume migration.
- Depends on: none.

## Side findings
- Blocking findings folded into active work: R-01, R-02.
- Non-blocking findings tracked separately: none.

## Verdict
- Status: success.
- Goal state: fully achieved.
- Final readiness: ready.
- Summary: RU-direct sing-box routing is deployed live on `vibe-practicum` Docker vpnkit; persisted config and runtime health are verified, and the live OpenVPN client regression passed.
