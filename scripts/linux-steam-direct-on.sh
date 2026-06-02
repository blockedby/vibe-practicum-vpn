#!/usr/bin/env bash
set -euo pipefail

# Linux client-side Steam/Dota bypass for Tailscale exit-node.
# Adds more-specific Valve/Steam routes to Tailscale table 52 via the local LAN gateway.
# This keeps normal traffic on the Tailscale exit-node while Steam/Dota game traffic goes local-direct.

TABLE="${TABLE:-52}"

mapfile -t DEFAULT_FIELDS < <(ip -4 route show default table main | head -1 | tr ' ' '\n')
GW=""
DEV=""
for i in "${!DEFAULT_FIELDS[@]}"; do
  case "${DEFAULT_FIELDS[$i]}" in
    via) GW="${DEFAULT_FIELDS[$((i+1))]}" ;;
    dev) DEV="${DEFAULT_FIELDS[$((i+1))]}" ;;
  esac
done

if [[ -z "$GW" || -z "$DEV" ]]; then
  echo "Could not detect main default gateway/device" >&2
  ip -4 route show default table main >&2
  exit 1
fi

# Observed Dota/Steam destinations plus common Valve network blocks.
# Keep this list conservative and specific; do not bypass huge unrelated ranges.
ROUTES=(
  103.10.124.0/24
  146.66.152.0/21
  155.133.224.0/19
  162.254.192.0/21
  185.5.160.0/22
  185.25.180.0/22
  192.69.96.0/22
  205.196.6.0/24
  208.64.200.0/22
)

echo "Using local gateway $GW dev $DEV, table $TABLE"
for cidr in "${ROUTES[@]}"; do
  sudo ip route replace "$cidr" via "$GW" dev "$DEV" table "$TABLE"
  echo "direct Steam/Dota route: $cidr via $GW dev $DEV table $TABLE"
done

echo
ip -4 route show table "$TABLE" | grep -E '103\.10\.124|146\.66\.15|155\.133|162\.254|185\.5|185\.25|192\.69|205\.196\.6|208\.64\.20' || true
