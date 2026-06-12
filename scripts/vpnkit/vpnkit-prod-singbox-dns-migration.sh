#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Migrate production vpnkit sing-box rendered config to the tracked new DNS schema.

Usage:
  scripts/vpnkit/vpnkit-prod-singbox-dns-migration.sh verify <ssh-host> [<ssh-host> ...]
  scripts/vpnkit/vpnkit-prod-singbox-dns-migration.sh deploy --yes <ssh-host> [<ssh-host> ...]

Safety:
- Prints only sanitized status labels; do not pass raw private endpoint values in logs.
- Discovers the vpnkit Compose working directory from Docker labels.
- Mutates only the discovered vpnkit Compose service on each host in deploy mode.
- In deploy mode, backs up .env and current runtime sing-box config under the remote workdir,
  tags the current image with a rollback tag when possible, renders the new config, checks it
  without deprecated DNS compatibility env, updates the persisted runtime config, recreates vpnkit,
  and runs a runtime smoke check.
USAGE
}

mode=${1:-}
if [[ -z "$mode" || "$mode" == "-h" || "$mode" == "--help" ]]; then
  usage
  exit 0
fi
shift

yes=0
if [[ "${1:-}" == "--yes" ]]; then
  yes=1
  shift
fi

case "$mode" in
  verify) ;;
  deploy) [[ "$yes" == 1 ]] || { echo "deploy requires --yes" >&2; exit 2; } ;;
  *) echo "unsupported mode: $mode" >&2; usage >&2; exit 2 ;;
esac

