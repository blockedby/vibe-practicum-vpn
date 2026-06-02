#!/usr/bin/env bash
set -eu

# Read-only status checks for the Hysteria 2 MVP. This script does not modify
# Docker, firewall, tailscaled, sing-box, routing rules, or iptables.

CONTAINER_NAME="${CONTAINER_NAME:-vibe-hy2-mvp}"
STATE_DIR="${STATE_DIR:-/opt/vibe-hy2-mvp}"
ENV_FILE="$STATE_DIR/state.env"
HY2_PUBLIC_PORT="${HY2_PUBLIC_PORT:-18443}"
HY2_LISTEN_PORT="${HY2_LISTEN_PORT:-$HY2_PUBLIC_PORT}"
SING_BOX_SOCKS_ADDR="${SING_BOX_SOCKS_ADDR:-192.0.2.10:2080}"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi

section() {
  printf '\n== %s ==\n' "$1"
}

run_or_warn() {
  if command -v "$1" >/dev/null 2>&1; then
    "$@" || true
  else
    echo "WARN: command not found: $1"
  fi
}

section "Hysteria 2 MVP configuration"
echo "Container: $CONTAINER_NAME"
echo "State dir: $STATE_DIR"
echo "Server config: $STATE_DIR/server.yaml"
echo "Published UDP: ${HY2_PUBLIC_PORT}; Hysteria listens on ${HY2_LISTEN_PORT}"
echo "Required SOCKS outbound: $SING_BOX_SOCKS_ADDR"
[ -f "$STATE_DIR/server.yaml" ] && echo "server.yaml exists" || echo "server.yaml missing"
[ -f "$STATE_DIR/server.crt" ] && echo "server.crt exists" || echo "server.crt missing"
[ -f "$STATE_DIR/server.key" ] && echo "server.key exists" || echo "server.key missing"
[ -n "${HY2_CERT_PIN_SHA256:-}" ] && echo "pinSHA256: $HY2_CERT_PIN_SHA256"

section "Docker container"
if command -v docker >/dev/null 2>&1; then
  docker ps -a --filter "name=^/${CONTAINER_NAME}$"
  docker port "$CONTAINER_NAME" 2>/dev/null || true
  docker inspect "$CONTAINER_NAME" \
    --format 'Name={{.Name}} Status={{.State.Status}} NetworkMode={{.HostConfig.NetworkMode}} CapAdd={{json .HostConfig.CapAdd}} PortBindings={{json .HostConfig.PortBindings}}' 2>/dev/null || true
else
  echo "WARN: docker not found"
fi

section "UDP listener"
run_or_warn ss -lunp | grep -E "(^|:)${HY2_PUBLIC_PORT}[[:space:]]" || true

section "Firewall"
if command -v ufw >/dev/null 2>&1; then
  ufw status verbose || true
else
  echo "WARN: ufw not found"
fi

section "Guardrail services (read-only)"
if command -v systemctl >/dev/null 2>&1; then
  systemctl is-active tailscaled.service || true
  systemctl is-active sing-box-vibe-router.service || true
  systemctl --no-pager --plain status tailscaled.service sing-box-vibe-router.service | sed -n '1,80p' || true
else
  echo "WARN: systemctl not found"
fi

section "Routing rules (read-only)"
run_or_warn ip rule show

section "Relevant iptables markers (read-only)"
if command -v iptables-save >/dev/null 2>&1; then
  iptables-save | grep -E 'tailscale0|ts-|VIBE_ROUTER_PIXEL|vibe-router-pixel|sing-box' || true
else
  echo "WARN: iptables-save not found"
fi

section "Recent container logs"
if command -v docker >/dev/null 2>&1; then
  docker logs --tail 80 "$CONTAINER_NAME" 2>&1 || true
fi
