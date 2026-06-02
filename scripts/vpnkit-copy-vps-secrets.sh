#!/usr/bin/env bash
set -euo pipefail
HOST=${1:-${VPNKIT_VPS_SSH_HOST:-example-vps-host}}
BASE=${VPNKIT_SECRETS_DIR:-secrets/vps}
mkdir -p "$BASE/sing-box" "$BASE/openvpn/server" "$BASE/openvpn/pki" "$BASE/openvpn/client"
cat <<MSG
This operator-bound helper copies real VPS material into gitignored $BASE.
It uses sudo rsync on $HOST and does not commit or print secrets.
MSG
rsync -av --rsync-path='sudo rsync' "$HOST:/etc/sing-box-vibe/tproxy-canary.json" "$BASE/sing-box/tproxy-canary.json"
rsync -av --rsync-path='sudo rsync' "$HOST:/etc/openvpn/server/vibe-asus.conf" "$BASE/openvpn/server/vibe-asus.conf"
rsync -av --rsync-path='sudo rsync' \
  "$HOST:/etc/vibe-vpn/openvpn-asus/ca.crt" \
  "$HOST:/etc/vibe-vpn/openvpn-asus/ta.key" \
  "$HOST:/etc/vibe-vpn/openvpn-asus/vibe-asus.crt" \
  "$HOST:/etc/vibe-vpn/openvpn-asus/vibe-asus.key" \
  "$HOST:/etc/vibe-vpn/openvpn-asus/ignat.crt" \
  "$HOST:/etc/vibe-vpn/openvpn-asus/ignat.key" \
  "$BASE/openvpn/pki/"
rsync -av --rsync-path='sudo rsync' "$HOST:/etc/openvpn/ccd-vibe-asus/ignat" "$BASE/openvpn/server/ccd-ignat"
