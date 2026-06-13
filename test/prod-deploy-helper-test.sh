#!/usr/bin/env bash
set -euo pipefail
script=${1:-scripts/vpnkit/vpnkit-prod-deploy.sh}
fail=0
check_fail() { if "$@" >/tmp/vpnkit-prod-deploy-test.out 2>&1; then echo "expected failure: $*"; fail=1; fi; }
check_ok() { if ! "$@" >/tmp/vpnkit-prod-deploy-test.out 2>&1; then echo "expected success: $*"; cat /tmp/vpnkit-prod-deploy-test.out; fail=1; fi; }
assert_grep() { local pattern=$1 file=${2:-/tmp/vpnkit-prod-deploy-test.out}; if ! grep -Eq -- "$pattern" "$file"; then echo "missing pattern: $pattern"; fail=1; fi; }
assert_not_grep() { local pattern=$1 file=${2:-/tmp/vpnkit-prod-deploy-test.out}; if grep -Eq -- "$pattern" "$file"; then echo "unexpected pattern: $pattern"; fail=1; fi; }
assert_order() {
  local first=$1 second=$2 file=${3:-/tmp/vpnkit-prod-deploy-test.out}
  local first_line second_line
  first_line=$(grep -En -- "$first" "$file" | head -1 | cut -d: -f1 || true)
  second_line=$(grep -En -- "$second" "$file" | head -1 | cut -d: -f1 || true)
  if [[ -z "$first_line" || -z "$second_line" || "$first_line" -ge "$second_line" ]]; then
    echo "order assertion failed: $first before $second"
    fail=1
  fi
}

check_fail "$script" deploy --target-ref main example.invalid
assert_grep "deploy requires --yes"
check_fail "$script" rollback example.invalid
assert_grep "rollback requires --yes"
check_fail "$script" plan --source-mode archive --target-ref main example.invalid
assert_grep "unsupported option: --source-mode"
check_ok "$script" plan --target-ref main --deploy-id custom-id example.invalid
assert_grep 'deploy_id=custom-id'
assert_grep 'release-dir:<remote-workdir>/.releases/vpnkit/custom-id'
assert_grep 'build-tag:vpnkit:custom-id'
assert_grep 'render-local-configs:tun'
assert_grep 'activate-no-build'
assert_not_grep 'source-before\.tar|source_update=archive|git archive|scp '
assert_not_grep '([0-9]{1,3}\.){3}[0-9]{1,3}|token=[^<]'
check_ok env VPNKIT_PROD_DEPLOY_HOSTS='example.invalid example2.invalid' "$script" dry-run --target-ref main --deploy-id env-id
if [[ $(grep -c 'mutation=none' /tmp/vpnkit-prod-deploy-test.out) -ne 2 ]]; then echo "env host list not handled sequentially"; fail=1; fi
check_ok env TZ=UTC "$script" plan --target-ref HEAD example.invalid
head_short=$(git rev-parse --short=12 HEAD)
assert_grep "deploy_id=[0-9]{8}T[0-9]{6}Z-${head_short}"
if git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
  check_ok env TZ=UTC "$script" plan --target-ref HEAD~1 example.invalid
  prev_short=$(git rev-parse --short=12 HEAD~1)
  assert_grep "deploy_id=[0-9]{8}T[0-9]{6}Z-${prev_short}"
fi
check_fail "$script" plan --target-ref main --deploy-id nested/id example.invalid
assert_grep 'deploy id contains unsupported characters'

mock_root=$(mktemp -d /tmp/vpnkit-prod-deploy-mock.XXXXXX)
trap 'rm -rf "$mock_root"' EXIT
fakebin=$mock_root/bin
remote_root=$mock_root/remote
mkdir -p "$fakebin" "$remote_root/bin" "$remote_root/workdir" "$remote_root/releases" "$remote_root/links"
mkdir -p "$remote_root/releases/prior-release"
ln -sfn "$remote_root/releases/prior-release" "$remote_root/links/current"
cat >"$remote_root/workdir/compose.yaml" <<'YAML'
services:
  vpnkit:
    env_file:
      - .env
