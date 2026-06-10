# Direct-fixture DNS detour verification
date=2026-06-10T08:03:19Z

## Static checks
PASS bash -n targeted shell scripts
PASS sing-box smart routing proof: adblock/dev-direct/RU/default decisions and remote/local-fixture template invariants

## Render assertions
PASS direct-fixture render omits DNS detour and keeps selected-native-out final/tag
/tmp/vpnkit-direct-fixture-singbox-check.json
PASS sing-box check direct-fixture rendered config (with disposable local rule-set path rewrite)
PASS proxy/default render keeps DNS detour via selected-native-out and remote RU rule sets

## Go checks
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
PASS go test/vet/build

## Sensitive tracked artifact check
 M docs/plans/2026-06-09-steamdeck-test-lab-lifecycle/plan.md
 M scripts/vpnkit-render-local-configs.sh
PASS no tracked sensitive/generated artifact path matches
