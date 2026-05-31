# Verification: containerized vpnkit implementation run (2026-06-01)

## Summary

Result: **passed with REDIRECT architecture**.

The requested TPROXY path was tested first and rejected with falsifiable local evidence: packets matched TPROXY rules, but neither sing-box nor a minimal `IP_TRANSPARENT` listener accepted the redirected TCP connection. The working final architecture uses scoped iptables `REDIRECT` rules into sing-box:

- TCP from `10.89.0.0/24` on `tun0` -> sing-box `redirect` inbound `vpnkit-redirect-in` on `:2082`.
- UDP/53 from `10.89.0.0/24` on `tun0` -> sing-box `direct` inbound `vpnkit-dns-in` on `:5353`, then route action `hijack-dns`.
- DNS server `remote-dns` uses `tls://1.1.1.1` detoured through `selected-native-out`.
- Final route is `selected-native-out`.
- No broad OpenVPN-pool MASQUERADE rule is used.

## TPROXY diagnostic evidence

### Scoped INPUT accept added/tested

`docker/vpnkit/setup-routing.sh` now supports `VPNKIT_ROUTING_MODE=tproxy` and installs a scoped local-delivery accept rule:

```bash
iptables -I INPUT 1 -i tun0 -s "$OVPN_CIDR" -m mark --mark "$MARK" \
  -m comment --comment "vpnkit:tproxy-input-accept" -j ACCEPT
```

Observed TPROXY-mode run after client traffic:

```text
Chain PREROUTING
1 19 1160 OVPN_TO_SINGBOX all -- tun0 * 10.89.0.0/24 0.0.0.0/0

Chain OVPN_TO_SINGBOX
1 18 1080 TPROXY tcp -- * * 0.0.0.0/0 0.0.0.0/0 TPROXY redirect 0.0.0.0:2082 mark 0x1/0x1
2  1   80 TPROXY udp -- * * 0.0.0.0/0 0.0.0.0/0 TPROXY redirect 0.0.0.0:2082 mark 0x1/0x1
```

### Minimal IP_TRANSPARENT listener proof

A temporary Perl listener set `IP_TRANSPARENT` and listened on `0.0.0.0:18082`; a temporary rule matched the exact client literal-IP HTTPS tuple:

```bash
iptables -t mangle -I PREROUTING 1 \
  -i tun0 -s 10.89.0.2/32 -p tcp -d 1.1.1.1 --dport 443 \
  -j TPROXY --on-port 18082 --tproxy-mark 0x1/0x1
```

Probe/listener evidence:

```text
PROBE_LISTEN 0.0.0.0:18082
curl: (28) Failed to connect to 1.1.1.1 port 443 after 3004 ms: Timeout was reached

Chain PREROUTING
1 6 360 TPROXY tcp -- tun0 * 10.89.0.2 1.1.1.1 tcp dpt:443 TPROXY redirect 0.0.0.0:18082 mark 0x1/0x1
```

No `PROBE_ACCEPT` line appeared. This rejects the TPROXY path in this local Docker/kernel environment because the kernel/netfilter rule matched but local transparent socket delivery did not complete.

### TUN fallback attempt

A sing-box `tun` inbound with `auto_route`/`auto_redirect` was also tested. It started, but policy-routing forwarded packets to the TUN peer address rather than preserving original destinations:

```text
23:36:27.520364 tun0 In  10.89.0.2.49825 > 8.8.8.8.53
23:36:27.520380 sb-tun0 Out 10.89.0.2.49825 > 172.19.0.2.53
```

The TUN fallback was therefore not used as the final architecture.

## Final working architecture verification

Commands run from worktree `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/containerized-vpnkit-openvpn-singbox`.

### Static/config checks

```bash
bash -n docker/vpnkit/entrypoint.sh docker/vpnkit/setup-routing.sh \
  docker/ovpn-client-test/entrypoint.sh docker/ovpn-client-test/run-tests.sh \
  scripts/vpnkit-render-local-configs.sh scripts/vpnkit-collect-evidence.sh
./scripts/vpnkit-render-local-configs.sh
docker run --rm --entrypoint sing-box -e ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true \
  -v "$PWD/secrets/vps/rendered/sing-box/config.json:/etc/sing-box/config.json:ro" \
  containerized-vpnkit-openvpn-singbox-vpnkit check -c /etc/sing-box/config.json
docker compose config >/tmp/vpnkit-compose-final.yml
git diff --check
grep -R "POSTROUTING.*10.89.0.0/24.*MASQUERADE" docker config scripts || true
grep -R "xray" docker config scripts/vpnkit-* docs/CONTAINERIZED_VPNKIT_RUNBOOK.md || true
```

Results:

```text
bash -n: passed
render: Rendered secrets/vps/rendered/openvpn/server.conf, secrets/vps/rendered/sing-box/config.json, and secrets/vps/openvpn/client/test-client.ovpn
sing-box check: passed (only legacy DNS warning from sing-box 1.13.11)
docker compose config: passed
git diff --check: passed
runtime broad MASQUERADE grep: no matches
lab xray dependency grep: no matches
```

