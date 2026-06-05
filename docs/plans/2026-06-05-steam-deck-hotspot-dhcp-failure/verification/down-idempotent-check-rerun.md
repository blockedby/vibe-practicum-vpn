# Steam Deck hotspot VPN down report

- Timestamp: 2026-06-05T11:38:15Z
- SSH target: <redacted>
- Container: vpnkit-deck-hotspot-ap-check
- nft table: vpnkit_deck_hotspot_check
- hotspot iface: ap0check

```text
[2026-06-05T11:38:16Z] down start
[2026-06-05T11:38:16Z] removing hotspot AP container vpnkit-deck-hotspot-ap-check
[2026-06-05T11:38:16Z] nft table inet vpnkit_deck_hotspot_check already absent
[2026-06-05T11:38:16Z] current status
DEVICE              TYPE      STATE                  
wlan0               wifi      connected              
tailscale0          tun       connected (externally) 
lo                  loopback  connected (externally) 
tun0                tun       connected (externally) 
/net/connman/iwd/0  wifi-p2p  disconnected           
ap0                 wifi      unavailable            
lo               UNKNOWN        <IP>/8 ::1/128 
wlan0            UP             <IP>/24 
tailscale0       UNKNOWN        <IP>/32 <IPv6>/128 <IPv6>/64 
tun0             UNKNOWN        <IP>/24 <IPv6>/64 
ap0              UP             <IP>/24 
net.ipv4.ip_forward = 1
[2026-06-05T11:38:16Z] down done
```
