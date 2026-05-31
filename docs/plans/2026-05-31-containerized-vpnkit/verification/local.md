# Local verification

Commands run on 2026-06-01:

```bash
bash -n docker/vpnkit/entrypoint.sh docker/vpnkit/setup-routing.sh docker/ovpn-client-test/entrypoint.sh docker/ovpn-client-test/run-tests.sh scripts/vpnkit-copy-vps-secrets.sh scripts/vpnkit-render-local-configs.sh scripts/vpnkit-collect-evidence.sh
# passed

docker compose config >/tmp/vpnkit-compose.txt
# passed

grep checks for forbidden broad NAT, xray in lab runtime, UUID/private-key/vless URL patterns
# passed
```

Live privileged Docker/VLESS validation was later run with real VPS material copied into gitignored `secrets/vps/`. See `verification/live-docker-2026-05-31.md`.

Result: partial success. OpenVPN-in-container works and the separate client container gets `10.89.0.2`; client packets enter `vpnkit` `tun0` and TPROXY counters increase. The remaining failure is the TPROXY handoff to a userland transparent socket: sing-box does not log `inbound/tproxy` accepts for `10.89.0.2`, and client DNS/HTTPS time out.
