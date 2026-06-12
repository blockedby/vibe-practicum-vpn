#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Production-safe vpnkit Docker/Compose deploy helper.

Usage:
  scripts/vpnkit-prod-deploy.sh plan --target-ref <ref> <ssh-host> [<ssh-host> ...]
  scripts/vpnkit-prod-deploy.sh dry-run --target-ref <ref> <ssh-host> [<ssh-host> ...]
  scripts/vpnkit-prod-deploy.sh deploy --yes --target-ref <ref> <ssh-host> [<ssh-host> ...]
  scripts/vpnkit-prod-deploy.sh rollback --yes [--rollback-id <id-or-path>] <ssh-host> [<ssh-host> ...]
  scripts/vpnkit-prod-deploy.sh verify <ssh-host> [<ssh-host> ...]

Safety:
- plan/dry-run print the bounded remote plan only; they do not run remote Docker/Compose mutation.
- deploy and rollback refuse unless --yes is passed.
- hosts are supplied explicitly or by VPNKIT_PROD_DEPLOY_HOSTS; keep real values in
  config/private-endpoints.local.env, never in tracked files.
- remote Compose workdir/service/container are discovered from Docker/Compose labels or
  approved overrides: VPNKIT_PROD_WORKDIR, VPNKIT_PROD_SERVICE, VPNKIT_PROD_CONTAINER.
- output is redacted and remote commands use bounded timeouts.
USAGE
}

redact() {
  sed -E \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' \
    -e 's#(vless|trojan|ss|vmess)://[^[:space:]]+#\1://[redacted]#g' \
    -e 's#(password|passwd|token|secret|private[_-]?key|uuid|short[_-]?id|server_name|server|endpoint)[=: ][^[:space:],;]+#\1=<redacted>#ig' \
    -e 's#-----BEGIN [^-]+-----.*-----END [^-]+-----#[redacted-pem]#g'
}

die() { echo "error: $*" >&2; exit 2; }

mode=${1:-}
[[ -n "$mode" && "$mode" != "-h" && "$mode" != "--help" ]] || { usage; exit 0; }
shift

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
timeout_bin=${VPNKIT_PROD_DEPLOY_TIMEOUT_BIN:-timeout}
ssh_timeout=${VPNKIT_PROD_SSH_TIMEOUT:-12}
remote_timeout=${VPNKIT_PROD_REMOTE_CMD_TIMEOUT:-900}
ssh_cmd=${VPNKIT_PROD_SSH_CMD:-ssh}
scp_cmd=${VPNKIT_PROD_SCP_CMD:-scp}
yes=0
target_ref=""
rollback_id=""
hosts=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) yes=1; shift ;;
    --target-ref) target_ref=${2:-}; [[ -n "$target_ref" ]] || die "--target-ref requires a value"; shift 2 ;;
    --rollback-id) rollback_id=${2:-}; [[ -n "$rollback_id" ]] || die "--rollback-id requires a value"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    --*) die "unsupported option: $1" ;;
    *) hosts+=("$1"); shift ;;
  esac
done

