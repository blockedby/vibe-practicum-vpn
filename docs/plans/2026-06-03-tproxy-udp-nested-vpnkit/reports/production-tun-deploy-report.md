# Production TUN deploy report

Date: 2026-06-03
Branch: `vpnkit-tproxy-udp-nested`

## Summary

Production `vpnkit` was updated on both public backends and validated from the development host with the real user profile:

```text
/home/kcnc/Desktop/rabotau-na-prod-ovpn/rabotau-na-two-server-device1.ovpn
```

Final result: **PASS / no rollback performed**.

Both production backends now run:

```text
VPNKIT_ROUTING_MODE=tun
OpenVPN client subnet: 10.231.89.0/24
OpenVPN gateway/DNS push: 10.231.89.1
sing-box TUN interface: sb-tun0 172.19.0.1/30
policy rule: from 10.231.89.0/24 lookup 101
```

## Rollback markers

Pre-deploy rollback image tags were created before production mutation:

```text
vibe-practicum: src-vpnkit:rollback-pre-tun-20260603T144652Z
moscow-tiger:   current-vpnkit:rollback-pre-tun-20260603T144652Z
```

Additional `vibe-practicum` OpenVPN rendered material backup was created before syncing PKI:

```text
/opt/vpnkit/src/openvpn-rendered-backup-pre-moscow-pki-20260603T151419Z.tgz
```

## Production changes made

### vibe-practicum / 45.12.74.211

- Compose project/container now active as `src-vpnkit-1`.
- Rebuilt from current branch source and started with `VPNKIT_ROUTING_MODE=tun`.
- OpenVPN rendered server config updated to `10.231.89.0/24` and DNS `10.231.89.1`.
- OpenVPN PKI/ta material was synced from `moscow-tiger` so the same `rabotau-na` profiles are accepted by both failover backends.
- Final image ID observed: `sha256:99bf4a877974a5ca1f91c2333ce2822a9fce14c028ca6e6ed1cddc9281231b3b`.

### moscow-tiger / 178.20.45.245

- Compose project/container active as `current-vpnkit-1`.
- Source tree overlaid with current branch source while preserving existing secrets/PKI.
- Rendered OpenVPN server config updated to `10.231.89.0/24` and DNS `10.231.89.1`.
- TUN rendered sing-box config regenerated using the host's native selected VLESS outbound.
- Added `packet_encoding: xudp` for VLESS selected outbound in TUN mode, because UDP/NTP through the selected outbound timed out without it.
- Final image ID observed: `sha256:72a191f953b9ec7ad78f6401e16f982fb5c7e49e361f927b0e6e00628d47f59d`.

## Final production health

### vibe-practicum

```text
container: src-vpnkit-1
status: running
restart: 0
published port: 0.0.0.0:1194->1194/udp
OpenVPN server: 10.231.89.0/24
DNS push: 10.231.89.1
sb-tun0: 172.19.0.1/30
policy route: from 10.231.89.0/24 lookup 101, default via 172.19.0.2 dev sb-tun0
processes: openvpn, sing-box, vibe-vpn daemon all running
```

### moscow-tiger

```text
container: current-vpnkit-1
status: running
restart: 0
published port: 0.0.0.0:1194->1194/udp
OpenVPN server: 10.231.89.0/24
DNS push: 10.231.89.1
sb-tun0: 172.19.0.1/30
policy route: from 10.231.89.0/24 lookup 101, default via 172.19.0.2 dev sb-tun0
processes: openvpn, sing-box, vibe-vpn daemon all running
```

## Client validation from development host

Validation used Docker/OpenVPN client containers with the real profile or exact temporary copies that only forced a single `remote` line for backend-specific checks. No generated profile, key, cert, rendered config, or raw secret was committed.

### Real profile as-is

```text
profile: /home/kcnc/Desktop/rabotau-na-prod-ovpn/rabotau-na-two-server-device1.ovpn
connected remote: 178.20.45.245:1194
assigned tunnel IP: 10.231.89.2/24
DNS @8.8.8.8: NOERROR
HTTPS hostname: 200
literal-IP HTTPS: 200
public UDP/NTP: OK, 48-byte response
observed egress IP: 194.180.188.136
result: PASS
```

### Forced moscow-tiger backend

```text
remote: 178.20.45.245:1194
assigned tunnel IP: 10.231.89.2/24
DNS @8.8.8.8: NOERROR
HTTPS hostname: 200
literal-IP HTTPS: 200
public UDP/NTP: OK on retry after xudp fix
observed egress IP: 194.180.188.136
result: PASS
```

### Forced vibe-practicum backend

```text
remote: 45.12.74.211:1194
assigned tunnel IP: 10.231.89.2/24
DNS @8.8.8.8: NOERROR
HTTPS hostname: 200
public UDP/NTP: OK, 48-byte response
observed egress IP: 45.12.74.211
result: PASS
```

## Issues encountered and resolved

### D-01: root deploy agent stalled mid-run

The async root-owner stalled after setting rollback tags and partial validation. It was interrupted and the deployment was completed manually.

### D-02: moscow TUN config initially used direct selected outbound

The first moscow TUN config had `selected-native-out` rendered as direct, which caused sing-box startup failure while bootstrapping remote rule sets through `8.8.8.8:853`. The rendered TUN config was regenerated from moscow's native selected VLESS outbound.

### D-03: vibe profile mismatch

The real `rabotau-na` profile matched moscow CA/ta material, while `vibe-practicum` still had a different OpenVPN CA/ta. Forced vibe testing produced OpenVPN `incoming packet authentication failed`. The old vibe rendered OpenVPN material was backed up, then vibe OpenVPN PKI/ta material was synced from moscow. Forced vibe testing passed afterward.

### D-04: moscow public UDP over selected VLESS needed XUDP

Moscow DNS/HTTPS worked, but public UDP/NTP initially timed out through the selected VLESS outbound. Adding `packet_encoding: xudp` to the TUN-rendered VLESS selected outbound fixed UDP/NTP without routing UDP directly/leaking it outside the selected outbound.

## Source follow-up

`scripts/vpnkit-render-local-configs.sh` now adds `packet_encoding: xudp` to VLESS selected outbound only for rendered TUN configs. Redirect/TProxy rendered configs keep the selected outbound unchanged.

## Verification commands

Run after source/report update:

```text
bash tests/vpnkit-singbox-template-test.sh
bash tests/vpnkit-setup-routing-test.sh
bash tests/openvpn-server-template-test.sh
bash scripts/vpnkit-routing-compat-bypass-test.sh
go test ./...
git diff --check
```

All passed.

## Verdict

Production TUN deployment is successful on both backends. The real user profile does not need to be regenerated for the new subnet; it receives `10.231.89.x/24` and DNS `10.231.89.1` from the server push. Both explicit backends accept the same profile and pass DNS/HTTPS/public-UDP validation.
