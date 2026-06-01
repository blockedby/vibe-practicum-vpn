# Acceptance plan: containerized vpnkit OpenVPN -> sing-box lab

## Acceptance criteria coverage plan

- AC1 Real config copied into gitignored `secrets/`, not committed
  - Evidence to collect: `scripts/vpnkit-copy-vps-secrets.sh`, `find secrets/vps -type f`, `git status --short`, secret-pattern grep.
  - Status now: pending live operator copy.

- AC2 `vpnkit` starts OpenVPN server and sing-box with real native VLESS config
  - Evidence to collect: `docker compose up -d vpnkit`, `docker compose logs vpnkit`, `sing-box check`.
  - Status now: pending live runtime.

- AC3 `ovpn-client-test` connects and gets `10.89.0.x`
  - Evidence to collect: `docker compose --profile test up ovpn-client-test`, client `ip addr`, client logs.
  - Status now: pending live runtime.

- AC4 Client packets visible on `vpnkit` `tun0`
  - Evidence to collect: `tcpdump -ni tun0 ...` in `vpnkit`.
  - Status now: pending live runtime.

- AC5 TPROXY counters increase
  - Evidence to collect: `iptables -t mangle -L OVPN_TO_SINGBOX -v -n -x` before/after traffic.
  - Status now: pending live runtime.

- AC6 sing-box logs/metrics show `inbound/tproxy` from `10.89.0.x`
  - Evidence to collect: `docker compose logs vpnkit` with redacted client IP.
  - Status now: pending live runtime.

- AC7 sing-box logs/metrics show `selected-native-out` to real VLESS server
  - Evidence to collect: redacted vpnkit logs and rendered sing-box config.
  - Status now: pending live runtime.

- AC8 DNS handled by sing-box rules, not permanent broad NAT bypass
  - Evidence to collect: rendered config, route rules, static grep for `MASQUERADE`, runtime DNS query results.
  - Status now: static safety checks passed; runtime DNS still pending.

- AC9 DNS replies return to the OpenVPN client container
  - Evidence to collect: client `dig example.com` output.
  - Status now: pending live runtime.

- AC10 HTTPS works through native VLESS outbound
  - Evidence to collect: client `curl https://ifconfig.me` output and outbound log correlation.
  - Status now: pending live runtime.

- AC11 Literal-IP TCP path works
  - Evidence to collect: client `curl --resolve example.com:443:1.1.1.1 ...` result.
  - Status now: pending live runtime.

## Fresh local evidence already available

- `bash -n` on new shell scripts: passed.
- `docker compose config`: passed.
- Static grep for broad NAT bypass in lab runtime files: passed (none found).
- Static grep for `xray` in lab runtime/docs: passed (none found).
- Static secret-pattern grep for obvious committed UUID/private-key/full-link patterns: passed.

## Required before acceptance

1. Copy operator-provided VPS material into gitignored `secrets/vps/...`.
2. Render local configs and client profile from copied material.
3. Run the Docker lab and capture runtime evidence for AC2-AC7 and AC9-AC11.
4. Save redacted logs/counters/output under this task package.
