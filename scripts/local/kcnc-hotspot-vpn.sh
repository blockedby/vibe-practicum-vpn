#!/usr/bin/env bash
set -euo pipefail

# Route this PC's NetworkManager hotspot clients through the existing sing-box/VPN TUN
# while allowing selected VPN-handshake destinations to bypass the hotspot VPN path.
#
# Usage:
#   sudo scripts/local/kcnc-hotspot-vpn.sh up
#   sudo scripts/local/kcnc-hotspot-vpn.sh status
#   sudo scripts/local/kcnc-hotspot-vpn.sh down
#
# Optional env:
#   OVPN_PROFILE_PATH      path to .ovpn file (optional)
#   OVPN_BYPASS_IPS        comma/space separated list (e.g. "203.0.113.10/32,198.51.100.0/24")
#   RULE_PRIO              ip rule priority for hotspot-table routing (default: 10022)
#   ROUTE_TABLE            policy table for hotspot VPN path (default: 2022)
#   VPN_IF                 outbound interface for hotspot path (default: proxyvpn0)
#   HOTSPOT_IF             hotspot interface (default: wlan0)

HOTSPOT_IF=${HOTSPOT_IF:-wlan0}
VPN_IF=${VPN_IF:-proxyvpn0}
ROUTE_TABLE=${ROUTE_TABLE:-2022}
RULE_PRIO=${RULE_PRIO:-10022}
RULE_PRIO_BYPASS=${RULE_PRIO_BYPASS:-10005}
NFT_TABLE=${NFT_TABLE:-kcnc_hotspot_vpn}
HOTSPOT_SUBNET_WAIT_ATTEMPTS=${HOTSPOT_SUBNET_WAIT_ATTEMPTS:-6}
HOTSPOT_SUBNET_WAIT_DELAY=${HOTSPOT_SUBNET_WAIT_DELAY:-0.5}
# Local defaults (edit directly in this file)
#  - OVPN_PROFILE_PATH: path to your OpenVPN client profile on this PC
#  - OVPN_BYPASS_IPS: CIDRs that must bypass sing-box path
OVPN_BYPASS_IPS='10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,185.241.192.190/32'
#  - HOTSPOT_SUBNET_OVERRIDE: hotspot source subnet (must be CIDR)
#  - SKIP_OVPN_PROFILE_PARSE: set 1 to skip fragile .ovpn parsing

OVPN_PROFILE_PATH=${OVPN_PROFILE_PATH:-"/home/kcnc/Downloads/Telegram Desktop/ezhulina.nix_openvpn.conf"}
OVPN_BYPASS_IPS=${OVPN_BYPASS_IPS:-"10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"}
SKIP_OVPN_PROFILE_PARSE=${SKIP_OVPN_PROFILE_PARSE:-0}
BYPASS_RULE_FILE=${BYPASS_RULE_FILE:-/run/kcnc-hotspot-vpn-bypass.rules}
HOTSPOT_SUBNET_OVERRIDE=${HOTSPOT_SUBNET_OVERRIDE:-}
CLAMP_MSS=${CLAMP_MSS:-1}
ACTION=${1:-up}


need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "error: run as root, e.g. sudo $0 $ACTION" >&2
    exit 1
  fi
}

is_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

is_cidr() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]
}

hotspot_subnet() {
  local subnet

  # preferred explicit override
  if [[ -n "$HOTSPOT_SUBNET_OVERRIDE" ]]; then
    if is_cidr "$HOTSPOT_SUBNET_OVERRIDE"; then
      echo "$HOTSPOT_SUBNET_OVERRIDE"
      return
    fi
    echo "warn: HOTSPOT_SUBNET_OVERRIDE invalid: $HOTSPOT_SUBNET_OVERRIDE" >&2
  fi

  # NM/NetworkManager may not expose as addr on managed APs; query both addr + local link routes
  subnet=$(ip -4 -o addr show dev "$HOTSPOT_IF" 2>/dev/null | awk '/ inet /{print $4; exit}')
  if is_cidr "$subnet"; then
    echo "$subnet"
    return
  fi

  subnet=$(ip -4 route show dev "$HOTSPOT_IF" | awk '/^10\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+/{print $1; exit}')
  if is_cidr "$subnet"; then
    echo "$subnet"
    return
  fi

  subnet=$(ip -4 route show dev "$HOTSPOT_IF" | awk '/ proto kernel /{print $1; exit}')
  if is_cidr "$subnet"; then
    echo "$subnet"
    return
  fi

  echo ""
}

