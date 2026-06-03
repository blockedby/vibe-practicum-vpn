#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEMPLATE="$ROOT/config/openvpn/server.tpl"

if ! grep -q '^server 10\.231\.89\.0 255\.255\.255\.0$' "$TEMPLATE"; then
  echo "expected OpenVPN server template default subnet 10.231.89.0/24" >&2
  exit 1
fi

if ! grep -q '^push "dhcp-option DNS 10\.231\.89\.1"$' "$TEMPLATE"; then
  echo "expected OpenVPN server template default DNS 10.231.89.1" >&2
  exit 1
fi

if grep -Eq '10\.89\.0\.(0|1)' "$TEMPLATE"; then
  echo "OpenVPN server template still contains old 10.89.0.0/24 defaults" >&2
  exit 1
fi

printf 'openvpn server template defaults ok\n'
