$ tests/sing-box-dns-schema-test.sh
sing-box DNS schema tests passed
$ tests/vpnkit-production-routing-wiring-test.sh
vpnkit production routing wiring tests passed
$ bash -n scripts/*.sh docker/vpnkit/*.sh tests/*.sh
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

$ render both templates with gitignored current selected outbound into temp dir and run sing-box check without deprecated DNS env
checking redirect.json with real selected outbound (redacted)
checking tun.json with real selected outbound (redacted)
Result: passed; temp files removed; no config values printed.
$ docker build -q -t vpnkit-singbox-dns-migration:local -f docker/vpnkit/Dockerfile .
sha256:bd52f4b8dce67dc93a73b4ad84b78d8adf4f6cae00e849c896e92de8afffb39c
docker_build=passed
