#!/usr/bin/env bash
set -euo pipefail

if command -v sing-box >/dev/null 2>&1; then
  sing-box version
  exit 0
fi

sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
sudo chmod a+r /etc/apt/keyrings/sagernet.asc
cat <<'SRC' | sudo tee /etc/apt/sources.list.d/sagernet.sources >/dev/null
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
SRC
sudo apt-get update
sudo apt-get install -y sing-box
sing-box version
