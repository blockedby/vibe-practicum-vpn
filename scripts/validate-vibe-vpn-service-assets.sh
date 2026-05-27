#!/usr/bin/env bash
set -euo pipefail

unit="${1:-systemd/vibe-vpn.service}"
config="${2:-examples/vibe-vpn-config.yaml}"
smoke_config="${3:-examples/vibe-vpn-smoke-config.yaml}"

for path in "$unit" "$config" "$smoke_config"; do
  if [[ ! -f "$path" ]]; then
    echo "missing required file: $path" >&2
    exit 1
  fi
done

grep -q '^ExecStart=/usr/local/bin/vibe-vpn daemon --config /etc/vibe-vpn/config.yaml$' "$unit"
grep -q '^Restart=always$' "$unit"
grep -q '^RestartSec=5$' "$unit"
grep -q '^After=network-online.target$' "$unit"
grep -q '^Wants=network-online.target$' "$unit"

grep -q 'runtime: singbox' "$config"
grep -q 'sing_box_service: sing-box-vibe-router' "$config"
grep -q 'production_socks: 127.0.0.1:2080' "$config"
grep -q 'mode: failover-only' "$config"
grep -q 'interval: 30m' "$config"
grep -q 'retention: 12h' "$config"
grep -q 'https://x.com/' "$config"
grep -q 'https://rutracker.org/' "$config"
grep -q 'https://ya.ru/' "$config"
grep -q 'runtime: singbox' "$smoke_config"
grep -q 'sing_box_service: sing-box-vibe-router' "$smoke_config"
grep -q 'production_socks: 127.0.0.1:2080' "$smoke_config"
grep -q 'mode: failover-only' "$smoke_config"
grep -q 'interval: 1m' "$smoke_config"

echo "vibe-vpn service assets passed static validation"
