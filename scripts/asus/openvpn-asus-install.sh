#!/usr/bin/env bash
set -euo pipefail

SSH_HOST="${SSH_HOST:-${VPNKIT_VPS_SSH_HOST:-example-vps-host}}"
OPENVPN_ASUS_APPLY="${OPENVPN_ASUS_APPLY:-0}"
OPENVPN_PORT="${OPENVPN_PORT:-1194}"
OPENVPN_DEV="${OPENVPN_DEV:-tun-asus}"
OPENVPN_VPN_CIDR="${OPENVPN_VPN_CIDR:-10.89.0.0/24}"
OPENVPN_VPN_NET="${OPENVPN_VPN_NET:-10.89.0.0}"
OPENVPN_VPN_MASK="${OPENVPN_VPN_MASK:-255.255.255.0}"
OPENVPN_VPN_GATEWAY="${OPENVPN_VPN_GATEWAY:-10.89.0.1}"
OPENVPN_ASUS_VPN_IP="${OPENVPN_ASUS_VPN_IP:-10.89.0.2}"
OPENVPN_CLIENT_POOL_START="${OPENVPN_CLIENT_POOL_START:-10.89.0.20}"
OPENVPN_CLIENT_POOL_END="${OPENVPN_CLIENT_POOL_END:-10.89.0.254}"
OPENVPN_DIRECT_CLIENT_CN="${OPENVPN_DIRECT_CLIENT_CN:-direct-client-1}"
OPENVPN_ASUS_LAN_CIDR="${OPENVPN_ASUS_LAN_CIDR:-192.0.2.0/24}"
TPROXY_PORT="${TPROXY_PORT:-2082}"
MARK="${MARK:-0x1}"
TABLE="${TABLE:-100}"
COMMENT_PREFIX="vibe-vpn-openvpn-asus:"

require_apply_password() {
  if [[ "$OPENVPN_ASUS_APPLY" == "1" && -z "${VIBE_PRACTICUM_SUDO_PASSWORD:-}" ]]; then
    echo "Set VIBE_PRACTICUM_SUDO_PASSWORD when OPENVPN_ASUS_APPLY=1" >&2
    exit 1
  fi
}

shell_quote() {
  printf "%q" "$1"
}

remote_env() {
  local names=(
    OPENVPN_PORT OPENVPN_DEV OPENVPN_VPN_CIDR OPENVPN_VPN_NET OPENVPN_VPN_MASK
    OPENVPN_VPN_GATEWAY OPENVPN_ASUS_VPN_IP OPENVPN_CLIENT_POOL_START OPENVPN_CLIENT_POOL_END
    OPENVPN_DIRECT_CLIENT_CN OPENVPN_ASUS_LAN_CIDR TPROXY_PORT MARK TABLE
    VIBE_PRACTICUM_SUDO_PASSWORD
  )
  local name
  for name in "${names[@]}"; do
    printf "%s=%s " "$name" "$(shell_quote "${!name:-}")"
  done
}