YAML
mkdir -p "$remote_root/workdir/scripts/vpnkit" "$remote_root/workdir/config/sing-box/rule-sets" "$remote_root/workdir/secrets/vps/sing-box" "$remote_root/workdir/secrets/vps/rendered/sing-box" "$remote_root/workdir/secrets/vps/rendered/openvpn"
cat >"$remote_root/workdir/secrets/vps/rendered/openvpn/server.conf" <<'CONF'
port 1194
proto udp
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 9.9.9.9"
keepalive 10 120
CONF
cat >"$remote_root/workdir/config/sing-box/config.tun.json.template" <<'JSON'
{
  "outbounds": [
    {{SELECTED_NATIVE_OUT_JSON}},
    { "type": "direct", "tag": "direct-out" },
    { "type": "block", "tag": "block-out" }
  ],
  "route": {
    "rule_set": [
{{RU_RULE_SETS_JSON}}
    ],
    "final": "selected-native-out"
  }
}
JSON
printf '{"version":1,"rules":[]}
' >"$remote_root/workdir/config/sing-box/rule-sets/vpnkit-adblock.json"
printf '{"version":1,"rules":[]}
' >"$remote_root/workdir/config/sing-box/rule-sets/vpnkit-dev-direct.json"
cat >"$remote_root/workdir/scripts/vpnkit/vpnkit-render-local-configs.sh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'render_invoked_routing_mode=%s token=%s\n' "${VPNKIT_ROUTING_MODE:-missing}" 'mock-render-secret'
if [[ "${VPNKIT_MOCK_RENDER_FAIL:-0}" == 1 ]]; then
  echo local_config_render_mock=failed
  exit 73
fi
mkdir -p secrets/vps/rendered/sing-box
printf '{"mock":"rendered"}\n' >secrets/vps/rendered/sing-box/config.json
echo local_config_render_mock=ok
MOCK
chmod +x "$remote_root/workdir/scripts/vpnkit/vpnkit-render-local-configs.sh"
cat >"$fakebin/timeout" <<'MOCK'
#!/usr/bin/env bash
shift
exec "$@"
MOCK
chmod +x "$fakebin/timeout"
cat >"$fakebin/ssh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) shift 2 ;;
    *) host=$1; shift; break ;;
  esac
done
cmd=${1:-}
script=$(cat)
printf 'mock_ssh_host=%s\n' "$host"
mode=$(printf '%s\n' "$cmd" | sed -E "s/.*__remote '([^']*)' '([^']*)' '([^']*)' '([^']*)'.*/\1/")
target_ref=$(printf '%s\n' "$cmd" | sed -E "s/.*__remote '([^']*)' '([^']*)' '([^']*)' '([^']*)'.*/\2/")
deploy_id=$(printf '%s\n' "$cmd" | sed -E "s/.*__remote '([^']*)' '([^']*)' '([^']*)' '([^']*)'.*/\3/")
rollback_id=$(printf '%s\n' "$cmd" | sed -E "s/.*__remote '([^']*)' '([^']*)' '([^']*)' '([^']*)'.*/\4/")
if printf '%s\n' "$cmd" | grep -Eq -- "source-before|archive|scp"; then echo source_transfer_arg=present; exit 70; fi
echo source_transfer_arg=absent
PATH="$VPNKIT_MOCK_REMOTE_BIN:$PATH" \
VPNKIT_MOCK_REMOTE_ROOT="$VPNKIT_MOCK_REMOTE_ROOT" \
VPNKIT_PROD_RELEASE_ROOT="$VPNKIT_MOCK_REMOTE_ROOT/releases" \
VPNKIT_PROD_CURRENT_LINK="$VPNKIT_MOCK_REMOTE_ROOT/links/current" \
VPNKIT_PROD_PREVIOUS_LINK="$VPNKIT_MOCK_REMOTE_ROOT/links/previous" \
VPNKIT_PROD_REMOTE_TIMEOUT_BIN="$VPNKIT_PROD_DEPLOY_TIMEOUT_BIN" \
VPNKIT_PROD_SMOKE_ATTEMPTS="${VPNKIT_PROD_SMOKE_ATTEMPTS:-1}" \
VPNKIT_PROD_SMOKE_DELAY="${VPNKIT_PROD_SMOKE_DELAY:-0}" \
VPNKIT_MOCK_ROUTING_MODE="${VPNKIT_MOCK_ROUTING_MODE:-tun}" \
VPNKIT_MOCK_ROLLBACK_SMOKE_FAIL="${VPNKIT_MOCK_ROLLBACK_SMOKE_FAIL:-0}" \
VPNKIT_MOCK_REQUIRE_TUN_FAIL="${VPNKIT_MOCK_REQUIRE_TUN_FAIL:-0}" \
VPNKIT_MOCK_RENDER_FAIL="${VPNKIT_MOCK_RENDER_FAIL:-0}" \
VPNKIT_MOCK_PREVIOUS_SINGBOX_USABLE="${VPNKIT_MOCK_PREVIOUS_SINGBOX_USABLE:-0}" \
bash -s -- __remote "$mode" "$target_ref" "$deploy_id" "$rollback_id" <<<"$script"
MOCK
chmod +x "$fakebin/ssh"
cat >"$fakebin/scp-blocked" <<'MOCK'
#!/usr/bin/env bash
echo "unexpected source transfer invocation" >&2
exit 71
MOCK
chmod +x "$fakebin/scp-blocked"

