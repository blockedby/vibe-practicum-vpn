# Live Docker validation — 2026-05-31

Related issue: https://github.com/blockedby/vibe-practicum-vpn/issues/11

## Plan followed

1. Copy real VPS config material from `vibe-practicum` into gitignored `secrets/vps/`.
2. Render local OpenVPN and sing-box configs.
3. Build Docker images.
4. Start `vpnkit` gateway container.
5. Start separate `ovpn-client-test`/`ovpn-client-live` OpenVPN client container.
6. Test DNS and HTTPS through the OpenVPN tunnel.
7. Capture TPROXY counters and sing-box logs.

## Commands/evidence summary

### Secret copy/render

Real material was copied with:

```bash
./scripts/vpnkit-copy-vps-secrets.sh vibe-practicum
./scripts/vpnkit-render-local-configs.sh
```

Material was stored only under gitignored `secrets/vps/`.

### Build/start

```bash
docker compose build
docker compose up -d vpnkit
docker compose --profile test build ovpn-client-test
```

Initial image build exposed one packaging issue: installing the `sing-box` `.deb` in `debian:bookworm-slim` failed because `systemd-sysusers` is absent. The Dockerfile was changed to install the upstream `sing-box-1.13.11-linux-amd64.tar.gz` binary directly.

Initial OpenVPN config rendering also exposed a live-config mismatch: the VPS material uses `tls-auth`, not `tls-crypt`. The templates were corrected to use `tls-auth`/`key-direction`.

### Gateway state

`vpnkit` starts successfully:

```text
OpenVPN server: tun0 = 10.89.0.1/24
sing-box: inbound/tproxy tcp server started at 0.0.0.0:2082
sing-box: inbound/tproxy udp server started at 0.0.0.0:2082
ip rule: fwmark 0x1 lookup 100
route table 100: local default dev lo
```

### Client state

A separate OpenVPN client container connects successfully:

```text
CN: ignat
client VPN IP: 10.89.0.2/24
routes:
  0.0.0.0/1 via 10.89.0.1 dev tun0
  128.0.0.0/1 via 10.89.0.1 dev tun0
```

This confirms OpenVPN auth, tunnel creation, pushed full-tunnel routing, and separate client network namespace.

### Packet/counter evidence

From `vpnkit` tcpdump during client tests:

```text
tun0 In 10.89.0.2 -> 8.8.8.8:53
tun0 In 10.89.0.2 -> 1.1.1.1:443 TCP SYN retransmits
```

TPROXY counters increase:

```text
Chain OVPN_TO_SINGBOX
  TCP TPROXY: packets increased
  UDP TPROXY: packets increased
```

Client tests fail by timeout:

```text
dig @8.8.8.8 example.com -> no servers could be reached
curl https://1.1.1.1 -> connection timed out
```

sing-box logs show the TPROXY listener started but do **not** show inbound accepts for `10.89.0.2`.

## Additional diagnostics

The failure reproduced with:

- default Docker capabilities plus `NET_ADMIN`/`NET_RAW`;
- `privileged: true` on the gateway container;
- iptables-nft TPROXY rules;
- native nftables TPROXY rules;
- a temporary Python `IP_TRANSPARENT` listener in the gateway container before recreate.

`xtables-monitor --trace` showed:

```text
raw PREROUTING
-> mangle PREROUTING
-> OVPN_TO_SINGBOX
-> TPROXY accept
```

But no userland transparent listener accepted the connection afterward.

## Current verdict

Partial success:

- OpenVPN-in-container works.
- Real VPS OpenVPN credentials work in the lab.
- Real sing-box VLESS config renders and the sing-box TPROXY listener starts.
- Client packets enter `vpnkit` `tun0` and match TPROXY rules.

Still failing:

```text
netfilter TPROXY accept -> userland transparent socket accept
```

This is the same boundary observed on the VPS, now reproduced in a clean Docker lab.

Failure classification: `INFRA`, high confidence.

First missing hop:

```text
sing-box inbound/tproxy accept for 10.89.0.2
```

or, more generally:

```text
any transparent listener accept after TPROXY
```

## Next highest-value step

Focus on a minimal transparent-socket kernel test in the `vpnkit` network namespace before further sing-box changes:

1. Add Python/socat test tooling to the gateway image.
2. Run a dedicated `IP_TRANSPARENT` TCP listener on a test port.
3. Add one TPROXY rule for `10.89.0.2 -> 1.1.1.1:443` to that test port.
4. Prove whether the transparent listener accepts.
5. If not, continue with kernel/netns prerequisites (`socket transparent`, route lookup with remote source, nft/iptables rule shape, required modules/sysctls).
6. Only after the minimal listener accepts, return to sing-box routing/DNS/VLESS validation.