### Docker end-to-end check

```bash
docker compose --profile test down --remove-orphans
docker compose build
docker compose up -d vpnkit
docker compose --profile test run --rm ovpn-client-test
docker compose exec -T vpnkit iptables -t nat -L OVPN_REDIRECT_TO_SINGBOX -v -n -x
docker compose logs --no-color --tail=120 vpnkit
```

Client tunnel and route evidence:

```text
inet 10.89.0.2/24 scope global tun0
0.0.0.0/1 via 10.89.0.1 dev tun0
128.0.0.0/1 via 10.89.0.1 dev tun0
```

Client DNS evidence:

```text
; <<>> DiG 9.18.49-1~deb12u1-Debian <<>> +time=10 +tries=1 @8.8.8.8 example.com
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR
;; ANSWER SECTION:
example.com. 17 IN A 104.20.23.154
example.com. 17 IN A 172.66.147.243
;; SERVER: 8.8.8.8#53(8.8.8.8) (UDP)
```

Client HTTPS evidence:

```text
https-test http_code=200 remote_ip=34.117.59.81
literal-ip-test http_code=200 remote_ip=1.1.1.1
```

Redirect counter evidence after the test:

```text
Chain OVPN_REDIRECT_TO_SINGBOX (1 references)
    pkts bytes target   prot source       destination
       2   120 REDIRECT tcp  0.0.0.0/0    0.0.0.0/0    redir ports 2082
       1    80 REDIRECT udp  0.0.0.0/0    0.0.0.0/0    udp dpt:53 redir ports 5353
```

sing-box DNS path evidence:

```text
inbound/direct[vpnkit-dns-in]: inbound packet connection from 10.89.0.2:56545
inbound/direct[vpnkit-dns-in]: inbound packet connection to 0.0.0.0:5353
router: match[0] inbound=vpnkit-dns-in => hijack-dns
dns: exchange example.com. IN A
outbound/vless[selected-native-out]: outbound connection to 1.1.1.1:853
dns: exchanged example.com NOERROR
```

sing-box TCP path evidence:

```text
inbound/redirect[vpnkit-redirect-in]: inbound connection from 10.89.0.2:38284
inbound/redirect[vpnkit-redirect-in]: inbound connection to 34.117.59.81:443
outbound/vless[selected-native-out]: outbound connection to 34.117.59.81:443

inbound/redirect[vpnkit-redirect-in]: inbound connection from 10.89.0.2:40214
inbound/redirect[vpnkit-redirect-in]: inbound connection to 1.1.1.1:443
outbound/vless[selected-native-out]: outbound connection to 1.1.1.1:443
```

Full redacted command output was captured in local temp file `/tmp/vpnkit-final-verify.txt` during the run and summarized above. Do not commit local `secrets/` or raw Docker logs containing secret-bearing config.

## Acceptance mapping

- AC1 containers build/start: passed (`docker compose build`, `docker compose up -d vpnkit`).
- AC2 OpenVPN client gets `10.89.0.x`: passed (`inet 10.89.0.2/24 scope global tun0`).
- AC3 traffic enters `vpnkit` `tun0`: passed (OpenVPN server assigns `10.89.0.2`; redirect counters increment from `tun0` PREROUTING chain; earlier tcpdump showed ingress on `tun0`).
- AC4 traffic reaches sing-box: passed (`vpnkit-redirect-in` and `vpnkit-dns-in` logs from `10.89.0.2`).
- AC5 selected-native-out VLESS used: passed (sing-box logs show `outbound/vless[selected-native-out]` for DNS-over-TLS and HTTPS destinations).
- AC6 DNS succeeds and is under sing-box: passed (`dig` NOERROR; `vpnkit-dns-in` + `hijack-dns` + `selected-native-out` to `1.1.1.1:853`).
- AC7 HTTPS succeeds: passed (`https-test http_code=200`).
- AC8 literal-IP HTTPS succeeds: passed (`literal-ip-test http_code=200 remote_ip=1.1.1.1`).
- AC9 no broad permanent MASQUERADE/no xray: passed (`grep` checks; final routing uses REDIRECT only).
- AC10 fresh evidence recorded: passed (this file).
- AC11 coherent commit: passed with commit `Fix containerized vpnkit lab routing`.

## Remaining caveats

- Final architecture is REDIRECT, not TPROXY. This is intentional based on the TPROXY minimal-listener blocker evidence above.
- sing-box 1.13.11 emits a legacy DNS config warning; config still validates and runs when `ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true` is set. Migrating DNS config to post-1.13 syntax is a follow-up, not a current blocker.
- `privileged: true` remains in compose for this local lab harness; reducing to exact capabilities can be a follow-up once the routing mode is stable.
