# ASUS OpenVPN site-to-site runbook

This runbook prepares an ASUS router to connect to the `vibe-practicum` VPS with
OpenVPN, then routes ASUS-side traffic through the existing sing-box/xray TProxy
path. It is intentionally dry-run-first: repo scripts print plans or status by
default and do not change live VPS state unless an explicit apply/export gate is
set.

## Safety model

- Install and rollback scripts are dry-run-only unless `OPENVPN_ASUS_APPLY=1` is
  set.
- Profile generation is dry-run-only unless `OPENVPN_ASUS_EXPORT=1` is set.
- `VIBE_PRACTICUM_SUDO_PASSWORD` is required only for apply/export operations
  that need remote root reads or writes.
- Status checks use read-only commands and `sudo -n` when possible.
- Do **not** commit generated `.ovpn` profiles, private keys, certificates,
  `ta.key`, subscription URLs, VLESS links, or tokens.
- Do **not** change the VPS default route for this setup.
- Do **not** flush broad iptables chains or use broad `iptables-restore` filters.
- Do **not** stop or restart `tailscaled`, `xray`, or `sing-box-vibe-router`
  except for read-only status checks.
- All OpenVPN ASUS-owned iptables comments use prefix
  `vibe-vpn-openvpn-asus:`.

## Intended topology

```text
ASUS LAN clients
-> ASUS router OpenVPN client
-> VPS OpenVPN server UDP/1194 on tun-asus
-> mangle PREROUTING VIBE_ROUTER_OPENVPN_ASUS
-> sing-box TProxy :2082
-> xray/VLESS upstream
-> internet
```

The setup captures only packets arriving on `tun-asus` from the OpenVPN pool or
ASUS LAN source range. Existing `VIBE_ROUTER_PIXEL`, Tailscale, xray, and
sing-box rules are preserved.

## Defaults

| Setting | Default |
| --- | --- |
| SSH host | `vibe-practicum` |
| OpenVPN UDP port | `1194` |
| OpenVPN device | `tun-asus` |
| VPN pool | `10.89.0.0/24` |
| VPN gateway | `10.89.0.1` |
| ASUS VPN IP | `10.89.0.2` |
| Direct client pool | `10.89.0.20`-`10.89.0.254` |
| Default direct client CN | `direct-client-1` |
| ASUS LAN | `192.168.50.0/24` |
| TProxy port | `2082` |
| fwmark | `0x1` |
| policy table | `100` |
| iptables comment prefix | `vibe-vpn-openvpn-asus:` |

Override these with env vars such as `OPENVPN_PORT`, `OPENVPN_DEV`,
`OPENVPN_ASUS_LAN_CIDR`, `OPENVPN_CLIENT_POOL_START`,
`OPENVPN_CLIENT_POOL_END`, `OPENVPN_DIRECT_CLIENT_CN`, `TPROXY_PORT`, `MARK`, or
`TABLE` before running the scripts.

## Repo-side files

```text
docs/ASUS_OPENVPN_SITE_TO_SITE.md
scripts/openvpn-asus-install.sh
scripts/openvpn-asus-status.sh
scripts/openvpn-asus-rollback.sh
scripts/openvpn-asus-profile.sh
```

Remote files created by apply mode:

```text
/etc/vibe-vpn/openvpn-asus/                 # root-only state and PKI exports
/etc/openvpn/server/vibe-asus.conf
/etc/openvpn/ccd-vibe-asus/asus
/usr/local/sbin/vibe-openvpn-asus-rules
/etc/systemd/system/vibe-openvpn-asus-routing.service
```

## Preflight snapshot and status

From a clean checkout on the operator workstation:

```bash
cd ~/code/tools/vibe-practicum-vpn

# Existing general snapshot helper, if desired. This is intended as a read-only
# pre-change capture; review its output before sharing.
./scripts/vps-snapshot.sh

# OpenVPN ASUS-specific read-only audit. It does not print certs, keys, or .ovpn
# contents. If passwordless sudo is unavailable, sudo-only sections are skipped.
./scripts/openvpn-asus-status.sh
```

Expected preflight checks:

- host/date are the expected VPS;
- `tailscaled`, `xray`, and `sing-box-vibe-router` are healthy;
- UDP `:1194` is either absent before install or owned by the intended OpenVPN
  service after install;
- `tun-asus`, `10.89.0.0/24`, and `192.168.50.0/24` routes match expectations;
- table `100` and fwmark `0x1` are consistent with the existing TProxy setup;
- any `vibe-vpn-openvpn-asus:` iptables lines are understood.

## Install dry-run

The default install invocation prints the exact plan only. It does not SSH or ask
for a sudo password.