cat >"$remote_root/bin/git" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  rev-parse)
    if [[ "${2:-}" == --is-inside-work-tree ]]; then exit 0; fi
    if [[ "${2:-}" == --verify ]]; then echo abc123resolved; exit 0; fi
    echo abc123mock ;;
  fetch) echo git_fetch=ok ;;
  checkout) echo "git_checkout=${*: -1}" ;;
  *) echo "git_$1=ok" ;;
esac
MOCK
cat >"$remote_root/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
root=${VPNKIT_MOCK_REMOTE_ROOT:?}
case "$1" in
  compose)
    if [[ "${2:-}" == version ]]; then echo 'Docker Compose mock'; exit 0; fi
    if [[ "${2:-}" == build ]]; then echo "compose_build=${*: -1}"; exit 0; fi
    if [[ "${2:-}" == images ]]; then echo 'sha256:candidatebuild'; exit 0; fi
    if [[ "${2:-}" == up || "$*" == *' up '* ]]; then echo "compose_up=${*:2}"; exit 0; fi ;;
  ps) echo mock-container ;;
  inspect)
    if [[ "$*" == *'{{.Config.Image}}'* ]]; then echo 'vpnkit:previous'; exit 0; fi
    if [[ "$*" == *'{{.Image}}'* ]]; then echo 'sha256:mockimageid'; exit 0; fi
    if [[ "$*" == *'com.docker.compose.project.working_dir'* ]]; then echo "$root/workdir"; exit 0; fi
    if [[ "$*" == *'com.docker.compose.service'* ]]; then echo vpnkit; exit 0; fi
    if [[ "$*" == *'com.docker.compose.project'* ]]; then echo vpnkit-prod; exit 0; fi
    if [[ "$*" == *'{{.State.Running}}'* ]]; then echo true; exit 0; fi
    if [[ "$*" == *'{{json .NetworkSettings.Ports}}'* ]]; then echo '{"1194/udp":[{"HostPort":"1194"}]}'; exit 0; fi
    echo '[{"mock":"inspect"}]' ;;
  cp)
    dest=${3:-}
    if [[ "$dest" == *previous-sing-box-config.json ]]; then
      if [[ "${VPNKIT_MOCK_PREVIOUS_SINGBOX_USABLE:-0}" == 1 ]]; then
        printf '{"outbounds":[{"type":"direct","tag":"selected-native-out"}]}
