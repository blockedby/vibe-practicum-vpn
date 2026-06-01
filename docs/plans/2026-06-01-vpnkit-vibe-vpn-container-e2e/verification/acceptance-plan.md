# Acceptance plan for apply-adapter follow-up fix audit

## Audit target
- Branch: `pi/containerized-vpnkit-openvpn-singbox`
- Current HEAD: `20f1ce7 Fix vpnkit apply hostname bootstrap`
- Scope: follow-up fix for the container-safe `vibe-vpn apply best` post-switch failure in `scripts/vpnkit-vibe-vpn-e2e.sh --switching`

## Root acceptance criteria to audit
1. Container-safe switching works after apply/failover.
2. VPS/systemd behavior remains preserved as default.
3. No secrets or VPS mutation are introduced.
4. REDIRECT/DNS path remains intact.
5. E2E integration proves the switched path.
6. Logs and cleanup behavior are preserved.
7. Verification is fresh after the fix commit.

## Evidence to check
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/apply-adapter-fix.md`
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/apply-adapter-fix-slice-owner.md`
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/reports/apply-adapter-slice-owner.md`
- `docs/plans/2026-06-01-vpnkit-vibe-vpn-container-e2e/verification/real-e2e-2026-06-01.md`
- root-owner fresh checks: `go test -count=1 ./internal/singbox ./internal/config ./cmd/vibe-vpn`, `bash -n scripts/vpnkit-vibe-vpn-e2e.sh docker/vpnkit/entrypoint.sh scripts/vpnkit-render-local-configs.sh`, `docker compose config`, `git diff --check HEAD~1..HEAD`

## Decision rule
Accept if the fresh evidence shows baseline/apply/supervisor restart/post-switch DNS+HTTPS+literal-IP passing with selected-native-out logs, while systemd defaults remain unchanged and no secret/VPS mutation or broad NAT bypass is introduced.