```bash
./scripts/openvpn-asus-install.sh
```

Review that the plan:

- creates/reuses `VIBE_ROUTER_OPENVPN_ASUS` only;
- attaches PREROUTING only for `-i tun-asus -s 10.89.0.0/24` and
  `-i tun-asus -s 192.168.50.0/24`;
- uses comments prefixed `vibe-vpn-openvpn-asus:`;
- does not mention default-route changes, broad iptables flushes, Tailscale
  restarts, xray changes, or sing-box restarts.

## Apply install

Only after reviewing the dry-run plan:

```bash
export VIBE_PRACTICUM_SUDO_PASSWORD='fill-this-in'
OPENVPN_ASUS_APPLY=1 ./scripts/openvpn-asus-install.sh
unset VIBE_PRACTICUM_SUDO_PASSWORD
```

Custom example:

```bash
export VIBE_PRACTICUM_SUDO_PASSWORD='fill-this-in'
SSH_HOST=vibe-practicum \
OPENVPN_PORT=1194 \
OPENVPN_DEV=tun-asus \
OPENVPN_ASUS_LAN_CIDR=192.168.50.0/24 \
OPENVPN_ASUS_APPLY=1 \
  ./scripts/openvpn-asus-install.sh
unset VIBE_PRACTICUM_SUDO_PASSWORD
```

Apply mode installs `openvpn`/`easy-rsa` if missing, creates root-only PKI state,
renders the server config and CCD for CN `asus`, generates the default direct
client CN `direct-client-1`, installs a direct-client CCD route to the ASUS LAN,
allows UDP `1194` in UFW when UFW is active, installs the routing helper and
systemd unit, and starts `openvpn-server@vibe-asus` plus
`vibe-openvpn-asus-routing.service`. The ASUS LAN route is not pushed back to
the ASUS client. The OpenVPN dynamic pool starts at `10.89.0.20`, leaving
`10.89.0.2` reserved for the ASUS router.

## Profile export for ASUS import

Profile export handles private key material. The default is a dry-run that prints
prerequisites and the target path only:

```bash
./scripts/openvpn-asus-profile.sh
```

Export only when the VPS materials have been generated and you are ready to store
a local secret profile:

```bash
mkdir -p /tmp/vibe-openvpn-asus-profile
export VIBE_PRACTICUM_SUDO_PASSWORD='fill-this-in'
OPENVPN_ASUS_EXPORT=1 \
PUBLIC_ENDPOINT='your.public.vps.name.or.ip' \
OUT_DIR=/tmp/vibe-openvpn-asus-profile \
  ./scripts/openvpn-asus-profile.sh
unset VIBE_PRACTICUM_SUDO_PASSWORD
```

The generated file is `OUT_DIR/asus-vibe-practicum.ovpn` with mode `0600` for
the default `OPENVPN_CLIENT_CN=asus`. Stdout says `secret_material: not printed`
and never echoes the embedded key or certificates.

To export the default direct-client profile instead:

```bash
mkdir -p /tmp/vibe-openvpn-direct-client
export VIBE_PRACTICUM_SUDO_PASSWORD='fill-this-in'
OPENVPN_ASUS_EXPORT=1 \
OPENVPN_CLIENT_CN=direct-client-1 \
PUBLIC_ENDPOINT='your.public.vps.name.or.ip' \
OUT_DIR=/tmp/vibe-openvpn-direct-client \
  ./scripts/openvpn-asus-profile.sh
unset VIBE_PRACTICUM_SUDO_PASSWORD
```

That writes `OUT_DIR/direct-client-1-vibe-practicum.ovpn` unless `PROFILE_NAME`
is overridden.

By default the profile does **not** include `redirect-gateway def1`. If you want
ASUS firmware to request full-tunnel behavior from the client profile, export
with:

```bash
OPENVPN_ASUS_REDIRECT_GATEWAY=1 OPENVPN_ASUS_EXPORT=1 \
PUBLIC_ENDPOINT='your.public.vps.name.or.ip' \
OUT_DIR=/tmp/vibe-openvpn-asus-profile \
VIBE_PRACTICUM_SUDO_PASSWORD='fill-this-in' \
  ./scripts/openvpn-asus-profile.sh
```

ASUS firmware varies. `tls-auth` is used instead of `tls-crypt` and exported
profiles use `cipher AES-256-CBC` for broader ASUSWRT import compatibility. The
server still permits modern AES-GCM negotiation for clients that support it. If
import fails, check whether the firmware supports embedded `<ca>`, `<cert>`,
`<key>`, and `<tls-auth>` blocks.

## ASUS router import notes