' >"$dest"
      else
        echo '{"mock":"sing-box"}' >"$dest"
      fi
    fi
    echo docker_cp=ok ;;
  tag) echo "docker_tag=$2 $3" ;;
  exec)
    if [[ "${VPNKIT_MOCK_ROLLBACK_SMOKE_FAIL:-0}" == 1 && "$*" == *'ip route show table'* ]]; then
      echo openvpn=up; echo tun0=present; echo singbox=up; echo routing_mode=tun; echo singbox_check=ok; echo sb_tun0=present; echo policy_rule=ok; echo route_table=missing; exit 39
    fi
    if [[ "$*" == *'printenv VPNKIT_ROUTING_MODE'* && "$*" != *'ip route show table'* ]]; then
      if [[ "$*" != *'echo routing_mode='* ]]; then
        echo "${VPNKIT_MOCK_PREVIOUS_ROUTING_MODE:-tun}"
        exit 0
      fi
      if [[ "${VPNKIT_MOCK_REQUIRE_TUN_FAIL:-0}" == 1 ]]; then echo routing_mode=redirect; exit 41; fi
      if [[ "$*" == *'\[ "$mode" = tun \]'* ]]; then
        [[ "${VPNKIT_MOCK_ROUTING_MODE:-tun}" == tun ]] && echo routing_mode=tun || echo routing_mode=redirect
        [[ "${VPNKIT_MOCK_ROUTING_MODE:-tun}" == tun ]] || exit 41
        exit 0
      fi
      [[ "${VPNKIT_MOCK_ROUTING_MODE:-tun}" == tun ]] && echo tun || echo redirect
      [[ "${VPNKIT_MOCK_ROUTING_MODE:-tun}" == tun ]] || exit 41
      exit 0
    fi
    if [[ "$*" == *'mode=$(printenv VPNKIT_ROUTING_MODE'* ]]; then
      if [[ "${VPNKIT_MOCK_ROUTING_MODE:-tun}" != tun ]]; then echo routing_mode=redirect; exit 35; fi
    fi
    echo openvpn=up
    echo tun0=present
    echo singbox=up
    echo routing_mode=tun
    echo singbox_check=ok
    echo sb_tun0=present
    echo policy_rule=ok
    echo route_table=ok
    echo udp_1194_listener=ok
    printf 'token=%s\n' 'mock-secret-output' ;;
  *) echo "docker_$1=ok" ;;
esac
MOCK
chmod +x "$remote_root/bin/git" "$remote_root/bin/docker"
mock_env=(env PATH="$fakebin:$PATH" VPNKIT_PROD_DEPLOY_TIMEOUT_BIN="$fakebin/timeout" VPNKIT_PROD_SSH_CMD="$fakebin/ssh" VPNKIT_MOCK_REMOTE_BIN="$remote_root/bin" VPNKIT_MOCK_REMOTE_ROOT="$remote_root")

check_ok "${mock_env[@]}" "$script" verify host-a
assert_grep 'mock_ssh_host=host-a'
assert_grep 'routing_mode=tun'
assert_grep 'sb_tun0=present'
assert_grep 'policy_rule=ok'
assert_grep 'route_table=ok'
assert_grep 'token=<redacted>'
assert_not_grep 'token=mock-secret-output'

check_fail env PATH="$fakebin:$PATH" VPNKIT_PROD_DEPLOY_TIMEOUT_BIN="$fakebin/timeout" VPNKIT_PROD_SSH_CMD="$fakebin/ssh" VPNKIT_MOCK_REMOTE_BIN="$remote_root/bin" VPNKIT_MOCK_REMOTE_ROOT="$remote_root" VPNKIT_MOCK_ROUTING_MODE=redirect "$script" verify host-a
assert_grep 'routing_mode=redirect'

check_ok "${mock_env[@]}" "$script" deploy --yes --target-ref main --deploy-id 20260613T010203Z-deadbeef host-a
if [[ $(grep -c 'mock_ssh_host=' /tmp/vpnkit-prod-deploy-test.out) -ne 1 ]]; then echo "mock deploy did not execute host once"; fail=1; fi
assert_grep 'source_transfer_arg=absent'
assert_grep 'source_update=git resolved_ref=abc123resolved'
assert_grep 'local_config_render=start mode=tun'
assert_grep 'render_invoked_routing_mode=tun token=<redacted>'
assert_grep 'local_config_render_mock=ok'
assert_grep 'local_config_render=ok'
assert_grep 'openvpn_push_dns=updated'
assert_not_grep 'singbox_only_fallback|local_config_render_selected_source'
assert_order 'source_update=git resolved_ref=abc123resolved' 'local_config_render=start mode=tun'
assert_order 'local_config_render=ok' 'openvpn_push_dns=updated'
assert_order 'openvpn_push_dns=updated' 'compose_build=vpnkit'
assert_grep 'push "dhcp-option DNS 1.1.1.1"' "$remote_root/workdir/secrets/vps/rendered/openvpn/server.conf"
assert_grep 'keepalive 10 120' "$remote_root/workdir/secrets/vps/rendered/openvpn/server.conf"
assert_grep 'release_dir=.*/releases/20260613T010203Z-deadbeef'
assert_grep 'candidate_image=vpnkit:20260613T010203Z-deadbeef'
assert_grep 'docker_tag=sha256:candidatebuild vpnkit:20260613T010203Z-deadbeef'
assert_grep 'compose_build=vpnkit'
assert_grep 'compose_up=.*-f .*/compose.image.override.yaml up -d --no-build vpnkit'
assert_grep 'compose_image_override=.*/compose.image.override.yaml'
assert_grep 'activation=no_build'
assert_grep 'persisted_singbox_check=ok'
assert_grep 'deploy=ok'
assert_not_grep 'mock-render-secret'
bundle="$remote_root/releases/20260613T010203Z-deadbeef/rollback"
for artifact in deploy-id.txt candidate-image.txt git-ref.txt previous-image.txt previous-image-id.txt previous-release-target.txt previous-routing-mode.txt container-inspect.json previous-sing-box-config.json compose-files.txt env-references.txt; do
  if [[ ! -s "$bundle/$artifact" ]]; then echo "missing rollback artifact: $artifact"; fail=1; fi
