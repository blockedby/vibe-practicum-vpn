#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Production-safe vpnkit Docker/Compose deploy helper.

Usage:
  scripts/vpnkit/vpnkit-prod-deploy.sh plan --target-ref <ref> [--deploy-id <id>] <ssh-host> [<ssh-host> ...]
  scripts/vpnkit/vpnkit-prod-deploy.sh dry-run --target-ref <ref> [--deploy-id <id>] <ssh-host> [<ssh-host> ...]
  scripts/vpnkit/vpnkit-prod-deploy.sh deploy --yes --target-ref <ref> [--deploy-id <id>] <ssh-host> [<ssh-host> ...]
  scripts/vpnkit/vpnkit-prod-deploy.sh rollback --yes [--rollback-id <id-or-path>] <ssh-host> [<ssh-host> ...]
  scripts/vpnkit/vpnkit-prod-deploy.sh verify <ssh-host> [<ssh-host> ...]

Safety:
- plan/dry-run print the bounded remote plan only; they do not run remote Docker/Compose mutation.
- deploy and rollback refuse unless --yes is passed.
- production source updates are git-only: the remote release is checked out from the requested git ref.
- deploy creates a release under the discovered workdir by default (.releases/vpnkit/<deploy-id>),
  tags the candidate image vpnkit:<deploy-id>, updates current/previous release pointers, and
  records rollback metadata. Override paths only with remote VPNKIT_PROD_RELEASE_ROOT/CURRENT_LINK/PREVIOUS_LINK.
- rollback restores previous image/release/config/mode metadata and does not build.
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
ref_id_re='^[A-Za-z0-9._@:+/~^-]+$'
deploy_id_re='^[A-Za-z0-9._@:+-]+$'

default_deploy_id() {
  local ref=${1:?} ts sha
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  sha=$(git rev-parse --short=12 "${ref}^{commit}" 2>/dev/null || git rev-parse --short=12 "$ref" 2>/dev/null || printf 'nogit')
  printf '%s-%s\n' "$ts" "$sha"
}

