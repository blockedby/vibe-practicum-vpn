#!/usr/bin/env bash
set -euo pipefail

SSH_HOST="${SSH_HOST:-vibe-practicum}"
OPENVPN_ASUS_APPLY="${OPENVPN_ASUS_APPLY:-0}"
OPENVPN_PORT="${OPENVPN_PORT:-1194}"
OPENVPN_DEV="${OPENVPN_DEV:-tun-asus}"
OPENVPN_VPN_CIDR="${OPENVPN_VPN_CIDR:-10.89.0.0/24}"
OPENVPN_ASUS_LAN_CIDR="${OPENVPN_ASUS_LAN_CIDR:-192.168.50.0/24}"
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
  local names=(OPENVPN_PORT OPENVPN_DEV OPENVPN_VPN_CIDR OPENVPN_ASUS_LAN_CIDR TPROXY_PORT MARK TABLE VIBE_PRACTICUM_SUDO_PASSWORD)
  local name
  for name in "${names[@]}"; do
    printf "%s=%s " "$name" "$(shell_quote "${!name:-}")"
  done
}

print_plan() {
  cat <<PLAN
OpenVPN ASUS rollback plan (dry run)

No remote command has been executed. Set OPENVPN_ASUS_APPLY=1 and
VIBE_PRACTICUM_SUDO_PASSWORD to apply this rollback to SSH_HOST=$SSH_HOST.

Rollback will remove only ASUS OpenVPN-owned services, files, and exact/comment-scoped rules:
  - stop/disable vibe-openvpn-asus-routing.service
  - stop/disable openvpn-server@vibe-asus.service
  - delete UFW allow for $OPENVPN_PORT/udp when UFW is active
  - delete exact PREROUTING jump:
      -i $OPENVPN_DEV -s $OPENVPN_VPN_CIDR -m comment --comment ${COMMENT_PREFIX}entry:vpn-pool -j VIBE_ROUTER_OPENVPN_ASUS
  - delete exact PREROUTING jump:
      -i $OPENVPN_DEV -s $OPENVPN_ASUS_LAN_CIDR -m comment --comment ${COMMENT_PREFIX}entry:asus-lan -j VIBE_ROUTER_OPENVPN_ASUS
  - delete only expected VIBE_ROUTER_OPENVPN_ASUS rules whose comments start with $COMMENT_PREFIX
  - delete VIBE_ROUTER_OPENVPN_ASUS only after it is empty
  - move these paths into /var/backups/vibe-vpn/openvpn-asus/<timestamp>/ instead of printing/deleting secrets:
      /etc/openvpn/server/vibe-asus.conf
      /etc/openvpn/ccd-vibe-asus
      /etc/sysctl.d/99-vibe-openvpn-asus.conf
      /etc/systemd/system/vibe-openvpn-asus-routing.service
      /usr/local/sbin/vibe-openvpn-asus-rules
      /etc/vibe-vpn/openvpn-asus

Safety invariants:
  - Does not delete shared fwmark $MARK / table $TABLE policy routing.
  - Does not force net.ipv4.ip_forward back to 0 because forwarding may be shared.
  - Does not change the VPS default route.
  - Does not run iptables -F, iptables-restore, or flush broad chains.
  - Does not touch VIBE_ROUTER_PIXEL, tailscaled, xray, or sing-box-vibe-router.
  - Does not print certificate, key, tls-auth, or profile contents.
PLAN
}

