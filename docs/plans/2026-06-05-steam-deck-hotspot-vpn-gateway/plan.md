# Steam Deck Wi-Fi Hotspot VPN Gateway Plan

## Goal

Turn the Steam Deck into a local Wi-Fi hotspot/router whose connected clients egress through the selected VPN/proxy path, with a repeatable implementation, tests, logs, and rollback.

Target topology:

```text
Phone/Laptop/etc
  -> Steam Deck Wi-Fi hotspot
  -> Steam Deck host network forwarding/NAT
  -> VPN tunnel on Steam Deck, preferably from a Podman container in host network namespace
  -> VPS/proxy selected outbound
  -> Internet
```

## Scope

In scope:
- Use SSH access to Steam Deck for discovery and implementation.
- Treat one-adapter Steam Deck mode as the primary target: existing Wi-Fi stays as uplink and the same radio exposes a hotspot if the driver/NetworkManager supports concurrent STA+AP.
- Use USB Wi-Fi dongle mode only as fallback if one-adapter mode is not supported or is unstable.
- Reuse the existing Steam Deck deployment/runtime where possible; do not reinstall or replace already deployed services blindly.
- Run the VPN client in a controlled Deck runtime, preferably the existing Podman/Docker setup with host networking when compatible.
- Configure hotspot, IP forwarding, NAT, DNS handling, and kill-switch/no-leak rules.
- Produce logs and a clear report for every test run.

Out of scope:
- Mutating ASUS/router config.
- Publishing private endpoints, profiles, keys, logs, or generated configs.
- Making this public-facing; it is a local apartment gateway only.

## Safety / rollback principles

- Never depend on the ASUS router being changed.
- Keep current home internet as plain uplink; the Deck becomes the experimental gateway.
- Every mutating script must have `stop`/`rollback` commands:
  - stop VPN container/unit;
  - bring down hotspot connection;
  - remove nft/iptables rules created by us;
  - restore `ip_forward` if we changed it;
  - write final status/log even on failure.
- Kill-switch is required before calling the setup complete: hotspot clients must not fall back to Deck uplink if VPN drops.

## Phase 1: Discovery on Steam Deck

Goal:
- Determine which network topology is possible and what tools are already installed/running, without disturbing existing Deck services.

Commands/evidence to collect over SSH:

```bash
hostnamectl
uname -a
ip -br link
ip -br addr
ip route
nmcli --version
nmcli dev status
nmcli con show
podman --version || true
docker --version || true
ls -l /dev/net/tun || true
sysctl net.ipv4.ip_forward
command -v nft || true
command -v iptables || true
```

Wi-Fi capability checks:

```bash
iw dev
for phy in /sys/class/ieee80211/*; do basename "$phy"; done
# if iw supports it:
iw list | grep -A20 'Supported interface modes'
iw list | grep -A20 'valid interface combinations'
```

Acceptance criteria:
- We know existing relevant Deck services/containers/connections and have not overwritten them.
- We know the uplink interface.
- We know candidate hotspot interface(s).
- We know whether one-adapter STA+AP is possible or whether a dongle is needed.
- We know whether Podman and `/dev/net/tun` are available.
- Discovery report is saved under `reports/` without secrets.

## Phase 2: Choose runtime topology

Decision order:

### Option A: One-adapter concurrent STA+AP, primary target

```text
Deck wlan0 -> home Wi-Fi uplink
Deck wlan0/virtual AP -> local hotspot
hotspot clients -> NAT -> tun0 VPN
```

Why first:
- Keeps the Steam Deck physically self-contained.
- Avoids a dongle sticking out of the box/enclosure.
- Matches the desired apartment appliance shape.

What must be proven before mutation:
- `iw list` shows AP mode and a valid interface combination compatible with STA+AP.
- NetworkManager can create or activate AP mode without dropping the uplink permanently.
- If STA+AP forces same channel as uplink, the hotspot remains stable enough for target clients.

Risks:
- Some Wi-Fi chipsets advertise AP mode but fail concurrent STA+AP in practice.
- Throughput/latency can be worse than two-adapter mode.
- Hotspot may disappear when Deck roams/reconnects uplink.

### Option B: USB Wi-Fi dongle fallback

```text
Deck internal wlan0 -> home Wi-Fi uplink
Deck USB Wi-Fi wlan1 -> hotspot AP
hotspot clients -> NAT -> tun0 VPN
```

Use only if:
- One-adapter mode cannot be activated;
- or it activates but drops uplink;
- or it is unstable under client traffic;
- or kill-switch/DNS behavior is unreliable with same-radio AP.