if [[ $# -lt 1 ]]; then
  echo "missing ssh host(s)" >&2
  usage >&2
  exit 2
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
paths=(
  config/sing-box/config.json.template
  config/sing-box/config.tun.json.template
  docker-compose.yml
  scripts/vpnkit/vpnkit-render-local-configs.sh
)

redact() {
  sed -E \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' \
    -e 's#vless://[^[:space:]]+#vless://[redacted]#g' \
    -e 's#(server|uuid|password|private_key|short_id|public_key|server_name)[=: ][^, ]+#\1=<redacted>#ig'
}

remote_payload='set -euo pipefail
mode=$1
archive=${2:-}
stamp=$(date -u +%Y%m%dT%H%M%SZ)
container=$(docker ps --filter label=com.docker.compose.service=vpnkit --format "{{.ID}}" | awk "NR==1{print}")
if [ -z "${container:-}" ]; then
  container=$(docker ps --filter name=vpnkit --format "{{.ID}}" | awk "NR==1{print}")
fi
[ -n "${container:-}" ] || { echo "container=missing"; exit 10; }
workdir=$(docker inspect "$container" --format "{{index .Config.Labels \"com.docker.compose.project.working_dir\"}}")
service=$(docker inspect "$container" --format "{{index .Config.Labels \"com.docker.compose.service\"}}")
project=$(docker inspect "$container" --format "{{index .Config.Labels \"com.docker.compose.project\"}}")
[ -n "$workdir" ] || { echo "workdir=missing"; exit 11; }
[ "$service" = "vpnkit" ] || service=vpnkit
cd "$workdir"
echo "workdir=discovered service=$service project=${project:-unknown}"

check_container() {
  cid=$1
  docker exec "$cid" sh -lc '\''set -eu
    if env | grep -Eq "^ENABLE_DEPRECATED_(LEGACY_DNS_SERVERS|MISSING_DOMAIN_RESOLVER)="; then echo deprecated_env=present; exit 21; else echo deprecated_env=absent; fi
    sing-box check -c /var/lib/vpnkit/sing-box/config.json >/tmp/vpnkit-singbox-check.out 2>&1 && echo singbox_check=ok || { echo singbox_check=fail; tail -20 /tmp/vpnkit-singbox-check.out; exit 22; }
    mode=$(printenv VPNKIT_ROUTING_MODE 2>/dev/null || true); [ -n "$mode" ] || mode=unknown; echo routing_mode=$mode
    pgrep openvpn >/dev/null && echo openvpn=up || { echo openvpn=down; exit 23; }
    ip addr show tun0 >/dev/null 2>&1 && echo tun0=present || { echo tun0=missing; exit 24; }
    pgrep sing-box >/dev/null && echo singbox=up || { echo singbox=down; exit 25; }
    if [ "$mode" = tun ]; then
      iface=$(printenv SINGBOX_TUN_IFACE 2>/dev/null || echo sb-tun0)
      table=$(printenv SINGBOX_TUN_TABLE 2>/dev/null || echo 101)
      ip addr show "$iface" >/dev/null 2>&1 && echo sb_tun0=present || { echo sb_tun0=missing; exit 26; }
      ip rule show | grep -q "lookup $table" && echo policy_rule=ok || { echo policy_rule=missing; exit 27; }
      ip route show table "$table" | grep -q "^default .* dev $iface" && echo route_table=ok || { echo route_table=missing; exit 28; }
    fi
    if ss -lunp 2>/dev/null | grep -q ":1194"; then echo udp_1194_listener=ok; else echo udp_1194_listener=missing; exit 29; fi
  '\''
  docker inspect "$cid" --format "udp_1194={{if (index .NetworkSettings.Ports \"1194/udp\")}}mapped{{else}}missing{{end}}"
}

if [ "$mode" = verify ]; then
  check_container "$container"
  exit 0
fi

rollback_dir="$workdir/.rollback/vpnkit/singbox-dns-$stamp"
mkdir -p "$rollback_dir"
[ -f .env ] && cp .env "$rollback_dir/env" || true
docker cp "$container:/var/lib/vpnkit/sing-box/config.json" "$rollback_dir/runtime-config.json" >/dev/null 2>&1 || true
image=$(docker inspect "$container" --format "{{.Config.Image}}" 2>/dev/null || true)
if [ -n "$image" ]; then
  docker image inspect "$image" >/dev/null 2>&1 && docker tag "$image" "vpnkit-rollback:$stamp" || true
fi
echo "rollback=prepared tag=vpnkit-rollback:$stamp env_backup=.rollback/vpnkit/singbox-dns-$stamp/env runtime_backup=.rollback/vpnkit/singbox-dns-$stamp/runtime-config.json"

[ -n "$archive" ] || { echo "archive=missing"; exit 12; }
tar -xf "$archive" -C "$workdir"
rm -f "$archive"
# Preserve private env values; source only to select render mode and overrides.
set -a
[ -r .env ] && . ./.env
set +a
if scripts/vpnkit/vpnkit-render-local-configs.sh >/tmp/vpnkit-render.out 2>/tmp/vpnkit-render.err; then
  echo "render=full"
else
  echo "render=singbox-only-fallback"
  python3 - "$rollback_dir/runtime-config.json" "${VPNKIT_ROUTING_MODE:-redirect}" <<'PYREMOTE'
import json, pathlib, sys
src = pathlib.Path(sys.argv[1])
mode = (sys.argv[2] or "redirect").lower()
template = pathlib.Path("config/sing-box/config.tun.json.template" if mode == "tun" else "config/sing-box/config.json.template")
out = pathlib.Path("secrets/vps/rendered/sing-box/config.json")
data = json.load(open(src))
selected = [o for o in data.get("outbounds", []) if o.get("tag") == "selected-native-out"]
if not selected:
    raise SystemExit("selected-native-out outbound not found in runtime backup")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(template.read_text().replace("{{SELECTED_NATIVE_OUT_JSON}}", json.dumps(selected[0], indent=4)))
PYREMOTE
  chmod 600 secrets/vps/rendered/sing-box/config.json
fi
if grep -q \"address\"[[:space:]]*:[[:space:]]*\"tls:// secrets/vps/rendered/sing-box/config.json; then
  echo "rendered_schema=legacy"
  exit 30
fi
if ! grep -q \"default_domain_resolver\" secrets/vps/rendered/sing-box/config.json; then
  echo "rendered_domain_resolver=missing"
  exit 31
fi
# Validate with the current production binary and without deprecated DNS compatibility env.
docker run --rm -v "$workdir/secrets/vps/rendered/sing-box/config.json:/config.json:ro" --entrypoint sh "$image" -lc '\''env -u ENABLE_DEPRECATED_LEGACY_DNS_SERVERS -u ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER sing-box check -c /config.json >/tmp/check.out 2>&1 || { tail -20 /tmp/check.out; exit 1; }'\''
echo "rendered_check=ok"

docker cp "$workdir/secrets/vps/rendered/sing-box/config.json" "$container:/var/lib/vpnkit/sing-box/config.json" >/dev/null
if command -v docker compose >/dev/null 2>&1; then
  docker compose up -d --build "$service" >/tmp/vpnkit-compose-up.out
else
  docker-compose up -d --build "$service" >/tmp/vpnkit-compose-up.out
fi
sleep 5
new_container=$(docker ps --filter label=com.docker.compose.service=vpnkit --format "{{.ID}}" | awk "NR==1{print}")
[ -n "${new_container:-}" ] || { echo "container_after=missing"; exit 40; }
echo "deploy=recreated"
check_container "$new_container"
'

for host in "$@"; do
  echo "== $host $mode =="
  if [[ "$mode" == deploy ]]; then
    remote_archive="/tmp/vpnkit-singbox-dns-migration-$(date -u +%Y%m%dT%H%M%SZ)-$$.tar"
    tar -C "$repo_root" -cf - "${paths[@]}" | ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" "cat > '$remote_archive'"
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" "bash -s -- deploy '$remote_archive'" <<<"$remote_payload" 2>&1 | redact
  else
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" "bash -s -- verify" <<<"$remote_payload" 2>&1 | redact
  fi
done
