# Slice B local verification and Slice C gated live runbook

## Local repo checks (Slice B)

Commands run from worktree `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/issue-9-openvpn-singbox-tproxy`:

```bash
jq . configs/sing-box/tproxy-canary.json >/dev/null
bash -n scripts/openvpn-asus-tproxy-canary-rules.sh
grep -R "sing-box/xray\|xray/VLESS\|dynamic.*xray\|sing-box -> xray" \
  docs/OPENVPN_ASUS_TPROXY_CANARY.md docs/ASUS_OPENVPN_SITE_TO_SITE.md \
  scripts/openvpn-asus-tproxy-canary-rules.sh configs/sing-box/tproxy-canary.json || true
```

Result: passed. Remaining grep hits in touched issue #9 docs are explicit legacy/not-success-path notes, not active dynamic-pool design claims.

Broader Go checks were also run after edits:

```bash
go test ./...
go vet ./...
go build -o /tmp/vibe-vpn ./cmd/vibe-vpn
```

Result: passed.

## Gated live-change runbook for Slice C

Do not run these until an owner explicitly opens live Slice C. Prefer waiting for an active `ignat` session if end-to-end acceptance is required.

### 0. Preconditions / safety gate

- Confirm operator approval for live mutations.
- Confirm no secrets/full VLESS links/UUIDs will be copied into reports.
- Confirm `ignat` or another dynamic client is available, ideally observed as `10.89.0.23` or a current `10.89.0.20-10.89.0.254` lease.
- Keep broad `10.89.0.0/24 -> eth0 MASQUERADE` only as emergency fallback; do not count it as final success.

### 1. Fresh pre-change snapshot (read-only)

```bash
ssh vibe-practicum 'date; hostname'
ssh vibe-practicum 'sudo sed -n "1,80p" /var/log/openvpn/vibe-asus-status.log || true'
ssh vibe-practicum 'sudo cat /var/lib/openvpn/vibe-asus-ipp.txt | sed -E "s/(.*,)[0-9.]+/\1<ip>/" || true'
ssh vibe-practicum 'sudo iptables -t mangle -S; sudo iptables -t filter -S INPUT; sudo iptables -t nat -S'
ssh vibe-practicum 'ip rule show; ip route show table 100'
ssh vibe-practicum 'systemctl is-active sing-box-vibe-router sing-box openvpn-server@vibe-asus xray || true'
ssh vibe-practicum 'sudo ss -lntup | grep -E ":(2082|2080|10808)" || true'
ssh vibe-practicum 'sudo jq "{log:.log,dns:.dns,route:{final:.route.final,rules:.route.rules},outbounds:.outbounds|map({tag,type,server,server_port,detour})}" /etc/sing-box-vibe/tproxy-canary.json'
```

### 2. Backup before mutation

```bash
ssh vibe-practicum 'sudo install -d -m 700 /var/backups/vibe-vpn/issue-9 && sudo cp -a /etc/sing-box-vibe/tproxy-canary.json /var/backups/vibe-vpn/issue-9/tproxy-canary.$(date +%Y%m%d-%H%M%S).json'
```

Record backup path in the live report.

### 3. Proposed reversible DNS/logging adjustment

Edit only `/etc/sing-box-vibe/tproxy-canary.json`, preserving the live VLESS outbound secret values. Target state:

- `route.final` remains native `selected-native-out`.
- A DNS `hijack-dns` route rule exists for `canary-tproxy-in`/port 53.
- Sing-box DNS servers used by final client DNS are detoured through `selected-native-out` or another explicit sing-box policy, not untracked direct/NAT DNS.
- Any direct resolver (`yandex-basic` or equivalent) is either removed from final DNS flow or clearly retained only for diagnostic/direct-domain exceptions.
- Temporary `log.level` may be raised only if needed and must be rolled back.

Validate before reload/restart:

```bash
ssh vibe-practicum 'sudo sing-box check -c /etc/sing-box-vibe/tproxy-canary.json'
```

Then perform the minimal approved service action (reload if supported, otherwise restart) only inside Slice C, with rollback ready.

### 4. Rollback path

If validation fails or client connectivity worsens:

