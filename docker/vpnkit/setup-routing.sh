#!/usr/bin/env bash
set -euo pipefail

OVPN_CIDR=${OVPN_CIDR:-10.89.0.0/24}
VPNKIT_ROUTING_MODE=${VPNKIT_ROUTING_MODE:-redirect}
TPROXY_PORT=${TPROXY_PORT:-2082}
DNS_REDIRECT_PORT=${DNS_REDIRECT_PORT:-5353}
MARK=${TPROXY_MARK:-0x1}
TABLE=${TPROXY_TABLE:-100}
TUN_IFACE=${SINGBOX_TUN_IFACE:-sb-tun0}
TUN_PEER=${SINGBOX_TUN_PEER:-172.19.0.2}
TUN_TABLE=${SINGBOX_TUN_TABLE:-101}
VPNKIT_COMPAT_BYPASS_ENABLED=${VPNKIT_COMPAT_BYPASS_ENABLED:-false}
VPNKIT_COMPAT_BYPASS_ENDPOINTS=${VPNKIT_COMPAT_BYPASS_ENDPOINTS:-}
VPNKIT_COMPAT_BYPASS_ALLOW_ICMP=${VPNKIT_COMPAT_BYPASS_ALLOW_ICMP:-false}
VPNKIT_IPV6_POLICY=${VPNKIT_IPV6_POLICY:-block}
VPNKIT_IPV6_POLICY=${VPNKIT_IPV6_POLICY,,}
VPNKIT_ROUTING_DRY_RUN=${VPNKIT_ROUTING_DRY_RUN:-false}
OPENVPN_FAIL_CLOSED_CHAIN=${OPENVPN_FAIL_CLOSED_CHAIN:-OVPN_FAIL_CLOSED}
OPENVPN_FAIL_CLOSED_OWNER_FILE=${VPNKIT_FAIL_CLOSED_OWNER_FILE:-/run/vpnkit/fail-closed-chain.owner}
SINGBOX_GENERATION_FILE=${VPNKIT_SINGBOX_GENERATION_FILE:-${SINGBOX_GENERATION_FILE:-/run/vpnkit/sing-box-generation}}
ACTION=apply
case "${1:-}" in
  "") ;;
  --install-fail-closed-barrier) ACTION=install-barrier ;;
  --remove-fail-closed-barrier) ACTION=remove-barrier ;;
  --help|-h)
    printf '%s\n' 'Usage: setup-routing.sh [--install-fail-closed-barrier|--remove-fail-closed-barrier]'
    exit 0
    ;;
  *)
    echo 'unsupported setup-routing action' >&2
    exit 2
    ;;