Acceptance criteria:
- First attempt and report are for one-adapter mode.
- Dongle fallback is documented but not used unless evidence shows one-adapter mode is not viable.

## Phase 3: VPN client on Deck

Goal:
- Bring up the VPN tunnel on Deck in the host network namespace so host routing/NAT can use `tun0`.

Preferred implementation:
- Podman container, host network namespace:

```bash
podman run --rm --name deck-openvpn-client \
  --network host \
  --cap-add NET_ADMIN \
  --device /dev/net/tun:/dev/net/tun \
  -v /path/to/client.ovpn:/etc/openvpn/client.ovpn:ro \
  <openvpn-client-image> \
  openvpn --config /etc/openvpn/client.ovpn
```

Alternative:
- Native `openvpn --config ...` on Deck if container host-network TUN is problematic.

Validation from Deck:

```bash
ip -4 addr show tun0
ip -4 route get 1.1.1.1
ping -4 -c 3 1.1.1.1
curl -4 --max-time 15 https://ifconfig.me
curl -4 --max-time 15 https://api.ipify.org
```

Acceptance criteria:
- VPN connects.
- `tun0` exists in the Deck host namespace.
- Deck can route/ping/curl through the VPN.
- ifconfig/ipify hashes match expected proxy/VPN egress, not normal home direct egress.

## Phase 4: Hotspot setup

Goal:
- Create a Deck-hosted Wi-Fi AP with DHCP for test clients.

NetworkManager-style implementation candidate:

```bash
nmcli dev wifi hotspot ifname <hotspot-iface> ssid <test-ssid> password <test-password>
```

Or explicit connection:

```bash
nmcli con add type wifi ifname <hotspot-iface> con-name deck-vpn-hotspot autoconnect no ssid <test-ssid>
nmcli con modify deck-vpn-hotspot 802-11-wireless.mode ap 802-11-wireless.band bg ipv4.method shared
nmcli con modify deck-vpn-hotspot wifi-sec.key-mgmt wpa-psk wifi-sec.psk <test-password>
nmcli con up deck-vpn-hotspot
```

Acceptance criteria:
- Test phone/laptop can see and join SSID.
- Client receives DHCP address.
- Deck can identify hotspot interface and subnet.
- Without VPN forwarding yet, connectivity state is understood and logged.

## Phase 5: Forwarding, NAT, DNS, kill-switch

Goal:
- Hotspot clients can only egress via VPN tunnel.

Required behavior:
- Enable IPv4 forwarding.
- NAT hotspot subnet/interface to `tun0`.
- Allow forward hotspot -> `tun0` and established replies.
- Block hotspot -> normal uplink to avoid leaks.
- DNS from clients must work and must not leak outside the VPN path.

Implementation preference:
- Use a dedicated nftables table/chain with unique names, e.g. `vpnkit_deck_hotspot`, so rollback can remove only our rules.
- Fall back to iptables only if nft is unavailable or broken.

Example rule intent, not final blindly-run commands:

```text
forward: allow iif <hotspot-iface> oif tun0
forward: allow iif tun0 oif <hotspot-iface> ct state established,related
forward: reject/drop iif <hotspot-iface> oif <uplink-iface>
nat postrouting: masquerade oif tun0 from <hotspot-subnet>
optional dns redirect: udp/tcp 53 from hotspot clients -> chosen DNS path
```

Acceptance criteria:
- Client route to internet works only while VPN is up.
- If VPN container stops, client internet fails closed instead of leaking via uplink.
- DNS resolution works from client.
- DNS and HTTP tests show VPN/proxy egress.

## Phase 6: Client-side test plan

From a device connected to the Deck hotspot:

Connectivity:

```bash
ip route get 1.1.1.1   # or platform equivalent
ping -4 -c 3 1.1.1.1
ping -4 -c 3 8.8.8.8
```

DNS:

```bash
nslookup x.com
nslookup ya.ru
nslookup www.linkedin.com
```

HTTPS:

```bash
curl -4 --max-time 20 https://x.com/
curl -4 --max-time 20 https://ya.ru/
curl -4 --max-time 20 https://www.linkedin.com/
```

IP identity:

```bash
curl -4 --max-time 20 https://ifconfig.me
curl -4 --max-time 20 https://api.ipify.org
# Browser/manual: Yandex Internetometer
```

Leak tests:

```bash
curl -6 --max-time 10 https://ifconfig.me || true
```

Acceptance criteria:
- x.com, ya.ru, linkedin.com reachable.
- DNS resolves target domains.
- ifconfig/ipify agree with VPN/proxy egress.
- IPv6 is either routed intentionally through VPN or unavailable; no unexpected direct IPv6 leak.
- Stopping VPN causes hotspot client internet to fail, not bypass.