apply_remote() {
  {
    remote_env
    printf '\n'
    cat <<'REMOTE'
set -euo pipefail

CHAIN="VIBE_ROUTER_OPENVPN_ASUS"
COMMENT_PREFIX="vibe-vpn-openvpn-asus:"
BACKUP_ROOT="/var/backups/vibe-vpn/openvpn-asus"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="$BACKUP_ROOT/$STAMP"

sudo_cmd() {
  printf '%s\n' "$VIBE_PRACTICUM_SUDO_PASSWORD" | sudo -S -p '' "$@"
}

delete_rule_while_present() {
  if sudo_cmd iptables -t mangle -C "$@" 2>/dev/null; then
    while sudo_cmd iptables -t mangle -C "$@" 2>/dev/null; do
      sudo_cmd iptables -t mangle -D "$@"
      echo "deleted mangle rule: $*"
    done
  fi
}

backup_path() {
  local src="$1" label="$2"
  if sudo_cmd test -e "$src"; then
    sudo_cmd install -d -o root -g root -m 700 "$BACKUP_DIR"
    sudo_cmd mv "$src" "$BACKUP_DIR/$label"
    echo "moved $src -> $BACKUP_DIR/$label"
  else
    echo "absent: $src"
  fi
}

echo "stopping ASUS OpenVPN-owned services"
sudo_cmd systemctl disable --now vibe-openvpn-asus-routing.service 2>/dev/null || true
sudo_cmd systemctl disable --now openvpn-server@vibe-asus.service 2>/dev/null || true

if command -v ufw >/dev/null 2>&1 && sudo_cmd ufw status 2>/dev/null | grep -q '^Status: active'; then
  sudo_cmd ufw delete allow "$OPENVPN_PORT/udp" >/dev/null 2>&1 || true
fi

echo "removing exact PREROUTING entries"
delete_rule_while_present PREROUTING -i "$OPENVPN_DEV" -s "$OPENVPN_VPN_CIDR" -m comment --comment "${COMMENT_PREFIX}entry:vpn-pool" -j "$CHAIN"
delete_rule_while_present PREROUTING -i "$OPENVPN_DEV" -s "$OPENVPN_ASUS_LAN_CIDR" -m comment --comment "${COMMENT_PREFIX}entry:asus-lan" -j "$CHAIN"

if sudo_cmd iptables -t mangle -S "$CHAIN" >/dev/null 2>&1; then
  echo "removing expected $CHAIN rules with $COMMENT_PREFIX comments"
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
    delete_rule_while_present "$CHAIN" -d "$cidr" -m comment --comment "${COMMENT_PREFIX}bypass:${cidr}" -j RETURN
  done
  delete_rule_while_present "$CHAIN" -p tcp -m comment --comment "${COMMENT_PREFIX}tproxy:tcp" -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK/$MARK"
  delete_rule_while_present "$CHAIN" -p udp -m comment --comment "${COMMENT_PREFIX}tproxy:udp" -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK/$MARK"

  if sudo_cmd iptables -t mangle -S "$CHAIN" | grep -q '^-A '; then
    echo "not deleting $CHAIN because non-ASUS or unexpected rules remain"
  else
    sudo_cmd iptables -t mangle -X "$CHAIN" 2>/dev/null || true
    echo "deleted empty chain $CHAIN"
  fi
else
  echo "absent: mangle chain $CHAIN"
fi

echo "backing up ASUS OpenVPN-owned files/directories without printing secrets"
backup_path /etc/openvpn/server/vibe-asus.conf vibe-asus.conf
backup_path /etc/openvpn/ccd-vibe-asus ccd-vibe-asus
backup_path /etc/sysctl.d/99-vibe-openvpn-asus.conf 99-vibe-openvpn-asus.conf
backup_path /etc/systemd/system/vibe-openvpn-asus-routing.service vibe-openvpn-asus-routing.service
backup_path /usr/local/sbin/vibe-openvpn-asus-rules vibe-openvpn-asus-rules
backup_path /etc/vibe-vpn/openvpn-asus state

sudo_cmd systemctl daemon-reload

echo "rollback complete; backup_dir=$BACKUP_DIR"
echo "shared policy routing preserved: fwmark $MARK table $TABLE"
sudo_cmd iptables -t mangle -S PREROUTING | grep "$COMMENT_PREFIX" || true
sudo_cmd iptables -t mangle -S "$CHAIN" 2>/dev/null || true
ip rule show | grep "fwmark $MARK" || true
ip route show table "$TABLE" || true
REMOTE
  } | ssh "$SSH_HOST" bash -s
}

require_apply_password
if [[ "$OPENVPN_ASUS_APPLY" != "1" ]]; then
  print_plan
  exit 0
fi

apply_remote
