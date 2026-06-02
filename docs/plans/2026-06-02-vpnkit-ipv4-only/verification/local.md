# Local verification: IPv4-only / IPv6-block policy

Date: 2026-06-02
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-compat-bypass`
Branch: `vpnkit-compat-bypass`

No live deploy, SSH, remote mutation, secrets, generated profiles, or logs were used.

## RED evidence

- `scripts/vpnkit-routing-compat-bypass-test.sh` failed after adding IPv6 block expectations and before production changes:
  - Failure excerpt: `FAIL: expected rendered rules to contain: ip6tables -t filter -A INPUT -i tun0 -j OVPN_IPV6_BLOCK`

## Checks run

- `bash -n docker/vpnkit/entrypoint.sh docker/vpnkit/setup-routing.sh scripts/vpnkit-render-local-configs.sh scripts/vpnkit-routing-compat-bypass-test.sh` — passed.
- `scripts/vpnkit-routing-compat-bypass-test.sh` — passed; covers existing compat bypass assertions, default IPv6 block dry-run rules, and invalid `VPNKIT_IPV6_POLICY=bogus` failure.
- `docker compose config >/tmp/vpnkit-compose-config.out && grep -n "VPNKIT_IPV6_POLICY" /tmp/vpnkit-compose-config.out` — passed; output included `VPNKIT_IPV6_POLICY: block`.
- `grep -n '"strategy": "ipv4_only"' config/sing-box/config.json.template` — passed; output included line 9.
- `sing-box check` on a temp config rendered from `config/sing-box/config.json.template` with a safe direct `selected-native-out` replacement:
  - Initial run without env flags failed on existing sing-box 1.12+ legacy-DNS compatibility gate (`ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true` required).
  - Rerun with `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true` — passed with deprecation warnings only.

## Deploy-time verification commands for operator

```bash
bash -n docker/vpnkit/entrypoint.sh docker/vpnkit/setup-routing.sh scripts/vpnkit-render-local-configs.sh scripts/vpnkit-routing-compat-bypass-test.sh
scripts/vpnkit-routing-compat-bypass-test.sh
docker compose config | grep -E 'VPNKIT_IPV6_POLICY|VPNKIT_ROUTING_MODE'
docker compose exec vpnkit ip6tables -t filter -L OVPN_IPV6_BLOCK -v -n -x
docker compose exec vpnkit grep -n '"strategy": "ipv4_only"' /var/lib/vpnkit/sing-box/config.json
```

If an existing `vpnkit-sing-box-state` volume has an old persisted sing-box config, rerender/recreate intentionally and verify the live `/var/lib/vpnkit/sing-box/config.json` contains `"strategy": "ipv4_only"`.
