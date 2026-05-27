# Root final local verification
Date: 2026-05-27T23:25:55+03:00
Branch: feature/fastest-rotation-mode
HEAD before final-report commit: df8a211

## go clean -testcache

## go test ./...
ok  	github.com/kcnc/vibe-practicum-vpn/cmd/vibe-vpn	1.149s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/config	0.003s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/extranodes	0.003s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/failover	0.002s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/health	0.003s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/ikev2	1.515s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/logging	0.003s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/nettest	0.003s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/picker	0.002s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/service	0.007s
?   	github.com/kcnc/vibe-practicum-vpn/internal/state	[no test files]
ok  	github.com/kcnc/vibe-practicum-vpn/internal/subscription	0.004s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/vless	0.002s
ok  	github.com/kcnc/vibe-practicum-vpn/internal/xray	0.003s

## go vet ./...

## go build ./cmd/vibe-vpn

## bash -n scripts/validate-vibe-vpn-service-assets.sh

## ./scripts/validate-vibe-vpn-service-assets.sh
vibe-vpn service assets passed static validation

## bash -n scripts/install-vibe-vpn-service.sh
