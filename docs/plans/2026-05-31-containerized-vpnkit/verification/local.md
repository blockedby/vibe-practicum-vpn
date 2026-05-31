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

Live privileged Docker/VLESS validation was not run because real secrets are intentionally absent and operator action is required.
