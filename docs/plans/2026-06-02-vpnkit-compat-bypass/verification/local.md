# Local verification: vpnkit compatibility bypass

## Commands run

- `bash -n docker/vpnkit/setup-routing.sh scripts/vpnkit-routing-compat-bypass-test.sh` — passed.
- `bash scripts/vpnkit-routing-compat-bypass-test.sh` — passed; verifies dry-run render of scoped UDP/TCP endpoint RETURN rules, scoped endpoint MASQUERADE/FORWARD rules, optional endpoint ICMP, invalid proto rejection, conflicting proto rejection, and absence of broad `POSTROUTING -s 10.89.0.0/24 -j MASQUERADE` in rendered rules.
- `shellcheck docker/vpnkit/setup-routing.sh scripts/vpnkit-routing-compat-bypass-test.sh` — not run; `shellcheck` is not installed in this environment.
- `docker compose config >/tmp/vpnkit-compose-config.out` — passed. Relevant environment output included defaults:
  - `VPNKIT_COMPAT_BYPASS_ALLOW_ICMP: "false"`
  - `VPNKIT_COMPAT_BYPASS_ENABLED: "false"`
  - `VPNKIT_COMPAT_BYPASS_ENDPOINTS: vpn.proofix.tv:1194`
  - `VPNKIT_ROUTING_MODE: redirect`
- `grep -n -E 'POSTROUTING .*-s ([$]OVPN_CIDR|10[.]89[.]0[.]0/24).* -j MASQUERADE|POSTROUTING .* -j MASQUERADE.*-s ([$]OVPN_CIDR|10[.]89[.]0[.]0/24)' docker/vpnkit/setup-routing.sh docker-compose.yml` — passed/no matches; no broad OpenVPN-client POSTROUTING MASQUERADE in routing/compose source.
- `VPNKIT_ROUTING_DRY_RUN=true VPNKIT_ROUTING_MODE=redirect VPNKIT_COMPAT_BYPASS_ENABLED=true bash docker/vpnkit/setup-routing.sh | grep -E -- '-A OVPN_REDIRECT_TO_SINGBOX -d .* -p udp --dport 1194 -j RETURN|-A OVPN_REDIRECT_TO_SINGBOX -p tcp -j REDIRECT|-A OVPN_REDIRECT_TO_SINGBOX -p udp --dport 53 -j REDIRECT'` — passed; default `vpn.proofix.tv:1194` resolved locally during dry-run and rendered an implicit-UDP endpoint RETURN before the TCP and UDP/53 sing-box REDIRECT rules.

## Notes

- No live VPS mutation or runtime OpenVPN connection test was run.
- The resolved public IP for `vpn.proofix.tv` may vary by DNS at runtime; routing installs rules for all IPv4 addresses returned by `getent ahostsv4` at container startup.