print_plan() {
  cat <<PLAN
OpenVPN ASUS site-to-site install plan (dry run)

No remote command has been executed. Set OPENVPN_ASUS_APPLY=1 and
VIBE_PRACTICUM_SUDO_PASSWORD to apply this plan to SSH_HOST=$SSH_HOST.

Defaults / selected values:
  SSH_HOST=$SSH_HOST
  OPENVPN_PORT=$OPENVPN_PORT/udp
  OPENVPN_DEV=$OPENVPN_DEV
  OPENVPN_VPN_CIDR=$OPENVPN_VPN_CIDR
  OPENVPN_VPN_NET=$OPENVPN_VPN_NET
  OPENVPN_VPN_MASK=$OPENVPN_VPN_MASK
  OPENVPN_VPN_GATEWAY=$OPENVPN_VPN_GATEWAY
  OPENVPN_ASUS_VPN_IP=$OPENVPN_ASUS_VPN_IP
  OPENVPN_CLIENT_POOL_START=$OPENVPN_CLIENT_POOL_START
  OPENVPN_CLIENT_POOL_END=$OPENVPN_CLIENT_POOL_END
  OPENVPN_DIRECT_CLIENT_CN=$OPENVPN_DIRECT_CLIENT_CN
  OPENVPN_ASUS_LAN_CIDR=$OPENVPN_ASUS_LAN_CIDR
  TPROXY_PORT=$TPROXY_PORT
  MARK=$MARK
  TABLE=$TABLE
  iptables comment prefix=$COMMENT_PREFIX

Remote apply will:
  1. Check status of tailscaled, xray, sing-box-vibe-router, and OpenVPN units.
  2. Install packages only if missing: openvpn and easy-rsa.
  3. Create root-only state directory /etc/vibe-vpn/openvpn-asus (0700).
  4. Initialize Easy-RSA PKI only if /etc/vibe-vpn/openvpn-asus/easy-rsa/pki is absent.
  5. Generate/export only the needed client materials under /etc/vibe-vpn/openvpn-asus:
       ca.crt, asus.crt, asus.key, $OPENVPN_DIRECT_CLIENT_CN.crt, $OPENVPN_DIRECT_CLIENT_CN.key, ta.key
     Secret material is never printed.
  6. Render /etc/sysctl.d/99-vibe-openvpn-asus.conf and ensure net.ipv4.ip_forward=1.
  7. Render /etc/openvpn/server/vibe-asus.conf for UDP $OPENVPN_PORT on $OPENVPN_DEV.
  8. Render readable /etc/openvpn/ccd-vibe-asus/asus with:
       ifconfig-push $OPENVPN_ASUS_VPN_IP $OPENVPN_VPN_MASK
       iroute $OPENVPN_ASUS_LAN_CIDR
     Render /etc/openvpn/ccd-vibe-asus/$OPENVPN_DIRECT_CLIENT_CN with a pushed
     route to $OPENVPN_ASUS_LAN_CIDR, without pushing that route back to ASUS.
  9. Allow UDP $OPENVPN_PORT in UFW when UFW is active.
 10. Install /usr/local/sbin/vibe-openvpn-asus-rules and
     /etc/systemd/system/vibe-openvpn-asus-routing.service.
 11. Ensure shared TProxy policy routing exists, without deleting it:
       ip rule add fwmark $MARK table $TABLE      # only if missing
       ip route add local 0.0.0.0/0 dev lo table $TABLE  # only if missing
 12. Create/reuse mangle chain VIBE_ROUTER_OPENVPN_ASUS.
 13. Add exact, comment-scoped bypass and TPROXY rules in that chain.
 14. Attach only these PREROUTING entries if missing:
       -i $OPENVPN_DEV -s $OPENVPN_VPN_CIDR -m comment --comment ${COMMENT_PREFIX}entry:vpn-pool -j VIBE_ROUTER_OPENVPN_ASUS
       -i $OPENVPN_DEV -s $OPENVPN_ASUS_LAN_CIDR -m comment --comment ${COMMENT_PREFIX}entry:asus-lan -j VIBE_ROUTER_OPENVPN_ASUS
 14. Enable/start vibe-openvpn-asus-routing.service and openvpn-server@vibe-asus.service.

Safety invariants:
  - Does not change the VPS default route.
  - Does not run iptables -F, iptables-restore, or flush broad chains.
  - Does not modify VIBE_ROUTER_PIXEL or Tailscale rules.
  - Does not stop/restart tailscaled, xray, or sing-box-vibe-router.
  - Does not print certificates, keys, tls-auth keys, or generated profiles.
PLAN
}

