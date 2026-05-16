# VPS conntrack saturation incident

Incident observed: 2026-05-16 around `23:23:13Z` on `vibe-practicum` while ASUS/OpenVPN full-tunnel clients reported apartment internet loss.

## Symptom

Kernel log:

```text
nf_conntrack: nf_conntrack: table full, dropping packet
```

This can look like the ASUS router OpenVPN tunnel or DNS died, because new forwarded/NAT/TPROXY flows are dropped before user-space services can handle them.

## Evidence from the incident

Read-only checks showed:

- VPS did **not** reboot: boot time stayed `2026-04-10 21:24`.
- Core services stayed running and had no restart loop:
  - `openvpn-server@vibe-asus`
  - `sing-box-vibe-router`
  - `xray`
  - `tailscaled`
- Disk was healthy (`/` around 44% used) and there was no OOM kill in the inspected window.
- `nf_conntrack_max` was only `8192`, too low for this box acting as VPN/router/TPROXY edge.

## Live fix applied

Persistent sysctl file on the VPS:

```text
/etc/sysctl.d/99-vibe-conntrack.conf
```

Contents:

```sysctl
# vibe-practicum VPN/TProxy router: avoid transient packet loss when conntrack fills.
# 2026-05-16 incident: kernel logged "nf_conntrack: table full, dropping packet"
# while ASUS/OpenVPN full-tunnel clients lost internet.
net.netfilter.nf_conntrack_max = 65536
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 120
```

Runtime verification immediately after apply:

```text
nf_conntrack_count=2509
nf_conntrack_max=65536
asus 10.89.0.4 ping: 3/3 OK, ~19 ms
10.89.0.4 TPROXY counters continued growing
no new `nf_conntrack: table full` lines
no new sing-box DNS errors in the immediate post-fix window
```

Backup captured before applying:

```text
/root/vibe-conntrack-before-20260516T232643Z.txt
```

## Rollback

```bash
ssh vibe-practicum 'sudo rm -f /etc/sysctl.d/99-vibe-conntrack.conf && sudo sysctl -w net.netfilter.nf_conntrack_max=8192 net.netfilter.nf_conntrack_tcp_timeout_established=432000'
```

## Diagnostic commands

```bash
ssh vibe-practicum 'cat /proc/sys/net/netfilter/nf_conntrack_count; cat /proc/sys/net/netfilter/nf_conntrack_max'
ssh vibe-practicum 'journalctl -k --since "30 min ago" --no-pager | grep -E "nf_conntrack: table full|oom|killed process"'
ssh vibe-practicum 'systemctl show openvpn-server@vibe-asus sing-box-vibe-router xray tailscaled -p ActiveState -p SubState -p NRestarts -p ExecMainStartTimestamp --no-pager'
ssh vibe-practicum 'sudo iptables -t mangle -vnL PREROUTING --line-numbers | grep 10.89.0.4'
ssh vibe-practicum 'ping -c 3 -W 2 10.89.0.4'
```

## Operational note

If users report “the apartment internet disappeared” while the ASUS profile is full-tunnel through OpenVPN, check conntrack saturation before only testing DNS or upstream proxy health. A full conntrack table drops packets globally and can break tunnel dataplane even when all systemd services are `active`.
