#!/usr/bin/env bash
set -Eeuo pipefail

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"
LOG_FILE=""
KEEP_ARTIFACTS=0
BUILD=1
CLEANUP_IMAGES=1

usage() {
  cat <<'EOF'
Usage: scripts/vpnkit-vibe-vpn-e2e.sh [options]

Options:
  --run-id ID                 Shell-safe run id (default: UTC timestamp + random)
  --log-file PATH             Log file (default: logs/vpnkit-vibe-vpn-e2e/<run-id>.log)
  --keep-artifacts            Keep containers/volumes/images on exit
  --no-build                  Skip docker compose build
  --cleanup-images            Remove local e2e-built images during cleanup (default on success)
  --no-cleanup-images         Keep local e2e-built images
  -h, --help                  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id) RUN_ID=${2:?missing --run-id value}; shift 2 ;;
    --log-file) LOG_FILE=${2:?missing --log-file value}; shift 2 ;;
    --keep-artifacts) KEEP_ARTIFACTS=1; shift ;;
    --no-build) BUILD=0; shift ;;
    --cleanup-images) CLEANUP_IMAGES=1; shift ;;
    --no-cleanup-images) CLEANUP_IMAGES=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! "$RUN_ID" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  echo "run id must contain only letters, numbers, dot, underscore, and dash: $RUN_ID" >&2
  exit 2
fi
LOG_FILE=${LOG_FILE:-logs/vpnkit-vibe-vpn-e2e/$RUN_ID.log}
mkdir -p "$(dirname "$LOG_FILE")"
PROJECT="vpnkit-vibe-vpn-e2e-$RUN_ID"
PROJECT=${PROJECT//./-}
TMP_OVERRIDE="$(mktemp -t vpnkit-vibe-vpn-e2e-$RUN_ID.XXXXXX.yml)"
STATUS=1

redact_stream() {
  sed -E \
    -e 's#vless://[^[:space:]]+#vless://[redacted]#g' \
    -e 's#(https?://)[^[:space:]]*(token|sub|subscription|api_key|apikey|key)[^[:space:]]*#\1[redacted-url]#ig' \
    -e 's/([0-9a-f]{8}-[0-9a-f-]{27,})/[redacted-uuid]/ig' \
    -e 's/(private[_-]?key[":= ]+)[^", ]+/\1[redacted]/ig' \
    -e 's/(password[":= ]+)[^", ]+/\1[redacted]/ig'
}

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
run() { log "+ $*"; "$@"; }
dc() { docker compose -p "$PROJECT" -f docker-compose.yml -f "$TMP_OVERRIDE" "$@"; }

cleanup() {
  local exit_status=$?
  STATUS=$exit_status
  if [[ $KEEP_ARTIFACTS -eq 1 ]]; then
    log "keeping artifacts for project $PROJECT"
    log "inspect with: docker compose -p $PROJECT -f docker-compose.yml -f $TMP_OVERRIDE ps"
    log "cleanup with: docker compose -p $PROJECT -f docker-compose.yml -f $TMP_OVERRIDE down --remove-orphans --volumes${CLEANUP_IMAGES:+ --rmi local}"
    return $exit_status
  fi
  if [[ $exit_status -eq 0 ]]; then
    if [[ $CLEANUP_IMAGES -eq 1 ]]; then
      dc down --remove-orphans --volumes --rmi local || true
    else
      dc down --remove-orphans --volumes || true
    fi
    rm -f "$TMP_OVERRIDE"
  else
    log "failure: preserving artifacts by default for project $PROJECT"
    log "cleanup with: docker compose -p $PROJECT -f docker-compose.yml -f $TMP_OVERRIDE down --remove-orphans --volumes --rmi local"
  fi
  return $exit_status
}
trap cleanup EXIT

exec > >(tee "$LOG_FILE" | redact_stream) 2>&1
log "run id: $RUN_ID"
log "compose project: $PROJECT"
log "log file: $LOG_FILE"

cat > "$TMP_OVERRIDE" <<'YAML'
services:
  vpnkit:
    ports: !reset []
  ovpn-client-test:
    depends_on:
      vpnkit:
        condition: service_started
YAML

for path in \
  secrets/vps/rendered/openvpn/server.conf \
  secrets/vps/rendered/sing-box/config.json \
  secrets/vps/openvpn/client/test-client.ovpn \
  secrets/vps/rendered/vibe-vpn/config.yaml; do
  if [[ ! -r "$path" ]]; then
    echo "missing required rendered input: $path" >&2
    echo "Run scripts/vpnkit-render-local-configs.sh after preparing gitignored secrets/vps inputs." >&2
    exit 1
  fi
done
if [[ ! -r secrets/vps/rendered/vibe-vpn/sub_url ]]; then
  echo "missing required vibe-vpn subscription input: secrets/vps/rendered/vibe-vpn/sub_url" >&2
  echo "Create secrets/vps/vibe-vpn/sub_url (or subscription.url/subscription.txt) and rerun scripts/vpnkit-render-local-configs.sh." >&2
  exit 1
fi

run docker compose -p "$PROJECT" -f docker-compose.yml -f "$TMP_OVERRIDE" config >/dev/null
if [[ $BUILD -eq 1 ]]; then
  run dc build vpnkit ovpn-client-test
fi
run dc up -d vpnkit
run dc exec -T vpnkit /usr/local/bin/vibe-vpn doctor --config /etc/vibe-vpn/config.yaml
run dc exec -T vpnkit /usr/local/bin/vibe-vpn test --config /etc/vibe-vpn/config.yaml --limit-kib 64 --max 2
run dc exec -T vpnkit /usr/local/bin/sing-box check -c /etc/sing-box/config.json
run dc --profile test up --abort-on-container-exit --exit-code-from ovpn-client-test ovpn-client-test
EVIDENCE="logs/vpnkit-vibe-vpn-e2e/$RUN_ID-evidence.txt"
COMPOSE_PROJECT_NAME="$PROJECT" scripts/vpnkit-collect-evidence.sh "$EVIDENCE" || true
log "evidence: $EVIDENCE"
log "success"
