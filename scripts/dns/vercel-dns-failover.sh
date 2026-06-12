#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_ENV="${LOCAL_ENV:-$REPO_ROOT/config/private-endpoints.local.env}"
CMD="${1:-}"; shift || true
YES=0; DRY_RUN=0; WANT_TARGET=""; OVPN_IN=""; OVPN_OUT=""; SELECTED_ENDPOINT=""; LIVE_CURRENT="${MOCK_VERCEL_CURRENT:-}"

usage() {
  cat <<'USAGE'
Usage: scripts/dns/vercel-dns-failover.sh <command> [options]

Commands:
  inventory                 Validate local private endpoint inventory only.
  rank                      Rank healthy endpoints by speed from local env/fixtures.
  dns-discover              Read-only current-record summary (mockable, no mutation).
  dns-plan                  Dry-run DNS failover plan with expected-current checks.
  dns-apply --yes           Guarded DNS apply. Mock/test only here; do not run live in this task.
  dns-rollback --yes        Guarded DNS rollback. Mock/test only here; do not run live in this task.
  ovpn-endpoint             Print or rewrite OpenVPN remote endpoint line.
  smoke-plan                Print post-failover/rollback smoke checklist.

Options:
  --dry-run                 Print intended actions only.
  --yes                     Required for dns-apply and dns-rollback.
  --target NAME             Endpoint name to select (default: fastest healthy ranked endpoint).
  --current VALUE           Test/mock current DNS value; otherwise MOCK_VERCEL_CURRENT or Vercel CLI.
  --input PATH              OpenVPN profile/template to rewrite.
  --output PATH             Output path for rewritten OpenVPN profile (must not be tracked).
  --endpoint HOST           Explicit OpenVPN endpoint host; otherwise failover domain or selected endpoint.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --yes) YES=1; shift ;;
    --target) WANT_TARGET="${2:?missing --target value}"; shift 2 ;;
    --current) LIVE_CURRENT="${2:?missing --current value}"; shift 2 ;;
    --input) OVPN_IN="${2:?missing --input value}"; shift 2 ;;
    --output) OVPN_OUT="${2:?missing --output value}"; shift 2 ;;
    --endpoint) SELECTED_ENDPOINT="${2:?missing --endpoint value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 2; }; }
fail() { echo "ERROR: $*" >&2; exit 2; }
redact() { local v="$1"; [[ -z "$v" ]] && { echo "<unset>"; return; }; printf '<redacted:%s>' "$(printf '%s' "$v" | wc -c | tr -d ' ')"; }

load_env() {
  if [[ ! -r "$LOCAL_ENV" ]]; then
    fail "missing $LOCAL_ENV; copy config/private-endpoints.example.env to config/private-endpoints.local.env and fill operator-local values before live planning"
  fi
  set -a
  # shellcheck disable=SC1090
  . "$LOCAL_ENV"
  set +a
}

require_env() { for k in "$@"; do [[ -n "${!k:-}" ]] || fail "missing required env $k in $LOCAL_ENV"; done; }

endpoint_names() {
  printf '%s\n' ${VPN_FAILOVER_ENDPOINTS:-vibe-practicum moscow-tiger}
}

