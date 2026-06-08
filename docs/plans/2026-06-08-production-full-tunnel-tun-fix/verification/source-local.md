# Source/local verification

Commands run in worktree `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/prod-full-tunnel-tun-fix`:

```text
bash -n scripts/*.sh docker/vpnkit/*.sh tests/*.sh
tests/vpnkit-production-routing-wiring-test.sh
go test ./...
```

Result: all passed.

The first production profile run failed ICMP/DNS because `OVPN_CIDR` in production env did not match the OpenVPN server pool, so packets did not match the source policy rule. Fixed by deriving and setting `OVPN_CIDR` from the rendered OpenVPN `server` directive on both servers without printing its value, then recreating only `vpnkit`.