apply_remote() {
  {
    remote_env
    printf '\n'
    cat <<'REMOTE'
set -euo pipefail

STATE_DIR="/etc/vibe-vpn/openvpn-asus"
EASYRSA_DIR="$STATE_DIR/easy-rsa"
OPENVPN_SERVER_DIR="/etc/openvpn/server"
CCD_DIR="/etc/openvpn/ccd-vibe-asus"
SERVER_CONF="$OPENVPN_SERVER_DIR/vibe-asus.conf"
CCD_FILE="$CCD_DIR/asus"
SYSCTL_CONF="/etc/sysctl.d/99-vibe-openvpn-asus.conf"
HELPER="/usr/local/sbin/vibe-openvpn-asus-rules"
UNIT="/etc/systemd/system/vibe-openvpn-asus-routing.service"
CHAIN="VIBE_ROUTER_OPENVPN_ASUS"
COMMENT_PREFIX="vibe-vpn-openvpn-asus:"

sudo_cmd() {
  printf '%s\n' "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S -p '' "$@"
}
sudo_test_dir() {
  sudo_cmd test -d "$1"
}
sudo_test_file() {
  sudo_cmd test -f "$1"
}
install_root_file() {
  local src="$1" dst="$2" mode="$3"
  sudo_cmd install -o root -g root -m "$mode" "$src" "$dst"
}
require_bin() {
  command -v "$1" >/dev/null 2>&1
}

cidr_to_netmask() {
  python3 - "$1" <<'PY'
import ipaddress, sys
net = ipaddress.ip_network(sys.argv[1], strict=False)
print(str(net.network_address), str(net.netmask))
PY
}

read -r ASUS_LAN_NET ASUS_LAN_MASK < <(cidr_to_netmask "$OPENVPN_ASUS_LAN_CIDR")

if [[ ! "$OPENVPN_DIRECT_CLIENT_CN" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "OPENVPN_DIRECT_CLIENT_CN must contain only letters, numbers, dot, underscore, or dash" >&2
  exit 1
fi
if [[ "$OPENVPN_DIRECT_CLIENT_CN" == "asus" ]]; then
  echo "OPENVPN_DIRECT_CLIENT_CN must differ from reserved ASUS CN 'asus'" >&2
  exit 1
fi

echo "=== preflight service status (read-only) ==="
for svc in tailscaled xray sing-box-vibe-router openvpn-server@vibe-asus; do
  printf '%-32s ' "$svc"
  systemctl is-active "$svc" 2>&1 || true
done

if ! require_bin openvpn || [[ ! -x /usr/share/easy-rsa/easyrsa ]]; then
  echo "installing missing packages: openvpn easy-rsa"
  sudo_cmd apt-get update
  printf '%s\n' "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S -p '' env DEBIAN_FRONTEND=noninteractive apt-get install -y openvpn easy-rsa
else
  echo "openvpn and easy-rsa already installed"
fi

sudo_cmd install -d -o root -g root -m 700 "$STATE_DIR"
sudo_cmd install -d -o root -g root -m 755 "$OPENVPN_SERVER_DIR" "$CCD_DIR" /var/log/openvpn
sudo_cmd install -d -o root -g root -m 750 /var/lib/openvpn

if ! sudo_test_dir "$EASYRSA_DIR/pki"; then
  echo "initializing Easy-RSA PKI under $EASYRSA_DIR"
  tmpdir="$(mktemp -d)"
  cp -a /usr/share/easy-rsa/. "$tmpdir/"
  sudo_cmd install -d -o root -g root -m 700 "$EASYRSA_DIR"
  sudo_cmd cp -a "$tmpdir/." "$EASYRSA_DIR/"
  rm -rf "$tmpdir"
  sudo_cmd chown -R root:root "$EASYRSA_DIR"
  sudo_cmd chmod 700 "$EASYRSA_DIR"
  sudo_cmd bash -c "cd '$EASYRSA_DIR' && ./easyrsa --batch init-pki"
  sudo_cmd bash -c "cd '$EASYRSA_DIR' && EASYRSA_BATCH=1 EASYRSA_REQ_CN='vibe-openvpn-asus-ca' ./easyrsa build-ca nopass"
  sudo_cmd bash -c "cd '$EASYRSA_DIR' && EASYRSA_BATCH=1 ./easyrsa build-server-full vibe-asus nopass"
  sudo_cmd bash -c "cd '$EASYRSA_DIR' && EASYRSA_BATCH=1 ./easyrsa build-client-full asus nopass"
  sudo_cmd bash -c "cd '$EASYRSA_DIR' && EASYRSA_BATCH=1 ./easyrsa build-client-full '$OPENVPN_DIRECT_CLIENT_CN' nopass"
else
  echo "Easy-RSA PKI already exists; not regenerating CA or existing client keys"
fi

if ! sudo_test_file "$EASYRSA_DIR/pki/issued/asus.crt" || ! sudo_test_file "$EASYRSA_DIR/pki/private/asus.key"; then
  sudo_cmd bash -c "cd '$EASYRSA_DIR' && EASYRSA_BATCH=1 ./easyrsa build-client-full asus nopass"
fi
if ! sudo_test_file "$EASYRSA_DIR/pki/issued/$OPENVPN_DIRECT_CLIENT_CN.crt" || ! sudo_test_file "$EASYRSA_DIR/pki/private/$OPENVPN_DIRECT_CLIENT_CN.key"; then
  sudo_cmd bash -c "cd '$EASYRSA_DIR' && EASYRSA_BATCH=1 ./easyrsa build-client-full '$OPENVPN_DIRECT_CLIENT_CN' nopass"
fi

if ! sudo_test_file "$STATE_DIR/ta.key"; then
  tmp_ta="$(mktemp)"
  openvpn --genkey secret "$tmp_ta"
  install_root_file "$tmp_ta" "$STATE_DIR/ta.key" 600
  rm -f "$tmp_ta"
fi

sudo_cmd install -o root -g root -m 644 "$EASYRSA_DIR/pki/ca.crt" "$STATE_DIR/ca.crt"
sudo_cmd install -o root -g root -m 644 "$EASYRSA_DIR/pki/issued/vibe-asus.crt" "$STATE_DIR/vibe-asus.crt"
sudo_cmd install -o root -g root -m 600 "$EASYRSA_DIR/pki/private/vibe-asus.key" "$STATE_DIR/vibe-asus.key"
sudo_cmd install -o root -g root -m 644 "$EASYRSA_DIR/pki/issued/asus.crt" "$STATE_DIR/asus.crt"
sudo_cmd install -o root -g root -m 600 "$EASYRSA_DIR/pki/private/asus.key" "$STATE_DIR/asus.key"
sudo_cmd install -o root -g root -m 644 "$EASYRSA_DIR/pki/issued/$OPENVPN_DIRECT_CLIENT_CN.crt" "$STATE_DIR/$OPENVPN_DIRECT_CLIENT_CN.crt"
sudo_cmd install -o root -g root -m 600 "$EASYRSA_DIR/pki/private/$OPENVPN_DIRECT_CLIENT_CN.key" "$STATE_DIR/$OPENVPN_DIRECT_CLIENT_CN.key"
sudo_cmd chmod 700 "$STATE_DIR"

tmp_sysctl="$(mktemp)"
cat >"$tmp_sysctl" <<SYSCTL
# Managed by vibe-vpn-openvpn-asus. Enables forwarding between tun-asus and local TProxy path.
net.ipv4.ip_forward=1
SYSCTL
install_root_file "$tmp_sysctl" "$SYSCTL_CONF" 644
rm -f "$tmp_sysctl"
sudo_cmd sysctl -w net.ipv4.ip_forward=1 >/dev/null

if command -v ufw >/dev/null 2>&1 && sudo_cmd ufw status 2>/dev/null | grep -q '^Status: active'; then
  sudo_cmd ufw allow "$OPENVPN_PORT/udp" comment 'vibe-vpn openvpn asus' >/dev/null || true
fi

tmp_conf="$(mktemp)"
cat >"$tmp_conf" <<CONF
port $OPENVPN_PORT
proto udp
dev $OPENVPN_DEV
mode server
tls-server
topology subnet
ifconfig $OPENVPN_VPN_GATEWAY $OPENVPN_VPN_MASK
ifconfig-pool $OPENVPN_CLIENT_POOL_START $OPENVPN_CLIENT_POOL_END $OPENVPN_VPN_MASK
push "topology subnet"
push "route-gateway $OPENVPN_VPN_GATEWAY"
ifconfig-pool-persist /var/lib/openvpn/vibe-asus-ipp.txt
client-config-dir $CCD_DIR
client-to-client
route $ASUS_LAN_NET $ASUS_LAN_MASK $OPENVPN_ASUS_VPN_IP
keepalive 10 120
persist-key
persist-tun
user nobody
group nogroup
ca $STATE_DIR/ca.crt
cert $STATE_DIR/vibe-asus.crt
key $STATE_DIR/vibe-asus.key
dh none
tls-auth $STATE_DIR/ta.key 0
key-direction 0
remote-cert-tls client
auth SHA256
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-256-CBC
data-ciphers-fallback AES-256-CBC
cipher AES-256-GCM
status /var/log/openvpn/vibe-asus-status.log
verb 3
explicit-exit-notify 1
CONF
install_root_file "$tmp_conf" "$SERVER_CONF" 600
rm -f "$tmp_conf"

tmp_ccd="$(mktemp)"
cat >"$tmp_ccd" <<CCD
ifconfig-push $OPENVPN_ASUS_VPN_IP $OPENVPN_VPN_MASK
iroute $ASUS_LAN_NET $ASUS_LAN_MASK
CCD
install_root_file "$tmp_ccd" "$CCD_FILE" 644
rm -f "$tmp_ccd"

DIRECT_CLIENT_CCD="$CCD_DIR/$OPENVPN_DIRECT_CLIENT_CN"
tmp_direct_ccd="$(mktemp)"
cat >"$tmp_direct_ccd" <<CCD
push "route $ASUS_LAN_NET $ASUS_LAN_MASK"
CCD
install_root_file "$tmp_direct_ccd" "$DIRECT_CLIENT_CCD" 644
rm -f "$tmp_direct_ccd"

tmp_helper="$(mktemp)"
cat >"$tmp_helper" <<'HELPER'
#!/usr/bin/env bash
set -euo pipefail

OPENVPN_DEV="${OPENVPN_DEV:-tun-asus}"
OPENVPN_VPN_CIDR="${OPENVPN_VPN_CIDR:-10.89.0.0/24}"
OPENVPN_ASUS_LAN_CIDR="${OPENVPN_ASUS_LAN_CIDR:-192.0.2.0/24}"
TPROXY_PORT="${TPROXY_PORT:-2082}"
MARK="${MARK:-0x1}"
TABLE="${TABLE:-100}"
CHAIN="VIBE_ROUTER_OPENVPN_ASUS"
COMMENT_PREFIX="vibe-vpn-openvpn-asus:"

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi

ensure_rule() {
  if ! iptables -t mangle -C "$@" 2>/dev/null; then
    iptables -t mangle -A "$@"
  fi
}
ensure_prerouting() {
  if ! iptables -t mangle -C PREROUTING "$@" 2>/dev/null; then
    iptables -t mangle -A PREROUTING "$@"
  fi
}

if ! ip rule show | grep -Eq "fwmark ${MARK}(/${MARK})?.*(lookup|table) ${TABLE}(\\b|$)"; then
  ip rule add fwmark "$MARK" table "$TABLE"
fi
if ! ip route show table "$TABLE" | grep -Eq '^local (default|0\.0\.0\.0/0)'; then
  ip route add local 0.0.0.0/0 dev lo table "$TABLE"
fi

iptables -t mangle -N "$CHAIN" 2>/dev/null || true

for cidr in \
  0.0.0.0/8 \
  10.0.0.0/8 \
  100.64.0.0/10 \
  127.0.0.0/8 \
  169.254.0.0/16 \
  172.16.0.0/12 \
  192.168.0.0/16 \
  224.0.0.0/4 \
  240.0.0.0/4; do
  ensure_rule "$CHAIN" -d "$cidr" -m comment --comment "${COMMENT_PREFIX}bypass:${cidr}" -j RETURN
done

ensure_rule "$CHAIN" -p tcp -m comment --comment "${COMMENT_PREFIX}tproxy:tcp" -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK/$MARK"
ensure_rule "$CHAIN" -p udp -m comment --comment "${COMMENT_PREFIX}tproxy:udp" -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK/$MARK"

ensure_prerouting -i "$OPENVPN_DEV" -s "$OPENVPN_VPN_CIDR" -m comment --comment "${COMMENT_PREFIX}entry:vpn-pool" -j "$CHAIN"
ensure_prerouting -i "$OPENVPN_DEV" -s "$OPENVPN_ASUS_LAN_CIDR" -m comment --comment "${COMMENT_PREFIX}entry:asus-lan" -j "$CHAIN"

iptables -t mangle -S PREROUTING | grep "$COMMENT_PREFIX" || true
iptables -t mangle -S "$CHAIN" | sed -n '1,120p'
ip rule show | grep "fwmark $MARK" || true
ip route show table "$TABLE" || true
HELPER
install_root_file "$tmp_helper" "$HELPER" 755
rm -f "$tmp_helper"

tmp_unit="$(mktemp)"
cat >"$tmp_unit" <<UNIT
[Unit]
Description=Vibe OpenVPN ASUS TProxy routing rules
Documentation=file:/etc/openvpn/server/vibe-asus.conf
After=network-online.target openvpn-server@vibe-asus.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=OPENVPN_DEV=$OPENVPN_DEV
Environment=OPENVPN_VPN_CIDR=$OPENVPN_VPN_CIDR
Environment=OPENVPN_ASUS_LAN_CIDR=$OPENVPN_ASUS_LAN_CIDR
Environment=TPROXY_PORT=$TPROXY_PORT
Environment=MARK=$MARK
Environment=TABLE=$TABLE
ExecStart=$HELPER

[Install]
WantedBy=multi-user.target
UNIT
install_root_file "$tmp_unit" "$UNIT" 644
rm -f "$tmp_unit"

sudo_cmd systemctl daemon-reload
sudo_cmd systemctl enable vibe-openvpn-asus-routing.service openvpn-server@vibe-asus.service
sudo_cmd systemctl restart vibe-openvpn-asus-routing.service
sudo_cmd systemctl restart openvpn-server@vibe-asus.service

echo "=== installed OpenVPN ASUS artifacts ==="
echo "server_conf=$SERVER_CONF"
echo "ccd_file=$CCD_FILE"
echo "sysctl_conf=$SYSCTL_CONF"
echo "state_dir=$STATE_DIR (secret material not printed)"
echo "routing_helper=$HELPER"
echo "routing_unit=$UNIT"
sudo_cmd systemctl --no-pager --full status vibe-openvpn-asus-routing.service openvpn-server@vibe-asus.service || true
REMOTE
  } | ssh "$SSH_HOST" bash -s
}

require_apply_password
if [[ "$OPENVPN_ASUS_APPLY" != "1" ]]; then
  print_plan
  exit 0
fi

apply_remote