env_key() { printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_' ; }
endpoint_value() { local key; key="$(env_key "$1")_PUBLIC_ENDPOINT"; printf '%s' "${!key:-}"; }
endpoint_health() { local key; key="$(env_key "$1")_HEALTH"; printf '%s' "${!key:-healthy}"; }
endpoint_latency() { local key; key="$(env_key "$1")_LATENCY_MS"; printf '%s' "${!key:-999999}"; }

rank() {
  load_env
  local rows=() name ep health latency order=0 healthy=0
  while read -r name; do
    [[ -z "$name" ]] && continue
    ep="$(endpoint_value "$name")"
    [[ -n "$ep" ]] || fail "missing endpoint value for $name ($(env_key "$name")_PUBLIC_ENDPOINT)"
    health="$(endpoint_health "$name")"
    latency="$(endpoint_latency "$name")"
    if [[ "$health" == "healthy" || "$health" == "ok" ]]; then
      healthy=$((healthy+1))
      rows+=("$(printf '%012d:%012d:%s:%s' "$latency" "$order" "$name" "$ep")")
    fi
    order=$((order+1))
  done < <(endpoint_names)
  (( healthy > 0 )) || fail "no healthy endpoints available; refusing DNS/OpenVPN mutation"
  printf '%s\n' "${rows[@]}" | sort -t: -k1,1n -k2,2n | awk -F: '{printf "%s latency_ms=%s endpoint=%s\n", $3, $1+0, "<redacted:" length($4) ">"}'
}

selected_target() {
  if [[ -n "$WANT_TARGET" ]]; then printf '%s' "$WANT_TARGET"; return; fi
  rank | awk 'NR==1 {print $1}'
}

current_dns() {
  if [[ -n "$LIVE_CURRENT" ]]; then printf '%s' "$LIVE_CURRENT"; return; fi
  require_env VERCEL_TOKEN VPN_FAILOVER_DOMAIN VPN_DNS_RECORD_NAME
  if [[ "${VERCEL_DNS_CURRENT_CMD:-}" ]]; then eval "$VERCEL_DNS_CURRENT_CMD"; return; fi
  fail "no mocked/current DNS value available; set MOCK_VERCEL_CURRENT or VERCEL_DNS_CURRENT_CMD for read-only discovery"
}

dns_summary() {
  load_env
  require_env VPN_FAILOVER_DOMAIN VPN_DNS_RECORD_NAME VPN_DNS_EXPECTED_CURRENT VPN_DNS_ROLLBACK_TARGET VPN_DNS_TTL
  local cur target ep
  cur="$(current_dns)"
  target="$(selected_target)"
  ep="$(endpoint_value "$target")"; [[ -n "$ep" ]] || fail "target $target has no endpoint value"
  cat <<EOF
record=$(redact "${VPN_FAILOVER_DOMAIN}.${VPN_DNS_RECORD_NAME}")
current=$(redact "$cur")
expected_current=$(redact "$VPN_DNS_EXPECTED_CURRENT")
proposed_target=$target
proposed_value=$(redact "$ep")
rollback_target=$(redact "$VPN_DNS_ROLLBACK_TARGET")
ttl=$VPN_DNS_TTL
mode=read-only/dry-run unless dns-apply or dns-rollback is invoked with --yes
EOF
}

assert_expected() {
  local cur="$1" expect="$2" label="$3"
  [[ -n "$expect" ]] || fail "missing $label expected-current value"
  [[ "$cur" == "$expect" ]] || fail "current DNS does not match $label expected-current; refusing mutation"
}

dns_apply() {
  load_env; require_env VPN_DNS_EXPECTED_CURRENT VERCEL_TOKEN VPN_FAILOVER_DOMAIN VPN_DNS_RECORD_NAME
  (( YES == 1 )) || fail "dns-apply requires explicit --yes"
  local cur target ep
  cur="$(current_dns)"; assert_expected "$cur" "$VPN_DNS_EXPECTED_CURRENT" apply
  target="$(selected_target)"; ep="$(endpoint_value "$target")"; [[ -n "$ep" ]] || fail "target $target has no endpoint value"
  if (( DRY_RUN == 1 )) || [[ "${MOCK_VERCEL_APPLY:-}" == "1" ]]; then
    echo "DRY-RUN apply target=$target value=$(redact "$ep") expected_current=$(redact "$cur")"
    return 0
  fi
  fail "live DNS apply is intentionally disabled unless an operator wires an approved Vercel mutation command outside this task"
}

dns_rollback() {
  load_env; require_env VPN_DNS_FAILED_OVER_EXPECTED_CURRENT VPN_DNS_ROLLBACK_TARGET VERCEL_TOKEN VPN_FAILOVER_DOMAIN VPN_DNS_RECORD_NAME
  (( YES == 1 )) || fail "dns-rollback requires explicit --yes"
  local cur; cur="$(current_dns)"; assert_expected "$cur" "$VPN_DNS_FAILED_OVER_EXPECTED_CURRENT" rollback
  if (( DRY_RUN == 1 )) || [[ "${MOCK_VERCEL_APPLY:-}" == "1" ]]; then
    echo "DRY-RUN rollback value=$(redact "$VPN_DNS_ROLLBACK_TARGET") expected_current=$(redact "$cur")"
    return 0
  fi
  fail "live DNS rollback is intentionally disabled unless an operator wires an approved Vercel mutation command outside this task"
}

ovpn_endpoint() {
  load_env
  local endpoint="${SELECTED_ENDPOINT:-${VPN_FAILOVER_DOMAIN:-}}"
  if [[ -z "$endpoint" ]]; then endpoint="$(endpoint_value "$(selected_target)")"; fi
  [[ -n "$endpoint" ]] || fail "no OpenVPN endpoint available"
  local port="${OPENVPN_PORT:-1194}"
  if [[ -z "$OVPN_IN" ]]; then
    printf 'remote %s %s udp\n' "$endpoint" "$port"
    return
  fi
  [[ -r "$OVPN_IN" ]] || fail "input profile/template is not readable"
  [[ -n "$OVPN_OUT" ]] || fail "--output is required when --input is used"
  case "$OVPN_OUT" in "$REPO_ROOT"/*|"$REPO_ROOT"/*) ;; *) ;; esac
  if git -C "$REPO_ROOT" ls-files --error-unmatch "$OVPN_OUT" >/dev/null 2>&1; then fail "refusing to overwrite tracked OpenVPN output path"; fi
  mkdir -p "$(dirname "$OVPN_OUT")"
  awk -v h="$endpoint" -v p="$port" 'BEGIN{done=0} /^remote[[:space:]]+/ && !done {print "remote " h " " p " udp"; done=1; next} {print} END{if(!done) print "remote " h " " p " udp"}' "$OVPN_IN" > "$OVPN_OUT"
  echo "wrote OpenVPN profile with endpoint=$(redact "$endpoint") to untracked output path"
}

smoke_plan() {
  cat <<'EOF'
Post-failover smoke checklist (public-safe summaries only):
1. DNS propagation: compare resolvers for the failover record; record only redacted match/mismatch and TTL timing.
2. Endpoint health: run endpoint health probes for selected and rollback targets; do not store concrete endpoint values.
3. OpenVPN/client smoke: generate/rewrite profile into a temp or gitignored output directory, start only isolated throwaway containers/projects/ports/networks/volumes/state; never restart/recreate/adopt production vpnkit.
4. Routing smoke: verify required public health URLs through the client path; store pass/fail summary only.
5. Rollback smoke: dry-run rollback, verify rollback target health, then future approved rollback apply with --yes and expected-current symmetry.
EOF
}

case "$CMD" in
  inventory) load_env; require_env VPN_FAILOVER_ENDPOINTS VPN_FAILOVER_DOMAIN VPN_DNS_RECORD_NAME; echo "inventory ok: domain=$(redact "${VPN_FAILOVER_DOMAIN}") endpoints=$(endpoint_names | wc -l | tr -d ' ')" ;;
  rank) rank ;;
  dns-discover|dns-plan) dns_summary ;;
  dns-apply) dns_apply ;;
  dns-rollback) dns_rollback ;;
  ovpn-endpoint) ovpn_endpoint ;;
  smoke-plan) smoke_plan ;;
  ""|-h|--help) usage ;;
  *) echo "unknown command: $CMD" >&2; usage >&2; exit 2 ;;
esac
