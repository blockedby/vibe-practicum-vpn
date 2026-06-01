# Apply adapter fix verification

## Summary
- Result: **passed** for the follow-up fix slice.
- Fix claim: the container request-file apply path no longer writes a domain-form selected outbound server into active sing-box config; it pre-resolves the dial address while preserving TLS/SNI fields, matching the initial render bootstrap behavior and avoiding the post-switch sing-box hostname-resolution loop.
- Secrets: real subscription URLs and full links are not recorded here. The real node hostname shown by the e2e runner is omitted from this committed evidence except where already present in untracked local logs.

## Code diagnosis evidence
- `scripts/vpnkit-render-local-configs.sh` already pre-resolved the initial `selected-native-out.server` to avoid a bootstrap loop.
- `cmd/vibe-vpn applyResult` converted selected links through `vless.SingBoxOutbound` and `singbox.ApplyWithRestart`, which previously wrote the selected link's raw domain hostname into the active config for request-file/container mode.
- `config/sing-box/config.json.template` uses Google DoT DNS servers detoured through `selected-native-out`; prior `verification/apply-adapter.md` recorded post-switch DNS timeout and sing-box hostname lookup-loop evidence for the selected server hostname.

## Fresh local checks
```text
$ go test ./internal/singbox
ok   github.com/kcnc/vibe-practicum-vpn/internal/singbox 0.003s

$ go test ./...
ok   github.com/kcnc/vibe-practicum-vpn/cmd/vibe-vpn 1.158s
ok   github.com/kcnc/vibe-practicum-vpn/internal/config (cached)
ok   github.com/kcnc/vibe-practicum-vpn/internal/singbox (cached)
... remaining packages passed/cached; internal/state has no test files

$ go vet ./...
passed

$ go build -o /tmp/vibe-vpn ./cmd/vibe-vpn
passed

$ bash -n scripts/vpnkit-vibe-vpn-e2e.sh docker/vpnkit/entrypoint.sh scripts/vpnkit-render-local-configs.sh
passed

$ docker compose config >/tmp/vpnkit-compose-config.txt
passed

$ git diff --check
passed
```

## Real vpnkit e2e switching run
Command:
```bash
scripts/vpnkit-vibe-vpn-e2e.sh --run-id apply-adapter-fix-20260601T032716Z --switching --cleanup-on-failure --no-cleanup-images
```

Result: **passed**.

Redacted evidence:
- Build and startup passed.
- `vibe-vpn doctor --config /etc/vibe-vpn/config.yaml` passed.
- `vibe-vpn test --limit-kib 64 --max 2` fetched 9 subscription nodes, 8 after filters, tested 2, yielded 1 OK / 1 failed.
- Baseline pre-switch OpenVPN client passed: client received `10.89.0.2`, DNS query succeeded, HTTPS domain check returned 200, literal-IP HTTPS check returned 200.
- `vibe-vpn apply --config /etc/vibe-vpn/config.yaml best` succeeded and wrote a backup under `/var/lib/vibe-vpn/backups/`.
- Supervisor log evidence included `restart requested for sing-box` and a fresh sing-box process start.
- Post-switch OpenVPN client passed: DNS query succeeded, HTTPS domain check returned 200, literal-IP HTTPS check returned 200.
- Redacted sing-box evidence after restart showed `outbound/vless[selected-native-out]` connections to Google DoT `8.8.8.8:853`, HTTPS domain destination, and literal-IP destination; no selected outbound hostname lookup-loop lines were observed in the evidence excerpt.
- Evidence artifact: ignored local file `logs/vpnkit-vibe-vpn-e2e/apply-adapter-fix-20260601T032716Z-evidence.txt`.

## Acceptance mapping
- AC1 Diagnose concrete failure: passed; apply path wrote raw domain server while initial render pre-resolved it, causing the documented loop with selected-outbound-detoured DNS.
- AC2 Robust constrained fix: passed; request-file/container mode pre-resolves only the selected outbound dial address, preserves TLS/SNI, leaves systemd mode unchanged, adds no NAT/VPS mutation/secrets.
- AC3 Real switching e2e: passed with baseline, apply, restart, post-switch DNS/HTTPS/literal-IP and selected-native-out log evidence.
- AC4 Blocker reporting: not needed; no current blocker remains from this run.
- AC5 Commit safety: passed; committed in this branch as `Fix vpnkit apply hostname bootstrap`.