1. Log in to the ASUS router admin UI.
2. Open the VPN client/OpenVPN client import page.
3. Import `asus-vibe-practicum.ovpn`.
4. Enable the profile.
5. Confirm whether the firmware routes all LAN clients or only selected clients
   through the VPN. Configure ASUS-side policy rules as desired.
6. Keep the profile out of git and delete temporary copies when no longer needed.

Some ASUS firmware NATs LAN traffic behind the OpenVPN client IP (`10.89.0.2`),
while other modes preserve ASUS LAN sources (`192.168.50.0/24`). The VPS routing
helper captures both source ranges on `tun-asus`; verify counters/status after
connecting the router.

## Post-install status

```bash
./scripts/openvpn-asus-status.sh
```

Look for:

- `openvpn-server@vibe-asus` active;
- UDP listener on `:1194`;
- `tun-asus` present after the ASUS client connects;
- route for `192.168.50.0/24` via OpenVPN when the client is connected;
- `ip rule` and table `100` still present;
- `iptables-save` lines with `vibe-vpn-openvpn-asus:` only in the expected
  `VIBE_ROUTER_OPENVPN_ASUS` path.

## Client acceptance checks

From a direct OpenVPN client using `direct-client-1-vibe-practicum.ovpn`:

```bash
ping -c 3 10.89.0.1
ping -c 3 10.89.0.2
ping -c 3 192.168.50.1
```

From a LAN client behind the ASUS router:

```bash
ping -c 3 10.89.0.1
# Replace with the actual direct client's VPN IP after it connects.
ping -c 3 10.89.0.20
curl -4 https://ifconfig.me
```

The curl result should be the intended proxied egress, not the local ISP address,
if ASUS routes that LAN client through the VPN profile. Also check:

- DNS resolution works for normal sites;
- key apps/sites work over TCP and UDP where relevant;
- ASUS router VPN client status stays connected;
- VPS health remains good:

```bash
./scripts/openvpn-asus-status.sh
ssh vibe-practicum 'systemctl is-active tailscaled xray sing-box-vibe-router openvpn-server@vibe-asus'
```

Do not restart Tailscale/xray/sing-box as part of acceptance unless you are
performing a separately planned maintenance action.

## Rollback dry-run

The default rollback invocation prints the exact rollback plan only:

```bash
./scripts/openvpn-asus-rollback.sh
```

Review that it removes only exact PREROUTING entries and
`VIBE_ROUTER_OPENVPN_ASUS` rules with comments prefixed
`vibe-vpn-openvpn-asus:`, preserves fwmark/table `100`, and moves files to a
backup directory instead of deleting or printing secrets.

## Apply rollback

```bash
export VIBE_PRACTICUM_SUDO_PASSWORD='fill-this-in'
OPENVPN_ASUS_APPLY=1 ./scripts/openvpn-asus-rollback.sh
unset VIBE_PRACTICUM_SUDO_PASSWORD
```

Rollback stops/disables only:

- `vibe-openvpn-asus-routing.service`
- `openvpn-server@vibe-asus.service`

It moves ASUS-owned config/state into:

```text
/var/backups/vibe-vpn/openvpn-asus/<timestamp>/
```

It does not remove shared TProxy policy routing (`fwmark 0x1`, table `100`) by
default.

## Post-rollback verification

```bash
./scripts/openvpn-asus-status.sh
ssh vibe-practicum 'systemctl is-active tailscaled xray sing-box-vibe-router'
```

Confirm:

- `tailscaled`, `xray`, and `sing-box-vibe-router` are still active;
- `openvpn-server@vibe-asus` is inactive or absent;
- no `vibe-vpn-openvpn-asus:` lines remain in `iptables-save -t mangle` unless
  intentionally preserved for investigation;
- no unexpected default route changes occurred;
- backup directory exists under `/var/backups/vibe-vpn/openvpn-asus/`.

## Local validation for repo changes

Before opening a PR or issue update, run only local/non-live validation:

```bash
bash -n scripts/openvpn-asus-install.sh scripts/openvpn-asus-status.sh \
  scripts/openvpn-asus-rollback.sh scripts/openvpn-asus-profile.sh

command -v shellcheck >/dev/null && shellcheck scripts/openvpn-asus-*.sh || true

grep -R "vibe-vpn-openvpn-asus" scripts docs/ASUS_OPENVPN_SITE_TO_SITE.md

./scripts/openvpn-asus-install.sh
./scripts/openvpn-asus-rollback.sh
./scripts/openvpn-asus-profile.sh
```

Do not run local validation with `OPENVPN_ASUS_APPLY=1` or
`OPENVPN_ASUS_EXPORT=1` unless you are deliberately performing the live operation
with the filled-in secrets and endpoint.