esac
[[ $# -le 1 ]] || { echo 'unsupported setup-routing arguments' >&2; exit 2; }

is_truthy() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

is_dry_run() {
  is_truthy "$VPNKIT_ROUTING_DRY_RUN"
}

run() {
  if is_dry_run; then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

ensure_iptables_rule() {
  local table=$1
  local chain=$2
  shift 2

  if is_dry_run; then
    run iptables -t "$table" -A "$chain" "$@"
    return 0
  fi

  iptables -t "$table" -C "$chain" "$@" 2>/dev/null \
    || iptables -t "$table" -A "$chain" "$@"
}

ensure_iptables_rule_at_head() {
  local table=$1
  local chain=$2
  shift 2

  if is_dry_run; then
    run iptables -t "$table" -I "$chain" 1 "$@"
    return 0
  fi

  # Always insert at position one. `iptables -C` can prove existence but not
  # position; re-inserting prevents an earlier ACCEPT from bypassing an older
  # copy of this exact barrier. Cleanup removes all duplicates by exact match.
  iptables -t "$table" -I "$chain" 1 "$@"
}

remove_iptables_rule_exact() {
  local table=$1
  local chain=$2
  shift 2

  if is_dry_run; then
    run iptables -t "$table" -D "$chain" "$@"
    return 0
  fi

  while iptables -t "$table" -C "$chain" "$@" 2>/dev/null; do
    iptables -t "$table" -D "$chain" "$@"
  done
}

ensure_ip6tables_rule() {
  local table=$1
  local chain=$2
  shift 2

  if is_dry_run; then
    run ip6tables -t "$table" -A "$chain" "$@"
    return 0
  fi

  ip6tables -t "$table" -C "$chain" "$@" 2>/dev/null \
    || ip6tables -t "$table" -A "$chain" "$@"
}

remove_ip6tables_rule() {
  local table=$1
  local chain=$2
  shift 2

  if is_dry_run; then
    run ip6tables -t "$table" -D "$chain" "$@"
    return 0
  fi

  while ip6tables -t "$table" -C "$chain" "$@" 2>/dev/null; do
    ip6tables -t "$table" -D "$chain" "$@" || break
  done
}

validate_ipv6_policy() {
  case "$VPNKIT_IPV6_POLICY" in
    block|allow) return 0 ;;
    *)
      echo "unsupported VPNKIT_IPV6_POLICY=$VPNKIT_IPV6_POLICY (expected block or allow)" >&2
      return 1
      ;;
  esac
}

ensure_ipv6_block_tooling() {
  if is_dry_run; then
    return 0
  fi
  if command -v ip6tables >/dev/null 2>&1; then
    return 0
  fi
  if [[ ! -d /proc/sys/net/ipv6 ]]; then
    echo "IPv6 kernel support is absent; skipping VPNKIT_IPV6_POLICY=block rules" >&2
    return 1
  fi
  echo "VPNKIT_IPV6_POLICY=block requires ip6tables, but ip6tables is unavailable" >&2
  return 2
}

clear_ipv6_block_rules() {
  if ! is_dry_run && ! command -v ip6tables >/dev/null 2>&1; then
    echo "ip6tables is unavailable; no managed IPv6 block rules to clear" >&2
    return 0
  fi

  remove_ip6tables_rule filter INPUT -i tun0 -j OVPN_IPV6_BLOCK
  remove_ip6tables_rule filter FORWARD -i tun0 -j OVPN_IPV6_BLOCK
  remove_ip6tables_rule filter OUTPUT -o tun0 -j OVPN_IPV6_BLOCK
  remove_ip6tables_rule filter FORWARD -o tun0 -j OVPN_IPV6_BLOCK
  run ip6tables -t filter -F OVPN_IPV6_BLOCK 2>/dev/null || true
  run ip6tables -t filter -X OVPN_IPV6_BLOCK 2>/dev/null || true
}

install_ipv6_block_rules() {
  ensure_ipv6_block_tooling
  local status=$?
  if [[ $status -ne 0 ]]; then
    if [[ $status -eq 1 ]]; then
      return 0
    fi
    return "$status"
  fi

  run ip6tables -t filter -N OVPN_IPV6_BLOCK 2>/dev/null || true
  run ip6tables -t filter -F OVPN_IPV6_BLOCK
  ensure_ip6tables_rule filter INPUT -i tun0 -j OVPN_IPV6_BLOCK
  ensure_ip6tables_rule filter FORWARD -i tun0 -j OVPN_IPV6_BLOCK
  ensure_ip6tables_rule filter OUTPUT -o tun0 -j OVPN_IPV6_BLOCK
  ensure_ip6tables_rule filter FORWARD -o tun0 -j OVPN_IPV6_BLOCK
  run ip6tables -t filter -A OVPN_IPV6_BLOCK -j DROP
  run ip6tables -t filter -L OVPN_IPV6_BLOCK -v -n -x
}

install_ipv6_policy() {
  validate_ipv6_policy
  case "$VPNKIT_IPV6_POLICY" in
    block) install_ipv6_block_rules ;;
    allow) clear_ipv6_block_rules ;;
  esac
}