done
assert_grep 'vpnkit:20260613T010203Z-deadbeef' "$bundle/candidate-image.txt"
assert_grep 'vpnkit:previous' "$bundle/previous-image.txt"
assert_grep '.*/releases/prior-release$' "$bundle/previous-release-target.txt"
assert_grep '^tun$' "$bundle/previous-routing-mode.txt"
if [[ "$(readlink -f "$remote_root/links/current")" != "$remote_root/releases/20260613T010203Z-deadbeef" ]]; then echo "current link not set to candidate release after deploy"; fail=1; fi
if [[ "$(readlink -f "$remote_root/links/previous")" != "$remote_root/releases/prior-release" ]]; then echo "previous link not set to prior release after deploy"; fail=1; fi
assert_grep 'image: vpnkit:20260613T010203Z-deadbeef' "$remote_root/releases/20260613T010203Z-deadbeef/compose.image.override.yaml"
assert_grep 'VPNKIT_ROUTING_MODE: tun' "$remote_root/releases/20260613T010203Z-deadbeef/compose.image.override.yaml"
assert_not_grep 'secret|token=|password=|PRIVATE|BEGIN ' "$bundle/env-references.txt"

check_ok env PATH="$fakebin:$PATH" VPNKIT_PROD_DEPLOY_TIMEOUT_BIN="$fakebin/timeout" VPNKIT_PROD_SSH_CMD="$fakebin/ssh" VPNKIT_MOCK_REMOTE_BIN="$remote_root/bin" VPNKIT_MOCK_REMOTE_ROOT="$remote_root" VPNKIT_OPENVPN_PUSH_DNS=8.8.4.4 "$script" deploy --yes --target-ref main --deploy-id 20260613T010203Z-cafebabe host-a
assert_grep 'openvpn_push_dns=updated'
assert_order 'local_config_render=ok' 'openvpn_push_dns=updated'
assert_order 'openvpn_push_dns=updated' 'compose_build=vpnkit'
assert_grep 'push "dhcp-option DNS 8.8.4.4"' "$remote_root/workdir/secrets/vps/rendered/openvpn/server.conf"
assert_not_grep 'push "dhcp-option DNS 1.1.1.1"' "$remote_root/workdir/secrets/vps/rendered/openvpn/server.conf"

check_fail env PATH="$fakebin:$PATH" VPNKIT_PROD_DEPLOY_TIMEOUT_BIN="$fakebin/timeout" VPNKIT_PROD_SSH_CMD="$fakebin/ssh" VPNKIT_MOCK_REMOTE_BIN="$remote_root/bin" VPNKIT_MOCK_REMOTE_ROOT="$remote_root" VPNKIT_OPENVPN_PUSH_DNS=999.1.1.1 "$script" deploy --yes --target-ref main --deploy-id 20260613T010203Z-badbadbad host-a
assert_grep 'VPNKIT_OPENVPN_PUSH_DNS must be a valid IPv4 address|openvpn_push_dns=invalid'
assert_not_grep 'compose_build|compose_up|activation=no_build'

rm -f "$remote_root/workdir/secrets/vps/rendered/openvpn/server.conf"
check_fail "${mock_env[@]}" "$script" deploy --yes --target-ref main --deploy-id 20260613T010203Z-missingdns host-a
assert_grep 'openvpn_push_dns_config=missing|openvpn_push_dns=failed'
assert_not_grep 'compose_build|compose_up|activation=no_build'
cat >"$remote_root/workdir/secrets/vps/rendered/openvpn/server.conf" <<'CONF'
port 1194
proto udp
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 9.9.9.9"
keepalive 10 120
CONF

