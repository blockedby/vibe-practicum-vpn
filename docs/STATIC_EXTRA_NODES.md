# Static extra nodes for `vibe-vpn`

Date: 2026-05-09

`vibe-vpn` normally fetches VLESS nodes from `/etc/vibe-vpn/sub_url`. It can also
append operator-managed static nodes from:

```text
/etc/vibe-vpn/extra-nodes.json
```

The file is optional. If it is missing, `vibe-vpn` behaves as before.

## Security

Treat `/etc/vibe-vpn/extra-nodes.json` as root-only. Do not commit it if it
contains auth material or references local secret files.

Recommended modes:

```bash
sudo install -d -o root -g root -m 700 /etc/vibe-vpn
sudo chmod 600 /etc/vibe-vpn/extra-nodes.json
sudo chmod 600 /etc/vibe-vpn/*-auth
```

## Hysteria2 node format

Example for `lil-sweden`:

```json
[
  {
    "name": "lil-sweden hysteria2",
    "type": "hysteria2",
    "host": "computer.peacedata.company",
    "port": 18443,
    "auth_file": "/etc/vibe-vpn/lil-sweden-hy2-auth",
    "server_name": "computer.peacedata.company",
    "alpn": ["h3"],
    "brutal_mbps": 200
  }
]
```

This renders an Xray outbound equivalent to:

```json
{
  "protocol": "hysteria",
  "settings": {
    "version": 2,
    "address": "computer.peacedata.company",
    "port": 18443
  },
  "streamSettings": {
    "network": "hysteria",
    "security": "tls",
    "tlsSettings": {
      "serverName": "computer.peacedata.company",
      "alpn": ["h3"]
    },
    "hysteriaSettings": {
      "version": 2,
      "auth": "..."
    },
    "finalmask": {
      "quicParams": {
        "congestion": "force-brutal",
        "brutalUp": "200 mbps",
        "brutalDown": "200 mbps"
      }
    }
  }
}
```

## Commands

Extra nodes are included in normal commands:

```bash
sudo vibe-vpn refresh
sudo vibe-vpn test --include lil-sweden --duration-sec 5
sudo vibe-vpn list --all
```

Do not run `pick`/`apply` unless you intend to change production Xray.