```bash
ssh vibe-practicum 'sudo cp -a /var/backups/vibe-vpn/issue-9/<recorded-backup>.json /etc/sing-box-vibe/tproxy-canary.json && sudo sing-box check -c /etc/sing-box-vibe/tproxy-canary.json'
# then reload/restart the same sing-box service action used for the change
```

Also revert temporary log-level changes.

## AC1-AC8 proof map for live Slice C

- AC1 dynamic client lease:
  - `sudo sed -n "1,120p" /var/log/openvpn/vibe-asus-status.log`
  - `sudo journalctl -u openvpn-server@vibe-asus --since "30 min ago" -g "ignat|10.89.0.|PUSH_REPLY|MULTI: primary virtual IP"`
  - Evidence: connected CN and current pool IP.

- AC2 dynamic-pool TPROXY/local delivery:
  - `sudo iptables -t mangle -L PREROUTING -v -n -x --line-numbers | grep VIBE_OVPN_ASUS_TP`
  - `sudo iptables -t mangle -L VIBE_OVPN_ASUS_TP -v -n -x --line-numbers`
  - `sudo iptables -t filter -L INPUT -v -n -x --line-numbers | grep tproxy-input-accept`
  - `ip rule show; ip route show table 100; sudo ss -lntup | grep ':2082'`
  - Evidence: counters increase for `10.89.0.20-10.89.0.254`, INPUT accept is not limited to `10.89.0.3`.

- AC3 sing-box DNS handling:
  - `sudo timeout 20 tcpdump -ni tun-asus "host <client-ip> and port 53" -vv -c 20`
  - `sudo journalctl -u sing-box-vibe-router --since "5 min ago" --no-pager | grep -Ei "dns|hijack|<client-ip>|selected-native"`
  - Evidence: DNS query/reply visible on `tun-asus`; sing-box config/logs show `hijack-dns` and sing-box DNS detours.

- AC4 UDP-over-VLESS / DNS transport behavior:
  - Capture DNS plus outbound sing-box traffic during lookup; if raw UDP over the selected native VLESS transport is unsafe, switch DNS to proven TCP/DoH/DoT under sing-box rules and document the generic UDP limitation.
  - Evidence: DNS succeeds without direct/NAT DNS bypass.

- AC5 TCP/HTTPS after DNS:
  - From client, browse/curl known HTTPS site after DNS.
  - VPS capture: `sudo timeout 20 tcpdump -ni tun-asus "host <client-ip> and (tcp port 443 or tcp port 80)" -vv -c 40`.
  - Evidence: SYN/traffic from client and response packets back out `tun-asus`.

- AC6 not broad NAT as final success:
  - Compare mangle/INPUT/sing-box counters/logs with nat POSTROUTING counters.
  - Temporarily disabling broad NAT may be a later separately approved gate only after sing-box proof exists.
  - Evidence: accepted success is TPROXY/sing-box/native VLESS path, not only `POSTROUTING MASQUERADE` growth.

- AC7 intended service state:
  - `systemctl is-active sing-box-vibe-router sing-box openvpn-server@vibe-asus xray || true`
  - `systemctl list-units "sing-box*" --all`
  - `ps -ef | grep -E "[s]ing-box|[x]ray"`
  - Evidence: `sing-box-vibe-router` active, package `sing-box.service` masked/inactive; xray, if still active, recorded as legacy side service not issue #9 route.

- AC8 reproducibility/rollback:
  - Link repo docs and this runbook; record exact applied diff, backup path, validation result, and rollback command tested/readied.

## Fresh final local verification (after all Slice B edits)

```bash
go test ./... && go vet ./... && go build -o /tmp/vibe-vpn ./cmd/vibe-vpn && \
  jq . configs/sing-box/tproxy-canary.json >/dev/null && \
  bash -n scripts/openvpn-asus-tproxy-canary-rules.sh
```

Result: passed.

Short output excerpt:

```text
ok  github.com/kcnc/vibe-practicum-vpn/cmd/vibe-vpn 1.105s
ok  github.com/kcnc/vibe-practicum-vpn/internal/ikev2 1.538s
ok  github.com/kcnc/vibe-practicum-vpn/internal/xray 0.004s
```