## Phase 7: Automation scripts

Planned scripts:

1. `scripts/deck-hotspot-discover.sh`
   - SSH to Deck.
   - Read-only inventory.
   - Save report.

2. `scripts/deck-hotspot-vpn-up.sh`
   - Start/ensure VPN client on Deck.
   - Bring up hotspot.
   - Apply forwarding/NAT/kill-switch.
   - Write live log and report path immediately.

3. `scripts/deck-hotspot-vpn-test.sh`
   - Run Deck-side tests.
   - Optionally run client-side instructions/report template.

4. `scripts/deck-hotspot-vpn-down.sh`
   - Stop hotspot.
   - Stop VPN container/unit.
   - Remove only our firewall rules.
   - Restore forwarding setting if needed.

5. Optional web panel integration:
   - Add buttons for discover/up/test/down.
   - No arbitrary command execution.
   - Show durable logs as they are written.

Acceptance criteria:
- Every mutating script writes a timestamped log under `reports/` from the beginning.
- `down` is idempotent.
- `up` refuses unsafe ambiguous interface state unless explicitly overridden.
- Scripts redact private endpoints/IPs in user-facing output.

## Phase 8: Persistence decision

After manual proof works, decide whether to persist:

Options:
- Manual scripts only, no persistence.
- systemd user/root units for:
  - VPN client container;
  - hotspot setup;
  - firewall rules.
- NetworkManager connection autostart for hotspot only when explicitly enabled.

Acceptance criteria for persistence:
- Reboot Deck.
- Verify hotspot starts only if intended.
- Verify VPN is up before clients get internet, or fail closed.
- Verify `down`/rollback still works.

## Execution order

1. Discovery on Deck.
2. Decide one-adapter vs dongle topology.
3. Prove VPN tunnel in Deck host namespace.
4. Prove hotspot joins and DHCP.
5. Add NAT/forwarding without persistence.
6. Add kill-switch and DNS handling.
7. Test from client device.
8. Package scripts + logs + rollback.
9. Optional web UI integration.
10. Optional persistence after manual success.

## First concrete next command

Start with read-only discovery, no mutation:

```bash
ssh <steam-deck-ssh-target> '
  hostnamectl;
  uname -a;
  ip -br link;
  ip -br addr;
  ip route;
  nmcli dev status;
  nmcli con show;
  podman --version || true;
  ls -l /dev/net/tun || true;
  sysctl net.ipv4.ip_forward;
  command -v nft || true;
  command -v iptables || true;
  iw dev || true;
  iw list | grep -A20 "Supported interface modes" || true;
  iw list | grep -A30 "valid interface combinations" || true
'
```

## 2026-06-05 execution update

Discovery evidence is recorded in:

- `docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway/reports/explorer.md`
- `docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway/reports/host-egress-discovery.md`
- `docs/plans/2026-06-05-steam-deck-hotspot-vpn-gateway/verification/discover-smoke.md`

Prepared scripts:

- `scripts/deck-hotspot-vpn-discover.sh` — read-only inventory and redacted report.
- `scripts/deck-hotspot-vpn-up.sh` — dry-run/apply one-adapter hotspot + nft kill-switch/NAT. Defaults to dry-run; apply requires `--apply --yes` and a password.
- `scripts/deck-hotspot-vpn-test.sh` — read-only Deck-side checks and client-side test checklist.
- `scripts/deck-hotspot-vpn-down.sh` — idempotent cleanup of this tool's NetworkManager connection and nft table.

Current evidence:

- Internal Wi-Fi one-adapter STA+AP remains the primary path and appears viable from `iw list` valid interface combinations.
- Existing `vpnkit` Podman container exists and should not be overwritten blindly.
- Fresh dry-run evidence shows `tun0` is not currently present in the Deck host namespace, so the existing `vpnkit` runtime likely keeps OpenVPN/TUN inside the container. Gateway `up --apply` should not be run until a host-namespace VPN egress interface is available or the gateway design is adjusted to forward into the existing container path explicitly.

Current next blocker:

- Decide/implement the host-namespace VPN egress path on Deck:
  1. run a client/VPN container with `--network host` and `/dev/net/tun` so `tun0` exists on the Deck host; or
  2. expose a different host-routable egress interface/path from the existing `vpnkit` container and update `deck-hotspot-vpn-up.sh --vpn-iface`/NAT accordingly.

Do not run mutating hotspot setup until this blocker is resolved.
