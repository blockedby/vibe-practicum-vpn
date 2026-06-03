# Root verification evidence

Date: 2026-06-03

## Fresh local checks

```text
vpnkit sing-box templates ok
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
```

## Safety/status checks

```text
## vpnkit-tproxy-udp-nested...origin/vpnkit-tproxy-udp-nested
 M docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/acceptance-auditor.md
 M docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/acceptance-plan.md
?? docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/root.md
!! config/private-endpoints.local.env
!! secrets/
.pi/gsd/templates/config.json
config/openvpn/test-client.ovpn.template
```

Result: local code checks passed. Gitignored private endpoint/secrets remain untracked/ignored; no generated profile/log/private endpoint files are tracked by the grep check above except tracked templates/docs if any appear.