resolve_hotspot_subnet() {
  local subnet
  local attempt=0

  while (( attempt < HOTSPOT_SUBNET_WAIT_ATTEMPTS )); do
    attempt=$((attempt + 1))
    subnet=$(hotspot_subnet)
    if is_cidr "$subnet"; then
      echo "$subnet"
      return 0
    fi
    sleep "$HOTSPOT_SUBNET_WAIT_DELAY"
  done

  echo ""
  return 1
}

main_out_iface() {
  ip route | awk '/^default/{print $5; exit}'
}

collect_bypass_networks() {
  local -n out_arr=$1
  local -A seen=()
  local token host ip mask network cidr
  local -a fields

  out_arr=()

  sanitize_token() {
    local token=$1
    token="${token//\"/}"
    token="${token//\'/}"
    echo "$token"
  }

  # helper to convert dotted netmask to cidr and append network token
  mask_to_cidr() {
    local m=$1
    local -a octets
    local bits=0
    IFS='.' read -r -a octets <<< "$m"
    for oct in "${octets[@]}"; do
      case "$oct" in
        0) ;;
        128) bits=$((bits+1));;
        192) bits=$((bits+2));;
        224) bits=$((bits+3));;
        240) bits=$((bits+4));;
        248) bits=$((bits+5));;
        252) bits=$((bits+6));;
        254) bits=$((bits+7));;
        255) bits=$((bits+8));;
        *) return 1 ;;
      esac
    done
    echo "$bits"
  }

  _add_bypass_token() {
    local net_token=$1
    if ! is_cidr "$net_token"; then
      return
    fi
    if [[ -z "${seen[$net_token]:-}" ]]; then
      out_arr+=("$net_token")
      seen[$net_token]=1
    fi
  }

  # 1) Manual entries: OVPN_BYPASS_IPS
  if [[ -n "$OVPN_BYPASS_IPS" ]]; then
    IFS=', ' read -r -a token_arr <<< "$OVPN_BYPASS_IPS"
    for token in "${token_arr[@]}"; do
      [[ -z "$token" ]] && continue
      if is_ipv4 "$token"; then
        token="${token}/32"
      elif [[ "$token" != */* ]]; then
        token="${token}/32"
      fi
      token=$(sanitize_token "$token")
      [[ -z "$token" ]] && continue
      _add_bypass_token "$token"
    done
  fi

  # 2) Parse directives from ovpn profile
  if [[ "$SKIP_OVPN_PROFILE_PARSE" != "1" && -n "$OVPN_PROFILE_PATH" && -r "$OVPN_PROFILE_PATH" ]]; then
    while IFS= read -r line; do
      line="$(sed -e 's/#.*$//' -e 's/^[[:space:]]*//' <<<"$line" | tr -d "\"'")"
      [[ -z "$line" ]] && continue
      # trim any leading/trailing spaces
      line="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<<"$line")"
      [[ -z "$line" ]] && continue

      read -r -a fields <<< "$line"
      case "${fields[0]:-}" in
        remote)
          host=$(sanitize_token "${fields[1]:-}")
          if is_ipv4 "$host"; then
            _add_bypass_token "${host}/32"
            continue
          fi
          while IFS= read -r ip _; do
            if is_ipv4 "$ip"; then
              _add_bypass_token "${ip}/32"
            fi
          done < <(getent hosts "$host" 2>/dev/null || true)
          ;;
        route)
          network=$(sanitize_token "${fields[1]:-}")
          mask=$(sanitize_token "${fields[2]:-}")
          if is_ipv4 "$network" && is_ipv4 "$mask"; then
            cidr=$(mask_to_cidr "$mask" || true)
            [[ -n "$cidr" ]] && _add_bypass_token "${network}/${cidr}"
          fi
          ;;
        push)
          if [[ "${fields[1]:-}" == "route" ]]; then
            network=$(sanitize_token "${fields[2]:-}")
            mask=$(sanitize_token "${fields[3]:-}")
            if is_ipv4 "$network" && is_ipv4 "$mask"; then
              cidr=$(mask_to_cidr "$mask" || true)
              [[ -n "$cidr" ]] && _add_bypass_token "${network}/${cidr}"
            fi
          fi
          ;;
      esac
    done < "$OVPN_PROFILE_PATH"
  fi
}


