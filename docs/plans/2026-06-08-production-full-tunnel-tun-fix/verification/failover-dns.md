# Failover DNS / endpoint reachability verification

- Check time: 2026-06-08T17:16-17:18Z
- Failover profile path: `secrets/vps/openvpn/client/rabotau-na-failover-20260608T162953Z/phone.ovpn` (gitignored; contents not printed)
- DNS A-record count: 2 distinct IPv4 A records (values redacted)
- Endpoint reachability: endpoint 1 and endpoint 2 both accepted isolated OpenVPN client connections and passed route, DNS, HTTPS, literal-IP HTTPS, and ICMP checks. See `profile-endpoint1.out` and `profile-endpoint2.out`.