check_ok "${mock_env[@]}" "$script" rollback --yes --rollback-id "$bundle" host-a
assert_grep 'rollback_start=.*rollback'
assert_grep 'compose_up=.*-f .*/rollback.compose.image.override.yaml up -d --no-build vpnkit'
assert_grep 'compose_image_override=.*/rollback.compose.image.override.yaml'
assert_grep 'rollback_activation=no_build'
assert_grep 'rollback=ok'
if [[ "$(readlink -f "$remote_root/links/current")" != "$remote_root/releases/prior-release" ]]; then echo "current link not restored to prior release after rollback"; fail=1; fi
if [[ "$(readlink -f "$remote_root/links/previous")" != "$remote_root/releases/20260613T010203Z-deadbeef" ]]; then echo "previous link not set to failed release after rollback"; fail=1; fi
assert_grep 'image: vpnkit:previous' "$bundle/rollback.compose.image.override.yaml"
assert_grep 'VPNKIT_ROUTING_MODE: tun' "$bundle/rollback.compose.image.override.yaml"
assert_not_grep 'compose_build'

check_fail env PATH="$fakebin:$PATH" VPNKIT_PROD_DEPLOY_TIMEOUT_BIN="$fakebin/timeout" VPNKIT_PROD_SSH_CMD="$fakebin/ssh" VPNKIT_MOCK_REMOTE_BIN="$remote_root/bin" VPNKIT_MOCK_REMOTE_ROOT="$remote_root" VPNKIT_MOCK_ROLLBACK_SMOKE_FAIL=1 "$script" rollback --yes --rollback-id "$bundle" host-a
assert_grep 'rollback_smoke=failed'
assert_grep 'manual_recovery_command=ssh <host> "cd .+ && VPNKIT_RECOVERY_BUNDLE=.+ scripts/vpnkit/vpnkit-prod-deploy.sh __remote rollback'
assert_not_grep 'compose_build'

check_fail env PATH="$fakebin:$PATH" VPNKIT_PROD_DEPLOY_TIMEOUT_BIN="$fakebin/timeout" VPNKIT_PROD_SSH_CMD="$fakebin/ssh" VPNKIT_MOCK_REMOTE_BIN="$remote_root/bin" VPNKIT_MOCK_REMOTE_ROOT="$remote_root" VPNKIT_MOCK_REQUIRE_TUN_FAIL=1 "$script" deploy --yes --target-ref main --deploy-id 20260613T010204Z-deadbeef host-a
assert_grep 'deploy_activation_or_config=failed'
assert_grep 'rollback_start=.*rollback'
assert_grep 'rollback_activation=no_build'

cat >"$remote_root/workdir/secrets/vps/sing-box/tproxy-canary.json" <<'JSON'
{
  "outbounds": [
    {
      "type": "vless",
      "tag": "selected-native-out",
      "server": "203.0.113.10",
      "server_port": 443,
      "uuid": "00000000-0000-0000-0000-000000000000"
    }
  ]
}
JSON
cat >"$remote_root/workdir/secrets/vps/rendered/sing-box/config.json" <<'JSON'
{"outbounds":[{"type":"direct","tag":"selected-native-out"}]}
JSON
check_ok env PATH="$fakebin:$PATH" VPNKIT_PROD_DEPLOY_TIMEOUT_BIN="$fakebin/timeout" VPNKIT_PROD_SSH_CMD="$fakebin/ssh" VPNKIT_MOCK_REMOTE_BIN="$remote_root/bin" VPNKIT_MOCK_REMOTE_ROOT="$remote_root" VPNKIT_MOCK_RENDER_FAIL=1 "$script" deploy --yes --target-ref main --deploy-id 20260613T010205Z-deadbeef host-a
assert_grep 'local_config_render=start mode=tun'
assert_grep 'render_invoked_routing_mode=tun token=<redacted>'
assert_grep 'local_config_render_mock=failed'
assert_grep 'local_config_render=singbox_only_fallback'
assert_grep 'local_config_render_selected_source=tproxy_canary'
assert_order 'local_config_render=singbox_only_fallback' 'compose_build=vpnkit'
fallback_config="$remote_root/workdir/secrets/vps/rendered/sing-box/config.json"
assert_grep '"type": "vless"' "$fallback_config"
assert_grep '"server": "203.0.113.10"' "$fallback_config"
assert_grep 'runetfreedom/russia-v2ray-rules-dat/.*/geoip-ru.srs' "$fallback_config"
assert_grep 'runetfreedom/russia-v2ray-rules-dat/.*/geosite-category-ru.srs' "$fallback_config"
assert_not_grep '\{\{SELECTED_NATIVE_OUT_JSON\}\}|\{\{RU_RULE_SETS_JSON\}\}' "$fallback_config"
for ruleset in vpnkit-adblock.json vpnkit-dev-direct.json; do
  if [[ ! -s "$remote_root/workdir/secrets/vps/rendered/sing-box/rule-sets/$ruleset" ]]; then echo "fallback did not copy rule set: $ruleset"; fail=1; fi