check_inputs() {
  ip link show "$HOTSPOT_IF" >/dev/null
  ip link show "$VPN_IF" >/dev/null
  local subnet
  subnet=$(resolve_hotspot_subnet)
  if ! is_cidr "$subnet"; then
    echo "error: no valid IPv4 subnet found for hotspot interface $HOTSPOT_IF" >&2
    echo "debug: HOTSPOT_IF=$HOTSPOT_IF HOTSPOT_SUBNET_OVERRIDE=${HOTSPOT_SUBNET_OVERRIDE}" >&2
    echo "debug: ip -4 -o addr show dev $HOTSPOT_IF" >&2; ip -4 -o addr show dev "$HOTSPOT_IF" || true
    echo "debug: ip -4 route show dev $HOTSPOT_IF" >&2; ip -4 route show dev "$HOTSPOT_IF" || true
    exit 1
  fi
}

iptables_enable_rules() {
  local subnet=$1
  local main_if=$2

  # Hotspot traffic to VPN path
  iptables -C FORWARD -i "$HOTSPOT_IF" -o "$VPN_IF" -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i "$HOTSPOT_IF" -o "$VPN_IF" -j ACCEPT
  iptables -C FORWARD -i "$VPN_IF" -o "$HOTSPOT_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i "$VPN_IF" -o "$HOTSPOT_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -t nat -C POSTROUTING -s "$subnet" -o "$VPN_IF" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s "$subnet" -o "$VPN_IF" -j MASQUERADE

  # Ensure direct WAN bypass can pass and be NATed when needed
  if [[ -n "$main_if" && "$main_if" != "$VPN_IF" ]]; then
    iptables -C FORWARD -i "$HOTSPOT_IF" -o "$main_if" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -t nat -C POSTROUTING -s "$subnet" -o "$main_if" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s "$subnet" -o "$main_if" -j MASQUERADE
  fi

  if [[ "$CLAMP_MSS" == "1" ]]; then
    iptables -t mangle -C FORWARD -i "$HOTSPOT_IF" -o "$VPN_IF" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null \
      || iptables -t mangle -A FORWARD -i "$HOTSPOT_IF" -o "$VPN_IF" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

    if [[ -n "$main_if" && "$main_if" != "$VPN_IF" ]]; then
      iptables -t mangle -C FORWARD -i "$HOTSPOT_IF" -o "$main_if" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null \
        || iptables -t mangle -A FORWARD -i "$HOTSPOT_IF" -o "$main_if" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
    fi
  fi
}

iptables_disable_rules() {
  local subnet=$1
  local main_if=$2

  iptables -D FORWARD -i "$HOTSPOT_IF" -o "$VPN_IF" -j ACCEPT 2>/dev/null || true
  iptables -D FORWARD -i "$VPN_IF" -o "$HOTSPOT_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
  iptables -t nat -D POSTROUTING -s "$subnet" -o "$VPN_IF" -j MASQUERADE 2>/dev/null || true

  if [[ -n "$main_if" && "$main_if" != "$VPN_IF" ]]; then
    iptables -D FORWARD -i "$HOTSPOT_IF" -o "$main_if" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s "$subnet" -o "$main_if" -j MASQUERADE 2>/dev/null || true
  fi

  if [[ "$CLAMP_MSS" == "1" ]]; then
    iptables -t mangle -D FORWARD -i "$HOTSPOT_IF" -o "$VPN_IF" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    if [[ -n "$main_if" && "$main_if" != "$VPN_IF" ]]; then
      iptables -t mangle -D FORWARD -i "$HOTSPOT_IF" -o "$main_if" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    fi
  fi
}