if [[ "${1:-}" == "__remote" ]]; then
  shift
  mode=${1:?}; target_ref=${2:-}; deploy_id=${3:-}; rollback_id=${4:-}
  timeout_cmd=${VPNKIT_PROD_REMOTE_TIMEOUT_BIN:-timeout}
  run_timeout=${VPNKIT_PROD_REMOTE_INNER_TIMEOUT:-600}
  release_root=${VPNKIT_PROD_RELEASE_ROOT:-}
  current_link=${VPNKIT_PROD_CURRENT_LINK:-}
  previous_link=${VPNKIT_PROD_PREVIOUS_LINK:-}
  compose_bin=""
  container=""; workdir=""; service=""; project=""; compose_image_override=""
  log() { printf '%s\n' "$*"; }
  run_bounded() { "$timeout_cmd" "$run_timeout" "$@"; }
  find_compose() { if docker compose version >/dev/null 2>&1; then compose_bin="docker compose"; elif command -v docker-compose >/dev/null 2>&1; then compose_bin="docker-compose"; else log compose=missing; return 20; fi; }
  docker_label() {
    key=$1
    value=$(docker inspect "$container" --format "{{index .Config.Labels \"$key\"}}" 2>/dev/null || true)
    if [ "$value" != "<no value>" ]; then printf '%s\n' "$value"; fi
  }
  infer_workdir_from_mounts() {
    docker inspect "$container" --format "{{range .Mounts}}{{println .Source \"->\" .Destination}}{{end}}" 2>/dev/null |
    while read -r mount_src _arrow mount_dest; do
      case "$mount_dest" in
        /etc/openvpn|/etc/sing-box|/etc/vibe-vpn)
          case "$mount_src" in
            */secrets/vps/rendered/openvpn|*/secrets/vps/rendered/sing-box|*/secrets/vps/rendered/vibe-vpn)
              root=${mount_src%/secrets/vps/rendered/*}
              if [ -d "$root" ] && { [ -f "$root/docker-compose.yml" ] || [ -f "$root/docker-compose.yaml" ] || [ -f "$root/compose.yaml" ] || [ -f "$root/compose.yml" ]; }; then printf '%s\n' "$root"; break; fi ;;
          esac ;;
      esac
    done
  }
  init_release_paths() {
    if [ -z "${release_root:-}" ]; then release_root="$workdir/.releases/vpnkit"; fi
    if [ -z "${current_link:-}" ]; then current_link="$workdir/.releases/current"; fi
    if [ -z "${previous_link:-}" ]; then previous_link="$workdir/.releases/previous"; fi
  }
  discover() {
    container=${VPNKIT_PROD_CONTAINER:-}
    [ -n "${container:-}" ] || container=$(docker ps --filter label=com.docker.compose.service=vpnkit --format "{{.ID}}" | awk 'NR==1{print}')
    [ -n "${container:-}" ] || container=$(docker ps --filter name='^/vpnkit$' --format "{{.ID}}" | awk 'NR==1{print}')
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
    init_release_paths
    log "discover=ok service=$service project=${project:-unknown} workdir=<discovered> release_root=<workdir>/.releases/vpnkit"
  }
  require_tun_pair() {
    docker exec "$container" sh -lc 'mode=$(printenv VPNKIT_ROUTING_MODE 2>/dev/null || true); [ "$mode" = tun ] && echo routing_mode=tun || { echo routing_mode=${mode:-missing}; exit 41; }' || return $?
    if [ -f secrets/vps/rendered/sing-box/config.json ]; then
      docker cp secrets/vps/rendered/sing-box/config.json "$container:/var/lib/vpnkit/sing-box/config.json" >/dev/null || return $?
      log persisted_singbox_config=refreshed
    fi
    docker exec "$container" sh -lc 'sing-box check -c /var/lib/vpnkit/sing-box/config.json >/tmp/vpnkit-sing-box-check.out 2>&1 || { echo persisted_singbox_check=fail; tail -20 /tmp/vpnkit-sing-box-check.out; exit 42; }' || return $?
    log persisted_singbox_check=ok
  }
  smoke() {
    cid=${1:-$container}
    docker inspect -f "{{.State.Running}}" "$cid" | grep -q true && log container_running=ok || { log container_running=fail; return 30; }
    docker inspect "$cid" --format "{{json .NetworkSettings.Ports}}" | grep -q '"1194/udp"' && log udp_1194=mapped || { log udp_1194=mapping_missing; return 31; }
    docker exec "$cid" sh -lc 'set -eu
      pgrep openvpn >/dev/null && echo openvpn=up || { echo openvpn=down; exit 32; }
      ip addr show tun0 >/dev/null 2>&1 && echo tun0=present || { echo tun0=missing; exit 33; }
      pgrep sing-box >/dev/null && echo singbox=up || { echo singbox=down; exit 34; }
      mode=$(printenv VPNKIT_ROUTING_MODE 2>/dev/null || true)
      [ "$mode" = tun ] && echo routing_mode=tun || { echo routing_mode=${mode:-missing}; exit 35; }
      sing-box check -c /var/lib/vpnkit/sing-box/config.json >/tmp/vpnkit-sing-box-check.out 2>&1 && echo singbox_check=ok || { echo singbox_check=fail; tail -20 /tmp/vpnkit-sing-box-check.out; exit 36; }
      iface=$(printenv SINGBOX_TUN_IFACE 2>/dev/null || echo sb-tun0)
      table=$(printenv SINGBOX_TUN_TABLE 2>/dev/null || echo 101)
      ip addr show "$iface" >/dev/null 2>&1 && echo sb_tun0=present || { echo sb_tun0=missing; exit 37; }
      ip rule show | grep -q "lookup $table" && echo policy_rule=ok || { echo policy_rule=missing; exit 38; }
      ip route show table "$table" | grep -q "^default .* dev $iface" && echo route_table=ok || { echo route_table=missing; exit 39; }
      if command -v ss >/dev/null 2>&1; then ss -lunp | grep -q ":1194" && echo udp_1194_listener=ok || { echo udp_1194_listener=missing; exit 40; }; fi
    '
  }
  refresh_container() {
    new_container=$(docker ps --filter label=com.docker.compose.service="$service" --format "{{.ID}}" | awk 'NR==1{print}')
    [ -n "${new_container:-}" ] || { log container_after=missing; return 44; }
    container=$new_container
  }
  compose_up_no_build_with_image() {
    local image=$1
    local override=$2
    local base_compose
    mkdir -p "$(dirname "$override")"
    cat >"$override" <<EOFOVERRIDE
services:
  $service:
    image: $image
    environment:
      VPNKIT_ROUTING_MODE: tun
EOFOVERRIDE
    compose_image_override=$override
    if [ -f compose.yaml ]; then base_compose=compose.yaml; elif [ -f compose.yml ]; then base_compose=compose.yml; elif [ -f docker-compose.yml ]; then base_compose=docker-compose.yml; else base_compose=docker-compose.yaml; fi
    VPNKIT_IMAGE="$image" run_bounded $compose_bin -f "$base_compose" -f "$override" up -d --no-build "$service" || return $?
    refresh_container || return $?
  }
  tag_candidate_image() {
    local image=$1
    local built_image refs ref
    built_image=$(run_bounded $compose_bin images -q "$service" 2>/dev/null | awk 'NR==1{print}' || true)
    refs=""
    [ -n "${built_image:-}" ] && refs="$refs $built_image sha256:$built_image"
    [ -n "${project:-}" ] && refs="$refs ${project}-${service}:latest"
    refs="$refs $(basename "$workdir")-${service}:latest ${service}:latest"
    for ref in $refs; do
      if docker image inspect "$ref" >/dev/null 2>&1; then
        docker tag "$ref" "$image" || return $?
        log "candidate_image_source=$ref"
        return 0
      fi
    done
    log candidate_image_tag=failed
    return 43
  }
  write_metadata() {
    local dir=$1
    mkdir -p "$dir"
    printf '%s\n' "$deploy_id" >"$dir/deploy-id.txt"
    printf 'vpnkit:%s\n' "$deploy_id" >"$dir/candidate-image.txt"
    git rev-parse --verify HEAD >"$dir/git-ref.txt" 2>/dev/null || true
    docker inspect "$container" --format "{{.Config.Image}}" >"$dir/previous-image.txt" 2>/dev/null || true
    docker inspect "$container" --format "{{.Image}}" >"$dir/previous-image-id.txt" 2>/dev/null || true
    if [ -L "$current_link" ] || [ -e "$current_link" ]; then readlink -f "$current_link" >"$dir/previous-release-target.txt" 2>/dev/null || printf '%s\n' "$current_link" >"$dir/previous-release-target.txt"; else : >"$dir/previous-release-target.txt"; fi
    docker exec "$container" sh -lc 'printenv VPNKIT_ROUTING_MODE 2>/dev/null || true' >"$dir/previous-routing-mode.txt" 2>/dev/null || true
    docker inspect "$container" >"$dir/container-inspect.json" 2>/dev/null || true
    docker cp "$container:/var/lib/vpnkit/sing-box/config.json" "$dir/previous-sing-box-config.json" >/dev/null 2>&1 || true
    : >"$dir/compose-files.txt"; for f in compose.yaml compose.yml docker-compose.yml docker-compose.yaml; do [ -f "$f" ] && printf '%s\n' "$f" >>"$dir/compose-files.txt"; done
    { printf '# References only; values intentionally omitted.\n'; for env_name in VPNKIT_PROD_WORKDIR VPNKIT_PROD_SERVICE VPNKIT_PROD_CONTAINER VPNKIT_PROD_PROJECT VPNKIT_PROD_RELEASE_ROOT VPNKIT_PROD_CURRENT_LINK VPNKIT_PROD_PREVIOUS_LINK; do if env | grep -q "^${env_name}="; then printf '%s=<set>\n' "$env_name"; else printf '%s=<unset>\n' "$env_name"; fi; done; [ -f .env ] && printf 'env_file=.env\n'; true; } >"$dir/env-references.txt"
  }
  create_release() {
    release_dir="$release_root/$deploy_id"
    rollback_dir="$release_dir/rollback"
    mkdir -p "$release_dir"
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      run_bounded git fetch --all --prune
      resolved_ref=$(git rev-parse --verify "$target_ref")
      run_bounded git checkout --detach "$resolved_ref"
      log "source_update=git resolved_ref=$resolved_ref"
    else log source_update=failed; return 40; fi
    write_metadata "$rollback_dir"
    printf '%s\n' "$workdir" >"$release_dir/workdir.txt"
    log "release_dir=$release_dir"
    log "rollback_bundle=$rollback_dir"
  }
  activate_image() {
    image="vpnkit:$deploy_id"
    run_bounded $compose_bin build "$service" || return $?
    tag_candidate_image "$image" || return $?
    log "candidate_image=$image"
    if [ -L "$current_link" ] || [ -e "$current_link" ]; then ln -sfn "$(readlink -f "$current_link" 2>/dev/null || printf '%s' "$current_link")" "$previous_link" 2>/dev/null || true; fi
    ln -sfn "$release_root/$deploy_id" "$current_link" 2>/dev/null || true
    compose_up_no_build_with_image "$image" "$release_root/$deploy_id/compose.image.override.yaml" || return $?
    log "compose_image_override=$compose_image_override"
    log activation=no_build
  }
  manual_recovery() { local rb=$1; printf 'manual_recovery_command=ssh <host> "cd %s && VPNKIT_RECOVERY_BUNDLE=%s scripts/vpnkit/vpnkit-prod-deploy.sh __remote rollback \"\" \"\" %s"\n' "$workdir" "$rb" "$rb"; }
  rollback_to() {
    if [ -n "$rollback_id" ]; then rb="$rollback_id"; else rb=$(find "$release_root" -path '*/rollback' -type d 2>/dev/null | sort | tail -1); fi
    [ -n "${rb:-}" ] || { log rollback_bundle=missing; return 50; }
    log "rollback_start=$rb"
    prev_image=$(cat "$rb/previous-image.txt" 2>/dev/null || true)
    [ -n "$prev_image" ] || { log previous_image=missing; return 51; }
    [ -f "$rb/previous-sing-box-config.json" ] && docker cp "$rb/previous-sing-box-config.json" "$container:/var/lib/vpnkit/sing-box/config.json" || true
    prev_mode=$(cat "$rb/previous-routing-mode.txt" 2>/dev/null || true)
    [ "$prev_mode" = tun ] || { log previous_routing_mode=${prev_mode:-missing}; return 52; }
    failed_release=$(dirname "$rb")
    prior_release=$(cat "$rb/previous-release-target.txt" 2>/dev/null || true)
    if [ -n "$prior_release" ]; then ln -sfn "$prior_release" "$current_link" 2>/dev/null || true; else log previous_release_target=missing; fi
    ln -sfn "$failed_release" "$previous_link" 2>/dev/null || true
    compose_up_no_build_with_image "$prev_image" "$rb/rollback.compose.image.override.yaml" || { log rollback_activation=failed; manual_recovery "$rb"; return 60; }
    log "compose_image_override=$compose_image_override"
    log rollback_activation=no_build
    new_container=$(docker ps --filter label=com.docker.compose.service="$service" --format "{{.ID}}" | awk 'NR==1{print}')
    [ -n "${new_container:-}" ] || new_container=$container
    if smoke "$new_container"; then log rollback=ok; else log rollback_smoke=failed; manual_recovery "$rb"; return 61; fi
  }
  plan() { discover; log "plan=deploy target_ref=$target_ref deploy_id=$deploy_id"; log "steps=discover,resolve-git-ref,release-dir:$release_root/$deploy_id,rollback-metadata,build-tag:vpnkit:$deploy_id,activate-no-build,force-tun-config-mode,smoke,auto-rollback-no-build,manual-recovery-on-rollback-smoke-failure"; }
  verify() { discover; smoke "$container"; }
  deploy() { discover; create_release; if activate_image && require_tun_pair; then new_container=$(docker ps --filter label=com.docker.compose.service="$service" --format "{{.ID}}" | awk 'NR==1{print}'); [ -n "${new_container:-}" ] || new_container=$container; if smoke "$new_container"; then log deploy=ok; return 0; else log deploy_smoke=failed; fi; else log deploy_activation_or_config=failed; fi; rollback_to || true; exit 61; }
  case "$mode" in plan|dry-run) plan ;; verify) verify ;; deploy) deploy ;; rollback) discover; rollback_to ;; *) die "unsupported remote mode: $mode" ;; esac
  exit 0
