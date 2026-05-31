# Verification: live discovery for Issue #9

## Commands run
- `ssh vibe-practicum 'hostname; date; uname -a'`
  - Host: `awsbbbuslw`
  - Time: `Sun May 31 03:08:36 AM UTC 2026`
  - Kernel: `Linux 6.8.0-117-generic x86_64`

- `ssh vibe-practicum 'systemctl list-units "sing-box*" --all --no-pager; systemctl is-active sing-box-vibe-router sing-box openvpn-server@vibe-asus || true; systemctl status --no-pager sing-box-vibe-router sing-box openvpn-server@vibe-asus | sed -n "1,220p"'`
  - `sing-box-vibe-router.service` active/running
  - `sing-box.service` masked/inactive
  - `openvpn-server@vibe-asus.service` active/running

- `ssh vibe-practicum 'sudo ps -ef | grep "[s]ing-box"; sudo ss -lntup | grep -E ":(2082|2080|10808)\b|sing-box|xray" || true'`
  - one `sing-box` PID
  - sing-box listeners on `2082` and `2080`
  - xray still listening on `10808`

- `ssh vibe-practicum 'sudo sed -n "1,220p" /etc/openvpn/server/vibe-asus.conf'`
  - `ifconfig-pool 10.89.0.20 10.89.0.254 255.255.255.0`
  - pushes DNS `8.8.8.8` and `8.8.4.4`

- `ssh vibe-practicum 'sudo sed -n "1,220p" /var/log/openvpn/vibe-asus-status.log'`
  - header only; no current client rows at capture time

- `ssh vibe-practicum 'sudo journalctl -u openvpn-server@vibe-asus --since "6 hours ago" --no-pager -g "ignat|10.89.0.23|PUSH_REPLY|MULTI: primary virtual IP"'`
  - `ignat` assigned `10.89.0.23`
  - last visible disconnect at `May 31 00:14:16`

- `ssh vibe-practicum 'sudo iptables -t mangle -S; sudo iptables -t filter -S INPUT; sudo iptables -t nat -S; sudo ip rule show; sudo ip route show table 100'`
  - dynamic-pool PREROUTING TPROXY rule present
  - INPUT ACCEPT for marked dynamic pool present
  - `fwmark 0x1 lookup 100`
  - table 100 local default route
  - broad `10.89.0.0/24 -> eth0 MASQUERADE` fallback present

- `ssh vibe-practicum 'sudo jq ... /etc/sing-box-vibe/tproxy-canary.json'`
  - outbound `selected-native-out` is `vless` to `185.192.22.159:8444` with UUID redacted
  - `route.final` is `selected-native-out`
  - DNS has `hijack-dns` and detoured resolvers, but `yandex-basic` remains direct

- `ssh vibe-practicum 'sudo timeout 8 tcpdump -ni tun-asus "src net 10.89.0.0/24 and (port 53 or tcp port 80 or tcp port 443)" -c 20'`
  - `0 packets captured`

## Evidence summary by AC
- AC1: `ignat` mapped to `10.89.0.23` in ipp/logs.
- AC2: TPROXY + INPUT + policy routing exist and sing-box listens on `2082`.
- AC3: `hijack-dns` exists, but direct DNS elements remain; no live DNS packets observed.
- AC4: sing-box outbound is native VLESS; live UDP/DNS packet behavior not proven.
- AC5: no live TCP/HTTPS packets observed.
- AC6: NAT fallback exists; not a success criterion.
- AC7: sing-box service cleanup is mostly correct; xray still active.
- AC8: docs/scripts exist; live config diverges from repo copy.

## Current blocker
- No active `ignat` traffic during observation, so packet-level end-to-end proof could not be completed in read-only mode.
