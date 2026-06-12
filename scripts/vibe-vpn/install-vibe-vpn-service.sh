#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: install-vibe-vpn-service.sh --binary PATH [--config PATH] [--unit PATH]

Installs vibe-vpn service assets on the current host only. It does not run ssh,
scp, systemctl enable, or systemctl start. Run as root or via sudo.
USAGE
}

binary=""
config=""
unit="systemd/vibe-vpn.service"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --binary) binary="${2:?missing --binary value}"; shift 2 ;;
    --config) config="${2:?missing --config value}"; shift 2 ;;
    --unit) unit="${2:?missing --unit value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$binary" ]]; then
  echo "--binary is required" >&2
  usage >&2
  exit 2
fi
if [[ ! -f "$binary" ]]; then
  echo "binary not found: $binary" >&2
  exit 1
fi
if [[ ! -f "$unit" ]]; then
  echo "unit not found: $unit" >&2
  exit 1
fi

install -d -o root -g root -m 700 /etc/vibe-vpn /var/lib/vibe-vpn /var/log/vibe-vpn
install -o root -g root -m 755 "$binary" /usr/local/bin/vibe-vpn
install -o root -g root -m 644 "$unit" /etc/systemd/system/vibe-vpn.service
if [[ -n "$config" ]]; then
  if [[ ! -f "$config" ]]; then
    echo "config not found: $config" >&2
    exit 1
  fi
  install -o root -g root -m 600 "$config" /etc/vibe-vpn/config.yaml
fi

cat <<'NEXT'
Installed service files on this host.
Next manual operator steps, when ready:
  sudo systemctl daemon-reload
  sudo systemctl enable --now vibe-vpn
  sudo systemctl status vibe-vpn
  sudo journalctl -u vibe-vpn -f
NEXT
