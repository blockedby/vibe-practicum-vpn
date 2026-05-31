# Root local verification

Claim verified: repo-side Slice B changes are locally valid and the branch is ready for live Slice C planning/PR review; root issue #9 is not fully fixed because live end-to-end dynamic-client evidence is still blocked by no active client session.

Commands run from `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-9-openvpn-singbox-tproxy`:

```bash
go test ./...
go vet ./...
go build -o /tmp/vibe-vpn ./cmd/vibe-vpn
jq . configs/sing-box/tproxy-canary.json >/dev/null
bash -n scripts/openvpn-asus-tproxy-canary-rules.sh
git status --short --branch
```

Result: passed.

Short output excerpt:

```text
ok  github.com/kcnc/vibe-practicum-vpn/cmd/vibe-vpn (cached)
ok  github.com/kcnc/vibe-practicum-vpn/internal/singbox (cached)
ok  github.com/kcnc/vibe-practicum-vpn/internal/vless (cached)
ok  github.com/kcnc/vibe-practicum-vpn/internal/xray (cached)
## issue-9-openvpn-singbox-tproxy...origin/main [ahead 3]
```

Acceptance status after root verification:

- AC1: partial — `ignat` -> `10.89.0.23` discovered, but no current session.
- AC2: partial/done for wiring — live rules found and repo docs updated; no current packet counter proof.
- AC3: partial — DNS final policy documented under sing-box rules; live DNS query/reply not proven.
- AC4: partial — native VLESS config shape found and runbook created; UDP/DNS transport not proven with active traffic.
- AC5: not proven — no active TCP/HTTPS client traffic.
- AC6: partial — broad NAT classified as fallback, but final path not proven live.
- AC7: mostly passed — `sing-box-vibe-router` active, package `sing-box.service` masked; xray remains a legacy side service.
- AC8: passed for repo-side documentation/runbook; live final state still pending Slice C.
