#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v sing-box >/dev/null 2>&1; then
  echo "sing-box missing; installing via SagerNet APT repo..."
  ./scripts/linux-d1-install-sing-box.sh
fi

./scripts/linux-d1-enable.sh
