port 1194
proto udp
dev tun0
topology subnet
server 10.89.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 10.89.0.1"
keepalive 10 120
persist-key
persist-tun
verb 3
ca /etc/openvpn/pki/ca.crt
cert /etc/openvpn/pki/vibe-asus.crt
key /etc/openvpn/pki/vibe-asus.key
tls-crypt /etc/openvpn/pki/ta.key
client-config-dir /etc/openvpn/ccd
