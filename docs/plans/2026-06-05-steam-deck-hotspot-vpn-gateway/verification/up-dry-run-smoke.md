# Steam Deck hotspot VPN up report

- Timestamp: 2026-06-05T10:50:37Z
- SSH target: <redacted>
- Mode: dry-run
- Topology: wlan0 uplink, wlan0 hotspot, tun0 VPN egress

```text
[2026-06-05T10:50:37Z] preflight
DEVICE              TYPE      STATE                  
wlan0               wifi      connected              
tailscale0          tun       connected (externally) 
lo                  loopback  connected (externally) 
/net/connman/iwd/0  wifi-p2p  disconnected           
lo               UNKNOWN        <IP>/8 ::1/128 
wlan0            UP             <IP>/24 
tailscale0       UNKNOWN        <IP>/32 <IPv6>/128 <IPv6>/64 
<IP> via <IP> dev wlan0 src <IP> uid 1000 
    cache 
[2026-06-05T10:50:37Z] warning: vpn iface missing: tun0 (host-namespace VPN tunnel must exist before apply can succeed)
[2026-06-05T10:50:37Z] dry-run plan: would create NM AP connection vpnkit-deck-hotspot on wlan0
[2026-06-05T10:50:37Z] dry-run plan: would enable net.ipv4.ip_forward=1
[2026-06-05T10:50:37Z] dry-run plan: would create nft inet vpnkit_deck_hotspot allowing wlan0->tun0, replies, masquerade, and rejecting wlan0->wlan0
[2026-06-05T10:50:37Z] dry-run blocker: start/reuse a host-namespace VPN tunnel first; existing container may keep tun inside container only
```
