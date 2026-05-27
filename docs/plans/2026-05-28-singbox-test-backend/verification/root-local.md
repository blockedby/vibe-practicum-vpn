# Root verification: Sing-box test backend by default

Date: 2026-05-28T01:04:28+03:00
Worktree: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/pi-singbox-test-backend
Branch: pi/singbox-test-backend

## Commands

```text
$ go test ./...
ok  	github.com/kcnc/vibe-practicum-vpn/cmd/vibe-vpn	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/config	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/extranodes	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/failover	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/health	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/ikev2	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/logging	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/nettest	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/picker	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/service	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/singbox	(cached)
?   	github.com/kcnc/vibe-practicum-vpn/internal/state	[no test files]
ok  	github.com/kcnc/vibe-practicum-vpn/internal/subscription	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/vless	(cached)
ok  	github.com/kcnc/vibe-practicum-vpn/internal/xray	(cached)
go test status: 0
$ go vet ./...
go vet status: 0
$ go build -o /tmp/vibe-vpn ./cmd/vibe-vpn
go build status: 0
$ ./scripts/validate-vibe-vpn-service-assets.sh
vibe-vpn service assets passed static validation
validation script status: 0
```

Result: PASS for all root-level verification commands.

## Additional freshness check
```text
$ go test -count=1 ./...
ok  	github.com/kcnc/vibe-practicum-vpn/cmd/vibe-vpn	1.574s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/config	0.003s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/extranodes	0.002s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/failover	0.003s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/health	0.002s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/ikev2	1.842s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/logging	0.002s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/nettest	0.002s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/picker	0.002s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/service	0.010s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/singbox	0.002s
?   	github.com/kcnc/vibe-practicum-vpn/internal/state	[no test files]
ok  	github.com/kcnc/vibe-practicum-vpn/internal/subscription	0.003s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/vless	0.002s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/xray	0.003s
go test -count=1 status: 0
```
