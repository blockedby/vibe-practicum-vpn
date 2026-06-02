# Local container verification: IPv4-only policy

Date: 2026-06-02
Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-compat-bypass`
Branch: `vpnkit-compat-bypass`

## Why this exists

The first live VPS attempt showed that live mutation is the wrong first test surface for `vpnkit` runtime policy changes. The VPS was restored to the previous tested image/config, then this branch was deployed locally with Docker Compose and the OpenVPN client-test container.

## Local setup

Gitignored secrets were copied into this worktree from the existing local Steam Deck worktree, then configs were rendered:

```bash
rm -rf secrets
cp -a /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/steamdeck-podman-vpnkit/secrets ./secrets
scripts/vpnkit-render-local-configs.sh
docker compose down -v --remove-orphans || true
```

The `-v` reset is important because the sing-box runtime config is persisted in `vpnkit-sing-box-state`; stale state can hide template changes such as DNS strategy.

## Local vpnkit runtime

Command:

```bash
VPNKIT_ENABLE_VIBE_VPN_DAEMON=true \
VPNKIT_IPV6_POLICY=block \
VPNKIT_COMPAT_BYPASS_ENABLED=true \
VPNKIT_COMPAT_BYPASS_ENDPOINTS='vpn.proofix.tv:1194/udp,vpn.proofix.tv:1194/tcp' \
docker compose up -d --build vpnkit
```

Observed:

```text
vpnkit container: Up
started sing-box pid=21 config=/var/lib/vpnkit/sing-box/config.json
OpenVPN Initialization Sequence Completed
Chain OVPN_IPV6_BLOCK (4 references)
Chain OVPN_REDIRECT_TO_SINGBOX (1 references)
Chain OVPN_COMPAT_POST (1 references)
Chain OVPN_COMPAT_FWD (2 references)
started vibe-vpn daemon pid=95 config=/etc/vibe-vpn/config.yaml
```

## OpenVPN client regression

Command:

```bash
VPNKIT_ENABLE_VIBE_VPN_DAEMON=true \
VPNKIT_IPV6_POLICY=block \
VPNKIT_COMPAT_BYPASS_ENABLED=true \
VPNKIT_COMPAT_BYPASS_ENDPOINTS='vpn.proofix.tv:1194/udp,vpn.proofix.tv:1194/tcp' \
docker compose --profile test run --rm ovpn-client-test
```

Result:

```text
OpenVPN connected to local compose vpnkit:1194
client tun0: 10.89.0.2/24
DNS @8.8.8.8 example.com: NOERROR
https-test http_code=200 remote_ip=172.66.147.243
literal-ip-test http_code=200 remote_ip=1.1.1.1
```

## IPv4-only DNS behavior

A second client-test container connected through OpenVPN and queried OpenAI DNS via explicit `@8.8.8.8`, which is hijacked by vpnkit/sing-box DNS.

Result:

```text
api.openai.com A:
  162.159.140.245
  172.66.0.243

api.openai.com AAAA:
  status: NOERROR
  ANSWER: 0

curl -4 https://api.openai.com/v1/models:
  code=401 ip=172.66.0.243
```

Interpretation:

- `dns.strategy=ipv4_only` is active through the OpenVPN client path.
- AAAA answers are suppressed instead of returning IPv6 targets that can blackhole Node/Codex.
- OpenAI API IPv4 path is reachable; `401` is expected without an API key.

## VPS restore note

The VPS was restored to the previous tested compat image/config before this local test:

- image restored from `vpnkit:vps-compat-fixed` to `vpnkit:vps`
- container restarted without `VPNKIT_IPV6_POLICY`
- temporary `dns.strategy=ipv4_only` was removed from live rendered/state sing-box configs
- running processes confirmed: `sing-box`, `openvpn`, `vibe-vpn daemon`