if [[ ${#hosts[@]} -eq 0 && -n "${VPNKIT_PROD_DEPLOY_HOSTS:-}" ]]; then
  # shellcheck disable=SC2206
  hosts=(${VPNKIT_PROD_DEPLOY_HOSTS})
fi
[[ ${#hosts[@]} -gt 0 ]] || die "missing ssh host(s)"

case "$mode" in
  plan|dry-run) [[ -n "$target_ref" ]] || die "$mode requires --target-ref" ;;
  deploy) [[ "$yes" == 1 ]] || die "deploy requires --yes"; [[ -n "$target_ref" ]] || die "deploy requires --target-ref" ;;
  rollback) [[ "$yes" == 1 ]] || die "rollback requires --yes" ;;
  verify) ;;
  *) die "unsupported mode: $mode" ;;
esac
[[ -z "$target_ref" || "$target_ref" =~ ^[A-Za-z0-9._/@:+-]+$ ]] || die "target ref contains unsupported characters"
[[ -z "$rollback_id" || "$rollback_id" =~ ^[A-Za-z0-9._/@:+-]+$ ]] || die "rollback id contains unsupported characters"

remote_script='set -euo pipefail
mode=$1
target_ref=${2:-}
rollback_id=${3:-}
stamp=$(date -u +%Y%m%dT%H%M%SZ)
timeout_cmd=${VPNKIT_PROD_REMOTE_TIMEOUT_BIN:-timeout}
run_timeout=${VPNKIT_PROD_REMOTE_INNER_TIMEOUT:-600}
compose_bin=""
log() { printf "%s\n" "$*"; }
run_bounded() { "$timeout_cmd" "$run_timeout" "$@"; }
find_compose() { if docker compose version >/dev/null 2>&1; then compose_bin="docker compose"; elif command -v docker-compose >/dev/null 2>&1; then compose_bin="docker-compose"; else log compose=missing; return 20; fi; }
docker_label() {
  key=$1
  value=$(docker inspect "$container" --format "{{index .Config.Labels \"$key\"}}" 2>/dev/null || true)
  if [ "$value" != "<no value>" ]; then printf "%s\n" "$value"; fi
}
infer_workdir_from_mounts() {
  docker inspect "$container" --format "{{range .Mounts}}{{println .Source \"->\" .Destination}}{{end}}" 2>/dev/null |
  while read -r mount_src _arrow mount_dest; do
    case "$mount_dest" in
      /etc/openvpn|/etc/sing-box|/etc/vibe-vpn)
        case "$mount_src" in
          */secrets/vps/rendered/openvpn|*/secrets/vps/rendered/sing-box|*/secrets/vps/rendered/vibe-vpn)
            root=${mount_src%/secrets/vps/rendered/*}
            if [ -d "$root" ] && { [ -f "$root/docker-compose.yml" ] || [ -f "$root/docker-compose.yaml" ] || [ -f "$root/compose.yaml" ] || [ -f "$root/compose.yml" ]; }; then
              printf "%s\n" "$root"
              break
            fi
            ;;
        esac
        ;;
    esac
  done
}
discover() {
  container=${VPNKIT_PROD_CONTAINER:-}
  if [ -z "${container:-}" ]; then
    container=$(docker ps --filter label=com.docker.compose.service=vpnkit --format "{{.ID}}" | awk "NR==1{print}")
  fi
  if [ -z "${container:-}" ]; then
    container=$(docker ps --filter name='^/vpnkit$' --format "{{.ID}}" | awk "NR==1{print}")
  fi
  if [ -z "${container:-}" ]; then
    container=$(docker ps --format "{{.ID}} {{.Names}}" | while read -r cid cname; do case "$cname" in *vpnkit*) printf "%s\n" "$cid"; break ;; esac; done)
  fi
  [ -n "${container:-}" ] || { log container=missing; return 10; }
  workdir=${VPNKIT_PROD_WORKDIR:-$(docker_label com.docker.compose.project.working_dir)}
  [ -n "${workdir:-}" ] || workdir=$(infer_workdir_from_mounts)
  service=${VPNKIT_PROD_SERVICE:-$(docker_label com.docker.compose.service)}
  project=${VPNKIT_PROD_PROJECT:-$(docker_label com.docker.compose.project)}
  [ -n "${workdir:-}" ] || { log workdir=missing; return 11; }
  [ -d "$workdir" ] || { log workdir=not_directory; return 11; }
  [ -n "${service:-}" ] || service=vpnkit
  [ "$service" = vpnkit ] || { log service=unexpected; return 12; }
  cd "$workdir"
  find_compose
  log "discover=ok service=$service project=${project:-unknown} workdir=<discovered>"
}
smoke() {
  cid=${1:-$container}
  docker inspect -f "{{.State.Running}}" "$cid" | grep -q true && log container_running=ok || { log container_running=fail; return 30; }
  docker inspect "$cid" --format "{{json .NetworkSettings.Ports}}" | grep -q "\"1194/udp\"" && log udp_1194=mapped || { log udp_1194=mapping_missing; return 31; }
  docker exec "$cid" sh -lc '\''set -eu
    pgrep openvpn >/dev/null && echo openvpn=up || { echo openvpn=down; exit 32; }
    ip addr show tun0 >/dev/null 2>&1 && echo tun0=present || { echo tun0=missing; exit 33; }
    pgrep sing-box >/dev/null && echo singbox=up || { echo singbox=down; exit 34; }
    sing-box check -c /var/lib/vpnkit/sing-box/config.json >/tmp/vpnkit-sing-box-check.out 2>&1 && echo singbox_check=ok || { echo singbox_check=fail; tail -20 /tmp/vpnkit-sing-box-check.out; exit 35; }
    mode=$(printenv VPNKIT_ROUTING_MODE 2>/dev/null || echo unknown)
    if [ "$mode" = tun ]; then
      iface=$(printenv SINGBOX_TUN_IFACE 2>/dev/null || echo sb-tun0)
      table=$(printenv SINGBOX_TUN_TABLE 2>/dev/null || echo 101)
      ip addr show "$iface" >/dev/null 2>&1 && echo sb_tun0=present || { echo sb_tun0=missing; exit 36; }
      ip rule show | grep -q "lookup $table" && echo policy_rule=ok || { echo policy_rule=missing; exit 37; }
      ip route show table "$table" | grep -q "^default .* dev $iface" && echo route_table=ok || { echo route_table=missing; exit 38; }
    fi
    if command -v ss >/dev/null 2>&1; then ss -lunp | grep -q ":1194" && echo udp_1194_listener=ok || { echo udp_1194_listener=missing; exit 39; }; fi
  '\''
}
make_bundle() {
  rollback_dir="$workdir/.rollback/vpnkit/$stamp"
  mkdir -p "$rollback_dir"
  git rev-parse --verify HEAD >"$rollback_dir/git-ref.txt" 2>/dev/null || true
  docker inspect "$container" --format "{{.Config.Image}}" >"$rollback_dir/image-ref.txt" 2>/dev/null || true
  cp "$rollback_dir/image-ref.txt" "$rollback_dir/image.txt" 2>/dev/null || true
  docker inspect "$container" --format "{{.Image}}" >"$rollback_dir/image-id.txt" 2>/dev/null || true
  docker inspect "$container" >"$rollback_dir/container-inspect.json" 2>/dev/null || true
  docker cp "$container:/var/lib/vpnkit/sing-box/config.json" "$rollback_dir/sing-box-config.json" >/dev/null 2>&1 || true
  : >"$rollback_dir/compose-files.txt"
  for compose_file in compose.yaml compose.yml docker-compose.yml docker-compose.yaml; do
    [ -f "$compose_file" ] && printf "%s\n" "$compose_file" >>"$rollback_dir/compose-files.txt"
  done
  [ -s "$rollback_dir/compose-files.txt" ] && cp "$rollback_dir/compose-files.txt" "$rollback_dir/compose-file.txt" 2>/dev/null || true
  {
    printf "# References only; this file intentionally records names/paths, not env values.\n"
    for env_name in VPNKIT_PROD_WORKDIR VPNKIT_PROD_SERVICE VPNKIT_PROD_CONTAINER VPNKIT_PROD_PROJECT VPNKIT_PROD_REMOTE_TIMEOUT_BIN VPNKIT_PROD_REMOTE_INNER_TIMEOUT VPNKIT_PROD_POST_RECREATE_SLEEP; do
      if env | grep -q "^${env_name}="; then printf "%s=<set>\n" "$env_name"; else printf "%s=<unset>\n" "$env_name"; fi
    done
    [ -f .env ] && printf "env_file=.env\n"
    while IFS= read -r compose_file; do
      if grep -q "^[[:space:]]*env_file:" "$compose_file"; then
        printf "compose_env_file_section=%s\n" "$compose_file"
      fi
    done <"$rollback_dir/compose-files.txt"
  } >"$rollback_dir/env-references.txt"
  cat >"$rollback_dir/rollback.sh" <<ROLLBACK
#!/usr/bin/env bash
set -euo pipefail
bundle_dir=\$(cd "\$(dirname "\$0")" && pwd)
cd "$workdir"
ref=\$(cat "\$bundle_dir/git-ref.txt" 2>/dev/null || true)
[ -n "\$ref" ] && git checkout --detach "\$ref"
[ -f "\$bundle_dir/sing-box-config.json" ] && docker cp "\$bundle_dir/sing-box-config.json" "$container:/var/lib/vpnkit/sing-box/config.json" || true
if docker compose version >/dev/null 2>&1; then docker compose up -d --build "$service"; else docker-compose up -d --build "$service"; fi
ROLLBACK
  chmod 700 "$rollback_dir/rollback.sh"
  log "rollback_bundle=.rollback/vpnkit/$stamp"
}
render_and_check() {
  [ -x scripts/vpnkit-render-local-configs.sh ] && run_bounded scripts/vpnkit-render-local-configs.sh >/tmp/vpnkit-render.out 2>/tmp/vpnkit-render.err || log render=skipped_or_failed
  if [ -f secrets/vps/rendered/sing-box/config.json ]; then
    docker cp secrets/vps/rendered/sing-box/config.json "$container:/var/lib/vpnkit/sing-box/config.json" >/dev/null
  fi
  docker exec "$container" sh -lc "sing-box check -c /var/lib/vpnkit/sing-box/config.json >/tmp/vpnkit-sing-box-check.out 2>&1" && log persisted_singbox_check=ok
}
rollback_to() {
  if [ -n "$rollback_id" ]; then rb="$rollback_id"; else rb=$(ls -1dt "$workdir"/.rollback/vpnkit/* 2>/dev/null | awk "NR==1{print}"); fi
  [ -n "${rb:-}" ] || { log rollback_bundle=missing; return 50; }
  [ -x "$rb/rollback.sh" ] || { log rollback_payload=missing; return 51; }
  log rollback_start=.rollback/vpnkit/$(basename "$rb")
  run_bounded "$rb/rollback.sh"
  new_container=$(docker ps --filter label=com.docker.compose.service="$service" --format "{{.ID}}" | awk "NR==1{print}")
  [ -n "${new_container:-}" ] || new_container=$container
  smoke "$new_container"
}
plan() {
  discover
  log "plan=deploy target_ref=$target_ref"
  log "steps=rollback-bundle,git-fetch-checkout,render-persisted-singbox-check,compose-up-vpnkit-only,smoke,auto-rollback-on-failure,post-rollback-smoke"
}
verify() { discover; smoke "$container"; }
deploy() {
  discover
  make_bundle
  run_bounded git fetch --all --prune
  run_bounded git checkout --detach "$target_ref"
  render_and_check
  run_bounded $compose_bin up -d --build "$service"
  sleep "${VPNKIT_PROD_POST_RECREATE_SLEEP:-5}"
  new_container=$(docker ps --filter label=com.docker.compose.service="$service" --format "{{.ID}}" | awk "NR==1{print}")
  [ -n "${new_container:-}" ] || { log container_after=missing; rollback_to; exit 60; }
  if smoke "$new_container"; then log deploy=ok; else log deploy_smoke=failed; rollback_to; exit 61; fi
}
case "$mode" in
  plan|dry-run) plan ;;
  verify) verify ;;
  deploy) deploy ;;
  rollback) discover; rollback_to ;;
esac
'

run_remote() {
  local host=$1
  "$timeout_bin" "$remote_timeout" "$ssh_cmd" -o BatchMode=yes -o ConnectTimeout="$ssh_timeout" "$host" \
    "bash -s -- '$mode' '$target_ref' '$rollback_id'" <<<"$remote_script" 2>&1 | redact
}

for host in "${hosts[@]}"; do
  echo "== <host> $mode =="
  if [[ "$mode" == "plan" || "$mode" == "dry-run" ]]; then
    cat <<EOFPLAN | redact
mode=$mode host=<host> target_ref=$target_ref
remote_discovery=labels_or_overrides
mutation=none
steps=discover,show plan only; deploy requires --yes and rerun with deploy
EOFPLAN
    continue
  fi
  if ! run_remote "$host"; then
    echo "host_result=failed mode=$mode" >&2
    exit 1
  fi
  echo "host_result=ok mode=$mode"
done
