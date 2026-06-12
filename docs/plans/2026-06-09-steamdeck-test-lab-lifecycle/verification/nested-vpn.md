## Nested VPN verification
Wed Jun 10 09:58:36 UTC 2026

### Static shell
PASS

### Sing-box proof
PASS sing-box smart routing proof: adblock/dev-direct/RU/default decisions and remote/local-fixture template invariants

### Go test
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

### Go vet

### Go build

### Python compile
PASS

### Lab setup generation smoke
WARNING: missing vibe-vpn subscription input; see /tmp/tmp.drO7xjIsMV/rendered/vibe-vpn/README.missing-subscription
test_lab_base=<tmp>
rendered_config_dir=<tmp>
client_profile=<tmp>
nested_client_profile=<tmp>
nested_server_config=<tmp>
routing_mode=tun
endpoint_set=yes
generated=ok (contents not printed)
PASS

### Sensitive tracked artifact guard
