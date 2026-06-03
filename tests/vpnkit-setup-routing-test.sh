#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/ip" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "rule show") exit 0 ;;
  "route show") exit 0 ;;
  "link show") exit 0 ;;
esac
exit 0
SH
cat > "$TMP/iptables" <<'SH'
#!/usr/bin/env bash
if [[ " $* " == *" -C "* ]]; then
  exit 1
fi
if [[ " $* " == *" -L "* ]]; then
  exit 0
fi
exit 0
SH
cp "$TMP/iptables" "$TMP/ip6tables"
chmod +x "$TMP/ip" "$TMP/iptables" "$TMP/ip6tables"

OUTPUT=$(PATH="$TMP:$PATH" \
  VPNKIT_ROUTING_DRY_RUN=true \
  VPNKIT_ROUTING_MODE=tproxy \
  VPNKIT_IPV6_POLICY=allow \
  bash "$ROOT/docker/vpnkit/setup-routing.sh")

printf '%s\n' "$OUTPUT" | grep -q 'OVPN_TPROXY_UDP_POST'
printf '%s\n' "$OUTPUT" | grep -q 'OVPN_TPROXY_UDP_FWD'
printf '%s\n' "$OUTPUT" | grep -q -- '-A OVPN_TO_SINGBOX -p udp -d 172.16.0.0/12 -m comment --comment vpnkit:tproxy-private-udp-bypass -j RETURN'
printf '%s\n' "$OUTPUT" | grep -q -- '-A OVPN_TPROXY_UDP_POST -d 172.16.0.0/12 -p udp -j MASQUERADE'
printf '%s\n' "$OUTPUT" | grep -q -- '-A OVPN_TPROXY_UDP_FWD -s 10.231.89.0/24 -d 172.16.0.0/12 -p udp -j ACCEPT'

private_line=$(printf '%s\n' "$OUTPUT" | grep -n -- '-A OVPN_TO_SINGBOX -p udp -d 172.16.0.0/12' | head -1 | cut -d: -f1)
tproxy_line=$(printf '%s\n' "$OUTPUT" | grep -n -- '-A OVPN_TO_SINGBOX -p udp -j TPROXY' | head -1 | cut -d: -f1)
if [[ -z "$private_line" || -z "$tproxy_line" || $private_line -ge $tproxy_line ]]; then
  echo "expected private UDP bypass before generic TPROXY" >&2
  exit 1
fi

REDIRECT_OUTPUT=$(PATH="$TMP:$PATH" \
  VPNKIT_ROUTING_DRY_RUN=true \
  VPNKIT_ROUTING_MODE=redirect \
  VPNKIT_IPV6_POLICY=allow \
  bash "$ROOT/docker/vpnkit/setup-routing.sh")
if printf '%s\n' "$REDIRECT_OUTPUT" | grep -q 'OVPN_TPROXY_UDP_POST'; then
  echo "redirect mode should not install tproxy private UDP bypass chains" >&2
  exit 1
fi

TUN_OUTPUT=$(PATH="$TMP:$PATH" \
  VPNKIT_ROUTING_DRY_RUN=true \
  VPNKIT_ROUTING_MODE=tun \
  VPNKIT_IPV6_POLICY=allow \
  bash "$ROOT/docker/vpnkit/setup-routing.sh")
printf '%s\n' "$TUN_OUTPUT" | grep -q -- 'ip route replace default dev sb-tun0 table 101'
printf '%s\n' "$TUN_OUTPUT" | grep -q -- 'ip rule add from 10.231.89.0/24 table 101 priority 1000'
if printf '%s\n' "$TUN_OUTPUT" | grep -Eq 'OVPN_TO_SINGBOX|TPROXY|REDIRECT --to-ports|OVPN_REDIRECT_TO_SINGBOX'; then
  echo "tun mode should not install redirect/tproxy capture rules" >&2
  exit 1
fi

printf 'vpnkit setup-routing mode behavior ok\n'
