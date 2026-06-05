# Steam Deck hotspot VPN discovery

- Timestamp: 2026-06-05T10:49:19Z
- SSH target: <redacted>
- Mutation: none/read-only

```text
[2026-06-05T10:49:19Z] host inventory

## hostnamectl
 Static hostname: steamdeck
       Icon name: computer-laptop
         Chassis: laptop 💻
      Machine ID: <redacted>
         Boot ID: <redacted>
Operating System: SteamOS
          Kernel: Linux 6.11.11-valve27-1-neptune-611-g60ef8556a811
    Architecture: x86-64
 Hardware Vendor: Valve
  Hardware Model: Galileo
Firmware Version: F7G0112
   Firmware Date: Thu 2024-08-01
    Firmware Age: 1y 10month 3d

## uname
Linux steamdeck 6.11.11-valve27-1-neptune-611-g60ef8556a811 #1 SMP PREEMPT_DYNAMIC Thu, 08 Jan 2026 10:09:09 +0000 x86_64 GNU/Linux

## ip-link
lo               UNKNOWN        <MAC> <LOOPBACK,UP,LOWER_UP> 
wlan0            UP             <MAC> <BROADCAST,MULTICAST,UP,LOWER_UP> 
tailscale0       UNKNOWN        <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> 

## ip-addr
lo               UNKNOWN        <IP>/8 ::1/128 
wlan0            UP             <IP>/24 
tailscale0       UNKNOWN        <IP>/32 <IPv6>/128 <IPv6>/64 

## ip-route
default via <IP> dev wlan0 proto dhcp src <IP> metric 600 
<IP>/24 dev wlan0 proto kernel scope link src <IP> metric 600 

## nmcli-dev
DEVICE              TYPE      STATE                  
wlan0               wifi      connected              
tailscale0          tun       connected (externally) 
lo                  loopback  connected (externally) 
/net/connman/iwd/0  wifi-p2p  disconnected           

## nmcli-con
TYPE      DEVICE      AUTOCONNECT 
wifi      wlan0       yes         
tun       tailscale0  no          
loopback  lo          no          
wifi      --          yes         
wifi      --          yes         
wifi      --          yes         
wifi      --          yes         
wifi      --          yes         
wifi      --          yes         
wifi      --          yes         
wifi      --          yes         
wifi      --          yes         
wifi      --          yes         
wifi      --          yes         
wifi      --          yes         
wifi      --          yes         
wifi      --          yes         

## runtime
/home/deck/.bash_profile: line 20: nodenv: command not found
podman version 5.3.2
podman version 5.3.2
NAMES       IMAGE                       STATUS      PORTS
vpnkit      localhost/vpnkit:steamdeck  Up 4 days   <IP>:1194->1194/udp

## tun-forward-firewall
/home/deck/.bash_profile: line 20: nodenv: command not found
crw-rw-rw- 1 root root 10, 200 May 27 23:42 /dev/net/tun
net.ipv4.ip_forward = 0
/usr/bin/nft
/usr/bin/iptables

## wifi-dev
phy#0
	Unnamed/non-netdev interface
		wdev 0x3
		addr <MAC>
		type P2P-device
		txpower 16.00 dBm
	Interface wlan0
		ifindex 3
		wdev 0x2
		addr <MAC>
		type managed
		channel 12 (2467 MHz), width: 40 MHz, center1: 2457 MHz
		txpower 16.00 dBm
		multicast TXQ:
			qsz-byt	qsz-pkt	flows	drops	marks	overlmt	hashcol	tx-bytes	tx-packets
			0	0	0	0	0	0	0	0		0

## wifi-supported-modes
/home/deck/.bash_profile: line 20: nodenv: command not found
	Supported interface modes:
		 * managed
		 * AP
		 * P2P-client
		 * P2P-GO
		 * P2P-device
	Band 1:

## wifi-valid-combinations
/home/deck/.bash_profile: line 20: nodenv: command not found
	valid interface combinations:
		 * #{ managed } <= 2, #{ AP, P2P-client, P2P-GO } <= 1, #{ P2P-device } <= 1,
		   total <= 3, #channels <= 2, STA/AP BI must match
	HT Capability overrides:
		 * MCS: ff ff ff ff ff ff ff ff ff ff
		 * maximum A-MSDU length
		 * supported channel width
		 * short GI for 40 MHz
		 * max A-MPDU length exponent
		 * min MPDU start spacing
	Device supports TX status socket option.
```