valid_ipv4_literal() {
  local ip=$1
  local IFS=.
  local -a octets
  read -r -a octets <<<"$ip"
  [[ ${#octets[@]} -eq 4 ]] || return 1

  local octet
  for octet in "${octets[@]}"; do
    [[ $octet =~ ^[0-9]+$ ]] || return 1
    (( 10#$octet <= 255 )) || return 1
  done
}

valid_ipv4_cidr() {
  local value=$1 address prefix
  [[ "$value" == */* ]] || return 1
  address=${value%/*}
  prefix=${value##*/}
  valid_ipv4_literal "$address" || return 1
  [[ "$prefix" =~ ^[0-9]{1,2}$ ]] || return 1
  (( prefix >= 1 && prefix <= 32 )) || return 1
}

validate_fail_closed_chain() {
  # This fixed application-reserved name can never alias a built-in or an
  # operator-selected foreign chain.
  [[ "$OPENVPN_FAIL_CLOSED_CHAIN" == OVPN_FAIL_CLOSED ]] \
    || { echo 'fail-closed chain override is not permitted' >&2; return 2; }
  [[ "$OPENVPN_FAIL_CLOSED_OWNER_FILE" == /run/* && "$OPENVPN_FAIL_CLOSED_OWNER_FILE" != *'/../'* ]] \
    || { echo 'fail-closed owner marker must remain below /run' >&2; return 2; }
}

fail_closed_chain_owned() {
  [[ -f "$OPENVPN_FAIL_CLOSED_OWNER_FILE" && ! -L "$OPENVPN_FAIL_CLOSED_OWNER_FILE" ]] || return 1
  [[ $(stat -c %h -- "$OPENVPN_FAIL_CLOSED_OWNER_FILE" 2>/dev/null) == 1 ]] || return 1
  [[ $(<"$OPENVPN_FAIL_CLOSED_OWNER_FILE") == "$OPENVPN_FAIL_CLOSED_CHAIN" ]]
}

record_fail_closed_chain_ownership() {
  local dir tmp
  dir=${OPENVPN_FAIL_CLOSED_OWNER_FILE%/*}
  install -d -m 0700 "$dir"
  tmp=$(mktemp "$dir/.fail-closed-owner.XXXXXX") || return 1
  chmod 0600 "$tmp" || { rm -f -- "$tmp"; return 1; }
  printf '%s\n' "$OPENVPN_FAIL_CLOSED_CHAIN" >"$tmp" || { rm -f -- "$tmp"; return 1; }
  mv -T -- "$tmp" "$OPENVPN_FAIL_CLOSED_OWNER_FILE" || { rm -f -- "$tmp"; return 1; }
}

install_fail_closed_barrier() {
  valid_ipv4_cidr "$OVPN_CIDR" || { echo 'invalid OpenVPN CIDR for fail-closed barrier' >&2; return 2; }
  validate_fail_closed_chain || return
  command -v iptables >/dev/null 2>&1 || { echo 'iptables is unavailable for fail-closed barrier' >&2; return 10; }

  # Use an explicitly owned chain rather than xt_comment: minimal/container
  # kernels may not provide the comment match extension. Never adopt a
  # pre-existing same-name chain unless our private capability marker exists.
  if is_dry_run; then
    run iptables -t filter -N "$OPENVPN_FAIL_CLOSED_CHAIN"
  elif iptables -t filter -N "$OPENVPN_FAIL_CLOSED_CHAIN" 2>/dev/null; then
    record_fail_closed_chain_ownership || {
      iptables -t filter -X "$OPENVPN_FAIL_CLOSED_CHAIN" 2>/dev/null || true
      echo 'could not record fail-closed chain ownership' >&2
      return 11
    }
  elif ! fail_closed_chain_owned; then
    echo 'refusing pre-existing unowned fail-closed chain' >&2
    return 11
  fi
  ensure_iptables_rule filter "$OPENVPN_FAIL_CLOSED_CHAIN" -j DROP

  # Do not require tun0 to exist: this barrier is installed before OpenVPN.
  ensure_iptables_rule_at_head filter INPUT -s "$OVPN_CIDR" -j "$OPENVPN_FAIL_CLOSED_CHAIN"
  ensure_iptables_rule_at_head filter FORWARD -s "$OVPN_CIDR" -j "$OPENVPN_FAIL_CLOSED_CHAIN"
}

remove_fail_closed_barrier() {
  validate_fail_closed_chain || return
  command -v iptables >/dev/null 2>&1 || return 10
  if ! is_dry_run && ! fail_closed_chain_owned; then
    echo 'refusing cleanup of unowned fail-closed chain' >&2
    return 11
  fi
  remove_iptables_rule_exact filter INPUT -s "$OVPN_CIDR" -j "$OPENVPN_FAIL_CLOSED_CHAIN"
  remove_iptables_rule_exact filter FORWARD -s "$OVPN_CIDR" -j "$OPENVPN_FAIL_CLOSED_CHAIN"
  if is_dry_run; then
    run iptables -t filter -F "$OPENVPN_FAIL_CLOSED_CHAIN"
    run iptables -t filter -X "$OPENVPN_FAIL_CLOSED_CHAIN"
  else
    if iptables -t filter -S "$OPENVPN_FAIL_CLOSED_CHAIN" >/dev/null 2>&1; then
      iptables -t filter -F "$OPENVPN_FAIL_CLOSED_CHAIN" \
        || { echo 'could not flush owned fail-closed chain' >&2; return 12; }
      iptables -t filter -X "$OPENVPN_FAIL_CLOSED_CHAIN" \
        || { echo 'could not delete owned fail-closed chain' >&2; return 12; }
    fi
    rm -f -- "$OPENVPN_FAIL_CLOSED_OWNER_FILE"
  fi
}

write_runtime_generation() {
  local current=0 tmp dir
  if is_dry_run; then
    printf '%s\n' '+ runtime generation advanced'
    return 0
  fi
  if [[ -r "$SINGBOX_GENERATION_FILE" ]]; then
    current=$(<"$SINGBOX_GENERATION_FILE")
    [[ "$current" =~ ^[0-9]+$ ]] || current=0
  fi
  current=$((current + 1))
  dir=${SINGBOX_GENERATION_FILE%/*}
  [[ "$dir" != "$SINGBOX_GENERATION_FILE" ]] || dir=.
  mkdir -p "$dir"
  tmp=$(mktemp "${SINGBOX_GENERATION_FILE}.tmp.XXXXXX")
  printf '%s\n' "$current" >"$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$SINGBOX_GENERATION_FILE"
}

validate_proto() {
  local proto=$1
  case "$proto" in
    tcp|udp) return 0 ;;
    *)
      echo "invalid compatibility bypass proto '$proto' (expected tcp or udp)" >&2
      return 1
      ;;
  esac
}

validate_port() {
  local port=$1
  if [[ ! $port =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    echo "invalid compatibility bypass port '$port' (expected 1-65535)" >&2
    return 1
  fi
}

parse_compat_endpoint() {
  local spec=$1
  local endpoint proto proto_prefix proto_suffix host port proto_explicit

  endpoint=${spec//[[:space:]]/}
  if [[ -z $endpoint ]]; then
    echo "empty compatibility bypass endpoint" >&2
    return 1
  fi

  proto=udp
  proto_explicit=false
  if [[ $endpoint == *://* ]]; then
    proto_prefix=${endpoint%%://*}
    endpoint=${endpoint#*://}
    proto=${proto_prefix,,}
    proto_explicit=true
  fi

  if [[ $endpoint == */* ]]; then
    proto_suffix=${endpoint##*/}
    endpoint=${endpoint%/*}
    proto_suffix=${proto_suffix,,}
    if [[ $proto_explicit == true && $proto != "$proto_suffix" ]]; then
      echo "conflicting compatibility bypass proto in '$spec'" >&2
      return 1
    fi
    proto=$proto_suffix
    proto_explicit=true
  fi

  validate_proto "$proto"

  if [[ $endpoint != *:* ]]; then
    echo "invalid compatibility bypass endpoint '$spec' (expected host:port[/proto])" >&2
    return 1
  fi
  host=${endpoint%:*}
  port=${endpoint##*:}
  if [[ -z $host || -z $port ]]; then
    echo "invalid compatibility bypass endpoint '$spec' (expected host:port[/proto])" >&2
    return 1
  fi
  validate_port "$port"

  printf '%s\t%s\t%s\n' "$host" "$port" "$proto"
}

resolve_compat_endpoint_ips() {
  local host=$1

  if valid_ipv4_literal "$host"; then
    printf '%s\n' "$host"
    return 0
  fi

  getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u || true
}

reset_compat_bypass_chains() {
  run iptables -t nat -N OVPN_COMPAT_POST 2>/dev/null || true
  run iptables -t nat -F OVPN_COMPAT_POST
  run iptables -N OVPN_COMPAT_FWD 2>/dev/null || true
  run iptables -F OVPN_COMPAT_FWD
}

install_compat_bypass_rules() {
  if ! is_truthy "$VPNKIT_COMPAT_BYPASS_ENABLED"; then
    return 0
  fi

  local normalized_specs spec host port proto ips ip
  local -a specs
  local -A icmp_seen=()

  normalized_specs=${VPNKIT_COMPAT_BYPASS_ENDPOINTS//,/ }
  normalized_specs=${normalized_specs//;/ }
  read -r -a specs <<<"$normalized_specs"
  if [[ ${#specs[@]} -eq 0 ]]; then
    echo "VPNKIT_COMPAT_BYPASS_ENABLED=true but VPNKIT_COMPAT_BYPASS_ENDPOINTS is empty" >&2
    return 1
  fi

  ensure_iptables_rule nat POSTROUTING -s "$OVPN_CIDR" -j OVPN_COMPAT_POST
  ensure_iptables_rule filter FORWARD -s "$OVPN_CIDR" -j OVPN_COMPAT_FWD
  ensure_iptables_rule filter FORWARD -d "$OVPN_CIDR" -j OVPN_COMPAT_FWD

  for spec in "${specs[@]}"; do
    IFS=$'\t' read -r host port proto < <(parse_compat_endpoint "$spec")
    ips=$(resolve_compat_endpoint_ips "$host")
    if [[ -z $ips ]]; then
      echo "could not resolve compatibility bypass endpoint host '$host'" >&2
      return 1
    fi

    while IFS= read -r ip; do
      [[ -n $ip ]] || continue
      run iptables -t nat -A OVPN_REDIRECT_TO_SINGBOX -d "$ip" -p "$proto" --dport "$port" -j RETURN
      run iptables -t nat -A OVPN_COMPAT_POST -d "$ip" -p "$proto" --dport "$port" -j MASQUERADE
      run iptables -A OVPN_COMPAT_FWD -s "$OVPN_CIDR" -d "$ip" -p "$proto" --dport "$port" -j ACCEPT
      run iptables -A OVPN_COMPAT_FWD -d "$OVPN_CIDR" -s "$ip" -p "$proto" --sport "$port" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

      if is_truthy "$VPNKIT_COMPAT_BYPASS_ALLOW_ICMP" && [[ -z ${icmp_seen[$ip]:-} ]]; then
        icmp_seen[$ip]=1
        run iptables -t nat -A OVPN_REDIRECT_TO_SINGBOX -d "$ip" -p icmp -j RETURN
        run iptables -t nat -A OVPN_COMPAT_POST -d "$ip" -p icmp -j MASQUERADE
        run iptables -A OVPN_COMPAT_FWD -s "$OVPN_CIDR" -d "$ip" -p icmp -j ACCEPT
        run iptables -A OVPN_COMPAT_FWD -d "$OVPN_CIDR" -s "$ip" -p icmp -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      fi
    done <<<"$ips"
  done
}

case "$ACTION" in
  install-barrier)
    install_fail_closed_barrier
    exit 0
    ;;
  remove-barrier)
    remove_fail_closed_barrier
    exit 0
    ;;
  apply) ;;
esac

# A normal routing apply is itself guarded. The entrypoint installs this exact
# barrier before OpenVPN starts; keeping this first makes restarts fail closed
# even when setup-routing is invoked independently.
install_fail_closed_barrier

run sysctl -w net.ipv4.ip_forward=1 >/dev/null || true
run sysctl -w net.ipv4.conf.all.src_valid_mark=1 >/dev/null || true
run sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null || true
run sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null || true
run sysctl -w net.ipv4.conf.tun0.src_valid_mark=1 >/dev/null || true
run sysctl -w net.ipv4.conf.tun0.rp_filter=0 >/dev/null || true

install_ipv6_policy

case "$VPNKIT_ROUTING_MODE" in
  tproxy)
    if ! ip rule show | grep -q "fwmark $MARK lookup $TABLE"; then
      run ip rule add fwmark "$MARK" table "$TABLE"
    fi
    run ip route replace local default dev lo table "$TABLE"

    run iptables -t mangle -N OVPN_TO_SINGBOX 2>/dev/null || true
    run iptables -t mangle -F OVPN_TO_SINGBOX
    iptables -t mangle -C PREROUTING -i tun0 -s "$OVPN_CIDR" -j OVPN_TO_SINGBOX 2>/dev/null \
      || run iptables -t mangle -A PREROUTING -i tun0 -s "$OVPN_CIDR" -j OVPN_TO_SINGBOX
    run iptables -t mangle -A OVPN_TO_SINGBOX -p tcp -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK"/"$MARK"
    run iptables -t mangle -A OVPN_TO_SINGBOX -p udp -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$MARK"/"$MARK"
    # Scoped local-delivery accept for marked TPROXY packets. This is not broad NAT;
    # it only prevents restrictive filter policies from dropping packets already
    # selected for local transparent proxy delivery.
    # Keep the temporary source-CIDR DROP at INPUT position one while
    # setup-routing is still in progress; this scoped accept is inserted just
    # behind it and is safe only after the barrier is removed at the end.
    iptables -C INPUT -i tun0 -s "$OVPN_CIDR" -m mark --mark "$MARK" -j ACCEPT 2>/dev/null \
      || run iptables -I INPUT 2 -i tun0 -s "$OVPN_CIDR" -m mark --mark "$MARK" -j ACCEPT

    ip rule show
    ip route show table "$TABLE"
    iptables -t mangle -L OVPN_TO_SINGBOX -v -n -x
    iptables -L INPUT -v -n -x | sed -n '1,12p'
    ;;
  tun)
    until ip link show "$TUN_IFACE" >/dev/null 2>&1; do
      sleep 0.2
    done
    run ip route replace default via "$TUN_PEER" dev "$TUN_IFACE" table "$TUN_TABLE"
    if ! ip rule show | grep -q "from $OVPN_CIDR lookup $TUN_TABLE"; then
      run ip rule add from "$OVPN_CIDR" table "$TUN_TABLE" priority 1000
    fi
    ensure_iptables_rule filter FORWARD -i tun0 -o "$TUN_IFACE" -s "$OVPN_CIDR" -j ACCEPT
    ensure_iptables_rule filter FORWARD -i "$TUN_IFACE" -o tun0 -d "$OVPN_CIDR" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ip rule show
    ip route show table "$TUN_TABLE"
    ip -s link show "$TUN_IFACE"
    ;;
  redirect)
    run iptables -t nat -N OVPN_REDIRECT_TO_SINGBOX 2>/dev/null || true
    run iptables -t nat -F OVPN_REDIRECT_TO_SINGBOX
    reset_compat_bypass_chains
    ensure_iptables_rule nat PREROUTING -i tun0 -s "$OVPN_CIDR" -j OVPN_REDIRECT_TO_SINGBOX
    install_compat_bypass_rules
    run iptables -t nat -A OVPN_REDIRECT_TO_SINGBOX -p tcp -j REDIRECT --to-ports "$TPROXY_PORT"
    run iptables -t nat -A OVPN_REDIRECT_TO_SINGBOX -p udp --dport 53 -j REDIRECT --to-ports "$DNS_REDIRECT_PORT"
    run iptables -t nat -L OVPN_REDIRECT_TO_SINGBOX -v -n -x
    if is_truthy "$VPNKIT_COMPAT_BYPASS_ENABLED"; then
      run iptables -t nat -L OVPN_COMPAT_POST -v -n -x
      run iptables -L OVPN_COMPAT_FWD -v -n -x
    fi
    ;;
  *)
    echo "unsupported VPNKIT_ROUTING_MODE=$VPNKIT_ROUTING_MODE (expected redirect, tun, or tproxy)" >&2
    exit 2
    ;;
esac

# Advance the generation before removing the barrier. A caller waiting on a
# request-file restart can therefore prove both setup completion and barrier
# replacement; any earlier failure leaves the DROP rules installed.
write_runtime_generation
remove_fail_closed_barrier
