# Steam Deck hotspot client DHCP success

- Timestamp: 2026-06-05T11:56:47Z
- Context: after adding `ap0` to firewalld `trusted` zone and restarting the Deck hotspot stack.
- Privacy: client MAC, private IPs, and device-specific values redacted or limited to the public test subnet.

## Result

Client association and DHCP completed successfully:

```text
hostapd: AP-STA-CONNECTED <client-mac>
hostapd: EAPOL-4WAY-HS-COMPLETED <client-mac>
dnsmasq: DHCPDISCOVER(ap0) <client-mac>
dnsmasq: DHCPOFFER(ap0) 10.42.0.95 <client-mac>
dnsmasq: DHCPREQUEST(ap0) 10.42.0.95 <client-mac>
dnsmasq: DHCPACK(ap0) 10.42.0.95 <client-mac> <client-name>
```

Client DNS traffic was observed from the leased address immediately after DHCP ACK:

```text
dnsmasq: query[A] www.google.com from 10.42.0.95
dnsmasq: reply www.google.com is <redacted>
dnsmasq: query[A] connectivitycheck.gstatic.com from 10.42.0.95
dnsmasq: reply connectivitycheck.gstatic.com is <redacted>
```

## Fix confirmed

The previous failure mode was: Wi-Fi association succeeded, but `dnsmasq` saw no DHCP requests. Firewalld was active with `wlan0` in `public`; `ap0` was not trusted. Adding `ap0` to firewalld `trusted` allowed DHCP to reach `dnsmasq`.

Relevant code commit already pushed:

```text
1c9c33f fix: trust Deck hotspot interface in firewalld
```
