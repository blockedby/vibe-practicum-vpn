#!/usr/bin/env bash
set -euo pipefail

SSH_HOST="${SSH_HOST:-vibe-practicum}"
OPENVPN_PORT="${OPENVPN_PORT:-1194}"
OPENVPN_DEV="${OPENVPN_DEV:-tun-asus}"
OPENVPN_VPN_CIDR="${OPENVPN_VPN_CIDR:-10.89.0.0/24}"
OPENVPN_ASUS_LAN_CIDR="${OPENVPN_ASUS_LAN_CIDR:-192.168.50.0/24}"
TABLE="${TABLE:-100}"
COMMENT_PREFIX="vibe-vpn-openvpn-asus:"

shell_quote() {
  printf "%q" "$1"
}

ssh "$SSH_HOST" \
  "OPENVPN_PORT=$(shell_quote "$OPENVPN_PORT") OPENVPN_DEV=$(shell_quote "$OPENVPN_DEV") OPENVPN_VPN_CIDR=$(shell_quote "$OPENVPN_VPN_CIDR") OPENVPN_ASUS_LAN_CIDR=$(shell_quote "$OPENVPN_ASUS_LAN_CIDR") TABLE=$(shell_quote "$TABLE") COMMENT_PREFIX=$(shell_quote "$COMMENT_PREFIX") bash -s" <<'REMOTE'
set -euo pipefail

sudo_read() {
  if sudo -n true 2>/dev/null; then
    sudo -n "$@" 2>&1 || true
  else
    echo "skip: passwordless sudo unavailable for: $*"
  fi
}

echo "=== host/date ==="
hostname 2>&1 || true
date -Is 2>&1 || true

echo "=== service status ==="
for svc in tailscaled xray sing-box-vibe-router openvpn-server@vibe-asus; do
  printf '%-32s ' "$svc"
  systemctl is-active "$svc" 2>&1 || true
done

echo "=== UDP listener :$OPENVPN_PORT ==="
ss -lunp 2>/dev/null | grep -E "(^|[[:space:]])[^[:space:]]*:${OPENVPN_PORT}[[:space:]]" || true

echo "=== interface $OPENVPN_DEV ==="
ip -o link show "$OPENVPN_DEV" 2>&1 || true
ip -o addr show dev "$OPENVPN_DEV" 2>&1 || true

echo "=== routes for $OPENVPN_VPN_CIDR and $OPENVPN_ASUS_LAN_CIDR ==="
ip route show "$OPENVPN_VPN_CIDR" 2>&1 || true
ip route show "$OPENVPN_ASUS_LAN_CIDR" 2>&1 || true

echo "=== policy routing table $TABLE ==="
ip rule show 2>&1 | grep -E "fwmark|lookup ${TABLE}|table ${TABLE}" || true
ip route show table "$TABLE" 2>&1 || true

echo "=== OpenVPN ASUS iptables comments (sudo -n read only) ==="
if sudo -n true 2>/dev/null; then
  sudo -n iptables-save -t mangle 2>&1 | grep -F "$COMMENT_PREFIX" || true
else
  echo "skip: passwordless sudo unavailable for: iptables-save -t mangle"
fi

echo "=== OpenVPN unit summaries (sudo -n read only) ==="
sudo_read systemctl --no-pager --full status openvpn-server@vibe-asus.service vibe-openvpn-asus-routing.service

echo "=== note ==="
echo "No certificates, private keys, tls-auth keys, or .ovpn profile contents are printed by this script."
REMOTE
