# Steam Deck hotspot VPN test report

- Timestamp: 2026-06-05T11:37:30Z
- SSH target: <redacted>
- Mutation: none/read-only

```text
[2026-06-05T11:37:30Z] interfaces
lo               UNKNOWN        <IP>/8 ::1/128 
wlan0            UP             <IP>/24 
tailscale0       UNKNOWN        <IP>/32 <IPv6>/128 <IPv6>/64 
tun0             UNKNOWN        <IP>/24 <IPv6>/64 
ap0              UP             <IP>/24 
[2026-06-05T11:37:30Z] routes
<IP> via <IP> dev tun0 src <IP> uid 1000 
    cache 
<IP> via <IP> dev tun0 src <IP> uid 1000 
    cache 
[2026-06-05T11:37:30Z] vpn iface
11: tun0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1400 qdisc fq_codel state UNKNOWN mode DEFAULT group default qlen 500
    link/none 
[2026-06-05T11:37:30Z] hotspot iface
21: ap0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default qlen 1000
    link/ether <MAC> brd <MAC>
[2026-06-05T11:37:30Z] dnsmasq readiness
container=vpnkit-deck-hotspot-ap status=Up 12 minutes image=localhost/vpnkit-deck-hotspot-ap:latest
Error: OCI runtime error: crun: open executable: Transport endpoint is not connected
Error: OCI runtime error: crun: open executable: Transport endpoint is not connected
UNCONN 0      0          <IP>:53         <IP>:*    users:(("dnsmasq",pid=4009073,fd=8))      
UNCONN 0      0          <IP>:53         <IP>:*    users:(("dnsmasq",pid=4009073,fd=6))      
UNCONN 0      0        <IP>%ap0:67         <IP>:*    users:(("dnsmasq",pid=4009073,fd=4))      
UNCONN 0      0              [::1]:53            [::]:*    users:(("dnsmasq",pid=4009073,fd=10))     
log_file=hostapd.log
ap0: AP-ENABLED 
log_file=dnsmasq.log missing
[2026-06-05T11:37:31Z] nft tables relevant
table inet vpnkit_deck_hotspot {
	chain forward {
		type filter hook forward priority filter; policy accept;
		iifname "ap0" oifname "tun0" accept
		iifname "tun0" oifname "ap0" ct state established,related accept
		iifname "ap0" oifname "wlan0" reject
	}

	chain postrouting {
		type nat hook postrouting priority srcnat; policy accept;
		ip saddr <IP>/24 oifname "tun0" masquerade
	}
}
[2026-06-05T11:37:31Z] icmp
PING <IP> (<IP>): 56 data bytes
64 bytes from <IP>: icmp_seq=0 ttl=251 time=63.920 ms
64 bytes from <IP>: icmp_seq=1 ttl=252 time=88.812 ms
64 bytes from <IP>: icmp_seq=2 ttl=253 time=108.630 ms
--- <IP> ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max/stddev = 63.920/87.121/108.630/18.292 ms
PING <IP> (<IP>): 56 data bytes
64 bytes from <IP>: icmp_seq=0 ttl=253 time=85.477 ms
64 bytes from <IP>: icmp_seq=1 ttl=254 time=20.761 ms
64 bytes from <IP>: icmp_seq=2 ttl=255 time=129.046 ms
--- <IP> ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max/stddev = 20.761/78.428/129.046/44.487 ms
[2026-06-05T11:37:35Z] dns
[2026-06-05T11:37:35Z] ip identity
ip_ifconfig_me=ok ip_hash=9660050a
ip_ipify=ok ip_hash=9660050a
[2026-06-05T11:37:36Z] https
https_x=ok body_hash=d9cfe08a
https_ya=ok body_hash=e3b0c442
https_linkedin=ok body_hash=22c3949a
[2026-06-05T11:37:39Z] nft tables relevant
table inet vpnkit_deck_hotspot
```

## Client-side checks to run while connected to the Deck hotspot

```bash
ip route get <IP> || true
ping -4 -c 3 <IP>
ping -4 -c 3 <IP>
nslookup x.com
nslookup ya.ru
nslookup www.linkedin.com
curl -4 --max-time 20 https://x.com/ -o /dev/null -w 'x=%{http_code}\n'
curl -4 --max-time 20 https://ya.ru/ -o /dev/null -w 'ya=%{http_code}\n'
curl -4 --max-time 20 https://www.linkedin.com/ -o /dev/null -w 'linkedin=%{http_code}\n'
curl -4 --max-time 20 https://ifconfig.me
curl -4 --max-time 20 https://api.ipify.org
curl -6 --max-time 10 https://ifconfig.me || true
```
