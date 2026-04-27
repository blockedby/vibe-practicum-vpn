#!/usr/bin/env bash
set -euo pipefail

TABLE="${TABLE:-52}"
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

for cidr in "${ROUTES[@]}"; do
  sudo ip route del "$cidr" table "$TABLE" 2>/dev/null || true
  echo "removed Steam/Dota direct route: $cidr table $TABLE"
done