done
assert_grep 'deploy=ok'
assert_not_grep 'mock-render-secret|00000000-0000-0000-0000-000000000000'

rm -f "$remote_root/workdir/secrets/vps/sing-box/tproxy-canary.json"
cat >"$remote_root/workdir/secrets/vps/rendered/sing-box/config.json" <<'JSON'
{"outbounds":[{"type":"direct","tag":"selected-native-out"}]}
JSON
check_ok env PATH="$fakebin:$PATH" VPNKIT_PROD_DEPLOY_TIMEOUT_BIN="$fakebin/timeout" VPNKIT_PROD_SSH_CMD="$fakebin/ssh" VPNKIT_MOCK_REMOTE_BIN="$remote_root/bin" VPNKIT_MOCK_REMOTE_ROOT="$remote_root" VPNKIT_MOCK_RENDER_FAIL=1 "$script" deploy --yes --target-ref main --deploy-id 20260613T010206Z-deadbeef host-a
assert_grep 'local_config_render=singbox_only_fallback'
assert_grep 'local_config_render_selected_source=rendered_singbox'
assert_order 'local_config_render=singbox_only_fallback' 'compose_build=vpnkit'

rm -f "$remote_root/workdir/secrets/vps/sing-box/tproxy-canary.json" "$remote_root/workdir/secrets/vps/rendered/sing-box/config.json"
check_ok env PATH="$fakebin:$PATH" VPNKIT_PROD_DEPLOY_TIMEOUT_BIN="$fakebin/timeout" VPNKIT_PROD_SSH_CMD="$fakebin/ssh" VPNKIT_MOCK_REMOTE_BIN="$remote_root/bin" VPNKIT_MOCK_REMOTE_ROOT="$remote_root" VPNKIT_MOCK_RENDER_FAIL=1 VPNKIT_MOCK_PREVIOUS_SINGBOX_USABLE=1 "$script" deploy --yes --target-ref main --deploy-id 20260613T010207Z-deadbeef host-a
assert_grep 'local_config_render=singbox_only_fallback'
assert_grep 'local_config_render_selected_source=rollback_previous'
assert_order 'local_config_render=singbox_only_fallback' 'compose_build=vpnkit'

rm -f "$remote_root/workdir/secrets/vps/sing-box/tproxy-canary.json" "$remote_root/workdir/secrets/vps/rendered/sing-box/config.json"
check_fail env PATH="$fakebin:$PATH" VPNKIT_PROD_DEPLOY_TIMEOUT_BIN="$fakebin/timeout" VPNKIT_PROD_SSH_CMD="$fakebin/ssh" VPNKIT_MOCK_REMOTE_BIN="$remote_root/bin" VPNKIT_MOCK_REMOTE_ROOT="$remote_root" VPNKIT_MOCK_RENDER_FAIL=1 "$script" deploy --yes --target-ref main --deploy-id 20260613T010208Z-deadbeef host-a
assert_grep 'local_config_render=start mode=tun'
assert_grep 'render_invoked_routing_mode=tun token=<redacted>'
assert_grep 'local_config_render_mock=failed'
assert_grep 'local_config_render=failed'
assert_grep 'singbox_only_fallback=failed'
assert_grep 'deploy_render=failed'
assert_not_grep 'compose_build|compose_up|activation=no_build|rollback_activation=no_build'
assert_not_grep 'mock-render-secret'

exit "$fail"