fi

mode=${1:-}
[[ -n "$mode" && "$mode" != "-h" && "$mode" != "--help" ]] || { usage; exit 0; }
shift

timeout_bin=${VPNKIT_PROD_DEPLOY_TIMEOUT_BIN:-timeout}
ssh_timeout=${VPNKIT_PROD_SSH_TIMEOUT:-12}
remote_timeout=${VPNKIT_PROD_REMOTE_CMD_TIMEOUT:-900}
ssh_cmd=${VPNKIT_PROD_SSH_CMD:-ssh}
yes=0; target_ref=""; rollback_id=""; deploy_id=""; hosts=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) yes=1; shift ;;
    --target-ref) target_ref=${2:-}; [[ -n "$target_ref" ]] || die "--target-ref requires a value"; shift 2 ;;
    --deploy-id) deploy_id=${2:-}; [[ -n "$deploy_id" ]] || die "--deploy-id requires a value"; shift 2 ;;
    --rollback-id) rollback_id=${2:-}; [[ -n "$rollback_id" ]] || die "--rollback-id requires a value"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    --*) die "unsupported option: $1" ;;
    *) hosts+=("$1"); shift ;;
  esac
done
if [[ ${#hosts[@]} -eq 0 && -n "${VPNKIT_PROD_DEPLOY_HOSTS:-}" ]]; then read -r -a hosts <<<"$VPNKIT_PROD_DEPLOY_HOSTS"; fi
[[ ${#hosts[@]} -gt 0 ]] || die "missing ssh host(s)"
case "$mode" in
  plan|dry-run) [[ -n "$target_ref" ]] || die "$mode requires --target-ref" ;;
  deploy) [[ "$yes" == 1 ]] || die "deploy requires --yes"; [[ -n "$target_ref" ]] || die "deploy requires --target-ref" ;;
  rollback) [[ "$yes" == 1 ]] || die "rollback requires --yes" ;;
  verify) ;;
  *) die "unsupported mode: $mode" ;;
esac
[[ -z "$target_ref" || "$target_ref" =~ $ref_id_re ]] || die "target ref contains unsupported characters"
[[ -z "$rollback_id" || "$rollback_id" =~ $ref_id_re ]] || die "rollback id contains unsupported characters"
if [[ -z "$deploy_id" && ( "$mode" == "plan" || "$mode" == "dry-run" || "$mode" == "deploy" ) ]]; then deploy_id=$(default_deploy_id "$target_ref"); fi
[[ -z "$deploy_id" || "$deploy_id" =~ $deploy_id_re ]] || die "deploy id contains unsupported characters"

run_remote() {
  local host=$1
  "$timeout_bin" "$remote_timeout" "$ssh_cmd" -o BatchMode=yes -o ConnectTimeout="$ssh_timeout" "$host" \
    "bash -s -- __remote '$mode' '$target_ref' '$deploy_id' '$rollback_id'" <"$0" 2>&1 | redact
}

for host in "${hosts[@]}"; do
  echo "== <host> $mode =="
  if [[ "$mode" == "plan" || "$mode" == "dry-run" ]]; then
    cat <<EOFPLAN | redact
mode=$mode host=<host> target_ref=$target_ref deploy_id=$deploy_id
remote_discovery=labels_or_overrides
mutation=none
steps=discover,resolve-git-ref,release-dir:<remote-workdir>/.releases/vpnkit/$deploy_id,rollback-metadata,build-tag:vpnkit:$deploy_id,activate-no-build,force-tun-config-mode,smoke,auto-rollback-no-build,manual-recovery-on-rollback-smoke-failure
EOFPLAN
    continue
  fi
  if ! run_remote "$host"; then echo "host_result=failed mode=$mode" >&2; exit 1; fi
  echo "host_result=ok mode=$mode"
done