apply_bypass_rules() {
  local subnet=$1
  local -a bypass_nets=()

  if ! is_cidr "$subnet"; then
    echo "skip_bypass_rules: hotspot subnet invalid ($subnet)" >&2
    return 1
  fi

  collect_bypass_networks bypass_nets

  : > "$BYPASS_RULE_FILE"
  local i=0
  for net in "${bypass_nets[@]}"; do
    if ! is_cidr "$net"; then
      echo "skip_invalid_bypass=$net" >/dev/stderr
      continue
    fi
    if ! is_cidr "$subnet"; then
      echo "error: invalid hotspot subnet $subnet for bypass rules" >/dev/stderr
      continue
    fi
    local prio=$((RULE_PRIO_BYPASS + i))
    if ! ip rule add from "$subnet" to "$net" table main priority "$prio" 2>/dev/null; then
      ip rule del from "$subnet" to "$net" table main priority "$prio" 2>/dev/null || true
      ip rule add from "$subnet" to "$net" table main priority "$prio" && {
        echo "$subnet $net $prio" >> "$BYPASS_RULE_FILE"
        i=$((i + 1))
      }
    else
      echo "$subnet $net $prio" >> "$BYPASS_RULE_FILE"
      i=$((i + 1))
    fi
  done

  if (( i > 0 )); then
    echo "bypass_networks=${bypass_nets[*]}"
  else
    echo "bypass_networks="
  fi
}

clear_bypass_rules() {
  if [[ ! -r "$BYPASS_RULE_FILE" ]]; then
    return
  fi
  while IFS=' ' read -r subnet to_net prio; do
    [[ -z "$subnet" || -z "$to_net" || -z "$prio" ]] && continue
    ip rule del from "$subnet" to "$to_net" table main priority "$prio" 2>/dev/null || true
  done < "$BYPASS_RULE_FILE"
  rm -f "$BYPASS_RULE_FILE"
}

up() {
  need_root
  check_inputs
  local subnet
  local main_if
  subnet=$(resolve_hotspot_subnet)
  if ! is_cidr "$subnet"; then
    echo "error: could not detect valid HOTSPOT subnet for $HOTSPOT_IF" >&2
    echo "debug: HOTSPOT_SUBNET_OVERRIDE=${HOTSPOT_SUBNET_OVERRIDE}" >&2
    echo "debug: ip -4 -o addr show dev $HOTSPOT_IF" >&2; ip -4 -o addr show dev "$HOTSPOT_IF" || true
    echo "debug: ip -4 route show dev $HOTSPOT_IF" >&2; ip -4 route show dev "$HOTSPOT_IF" || true
    exit 1
  fi
  main_if=$(main_out_iface || true)

  sysctl -w \
    net.ipv4.ip_forward=1 \
    net.ipv4.conf.all.rp_filter=0 \
    "net.ipv4.conf.${HOTSPOT_IF}.rp_filter=0" \
    "net.ipv4.conf.${VPN_IF}.rp_filter=0" >/dev/null

  # Bypass VPN handshake destinations from forced 2022 table
  clear_bypass_rules
  apply_bypass_rules "$subnet"

  ip rule del from "$subnet" table "$ROUTE_TABLE" priority "$RULE_PRIO" 2>/dev/null || true
  ip rule add from "$subnet" table "$ROUTE_TABLE" priority "$RULE_PRIO"

  iptables_enable_rules "$subnet" "$main_if"

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --direct --remove-rule ipv4 filter FORWARD 0 -i "$HOTSPOT_IF" -o "$VPN_IF" -j ACCEPT 2>/dev/null || true
    firewall-cmd --direct --remove-rule ipv4 filter FORWARD 0 -i "$VPN_IF" -o "$HOTSPOT_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    if [[ -n "$subnet" ]]; then
      firewall-cmd --direct --remove-rule ipv4 nat POSTROUTING 0 -s "$subnet" -o "$VPN_IF" -j MASQUERADE 2>/dev/null || true
    fi
    firewall-cmd --direct --add-rule ipv4 filter FORWARD 0 -i "$HOTSPOT_IF" -o "$VPN_IF" -j ACCEPT
    firewall-cmd --direct --add-rule ipv4 filter FORWARD 0 -i "$VPN_IF" -o "$HOTSPOT_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    if [[ -n "$subnet" ]]; then
      firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s "$subnet" -o "$VPN_IF" -j MASQUERADE
    fi
  fi

  nft delete table inet "$NFT_TABLE" 2>/dev/null || true
  nft -f - <<EOF_NFT
table inet $NFT_TABLE {
  chain forward_chain {
    type filter hook forward priority -5; policy accept;
    iifname "$HOTSPOT_IF" oifname "$VPN_IF" tcp flags syn tcp option maxseg size set rt mtu counter accept
    iifname "$HOTSPOT_IF" oifname "$VPN_IF" counter accept
    iifname "$VPN_IF" oifname "$HOTSPOT_IF" ct state established,related counter accept
  }

  chain postrouting_chain {
    type nat hook postrouting priority srcnat; policy accept;
    ip saddr $subnet oifname "$VPN_IF" counter masquerade
  }
}
EOF_NFT

  echo "hotspot_vpn=up"
  status
}

