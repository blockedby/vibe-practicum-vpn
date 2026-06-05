# Steam Deck hotspot VPN up report

- Timestamp: 2026-06-05T11:36:30Z
- SSH target: <redacted>
- Mode: dry-run
- Topology: wlan0 uplink, ap0 hostapd AP, tun0 VPN egress

```text
[2026-06-05T11:36:31Z] preflight
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
<IP> via <IP> dev tun0 src <IP> uid 1000 
    cache 
[2026-06-05T11:36:31Z] dry-run plan: would create virtual AP iface ap0 from wlan0
[2026-06-05T11:36:31Z] dry-run plan: would assign <IP>/24 to ap0
[2026-06-05T11:36:31Z] dry-run plan: would build/run hostapd+dnsmasq container vpnkit-deck-hotspot-ap (localhost/vpnkit-deck-hotspot-ap:latest)
[2026-06-05T11:36:31Z] dry-run plan: would enable net.ipv4.ip_forward=1 and nft NAT <IP>/24 -> tun0
```
