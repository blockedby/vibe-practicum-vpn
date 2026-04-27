#!/usr/bin/env bash
set -euo pipefail

SERVICE="${SERVICE:-sing-box-vibe-local.service}"

sudo systemctl disable --now "$SERVICE" 2>/dev/null || true
sudo ip link delete vibe-tun0 2>/dev/null || true

echo "D1 local sing-box disabled. Tailscale remains connected without exit-node unless you enable it manually."