down() {
  need_root
  local subnet
  local main_if
  subnet=$(resolve_hotspot_subnet || true)
  main_if=$(main_out_iface || true)

  if [[ -n "$subnet" ]]; then
    clear_bypass_rules
    ip rule del from "$subnet" table "$ROUTE_TABLE" priority "$RULE_PRIO" 2>/dev/null || true
  fi

  iptables_disable_rules "$subnet" "$main_if"

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --direct --remove-rule ipv4 filter FORWARD 0 -i "$HOTSPOT_IF" -o "$VPN_IF" -j ACCEPT 2>/dev/null || true
    firewall-cmd --direct --remove-rule ipv4 filter FORWARD 0 -i "$VPN_IF" -o "$HOTSPOT_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    if [[ -n "$subnet" ]]; then
      firewall-cmd --direct --remove-rule ipv4 nat POSTROUTING 0 -s "$subnet" -o "$VPN_IF" -j MASQUERADE 2>/dev/null || true
    fi
  fi
  nft delete table inet "$NFT_TABLE" 2>/dev/null || true
  echo "hotspot_vpn=down"
}

status() {
  check_inputs
  local subnet client_ip
  local main_if
  subnet=$(resolve_hotspot_subnet)
  main_if=$(main_out_iface || true)
  client_ip=$(ip -4 neigh show dev "$HOTSPOT_IF" | awk '/lladdr/ {print $1; exit}' || true)

  echo "hotspot_if=$HOTSPOT_IF"
  echo "vpn_if=$VPN_IF"
  echo "main_if=$main_if"
  echo "hotspot_subnet=$subnet"
  echo "route_table=$ROUTE_TABLE"
  echo "rule_prio=$RULE_PRIO"
  echo "nft_table=$NFT_TABLE"
  echo "ovpn_profile=${OVPN_PROFILE_PATH:-<empty>}"
  echo "ovpn_bypass_ips=${OVPN_BYPASS_IPS:-<empty>}"
  echo "bypass_rules_file=$BYPASS_RULE_FILE"
  ip rule show | grep -E "lookup $ROUTE_TABLE|from $subnet to|lookup main" || true
  ip route show table "$ROUTE_TABLE" | head -20 || true
  nft -a list table inet "$NFT_TABLE" 2>/dev/null || true
  iptables -L FORWARD -v -n 2>/dev/null | sed -n '1,120p' || true
  iptables -t nat -L POSTROUTING -v -n 2>/dev/null | sed -n '1,120p' || true
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    echo "firewalld_direct_rules:"
    firewall-cmd --direct --get-all-rules | grep -E "${HOTSPOT_IF}\|${VPN_IF}\|${main_if}" || true
  fi
  iw dev "$HOTSPOT_IF" info 2>/dev/null | grep -E 'ssid|type|channel' || true
  iw dev "$HOTSPOT_IF" station dump 2>/dev/null | sed -E 's/Station ([0-9a-f:]{17})/Station <MAC>/Ig' | head -80 || true
  if [[ -n "$client_ip" ]]; then
    echo "client_seen=yes"
    ip route get 1.1.1.1 from "$client_ip" iif "$HOTSPOT_IF" || true
  else
    echo "client_seen=no"
  fi

  if [[ -r "$BYPASS_RULE_FILE" ]]; then
    echo "active_bypass_rules:"
    cat "$BYPASS_RULE_FILE"
  fi
}

case "$ACTION" in
  up) up ;;
  down) down ;;
  status) status ;;
  *)
    echo "usage: $0 {up|down|status}" >&2
    exit 2
    ;;
esac
