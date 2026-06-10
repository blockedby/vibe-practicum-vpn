#!/usr/bin/env bash
set -euo pipefail
script=${1:-scripts/vpnkit-prod-deploy.sh}
fail=0
check_fail() { if "$@" >/tmp/vpnkit-prod-deploy-test.out 2>&1; then echo "expected failure: $*"; fail=1; fi; }
check_ok() { if ! "$@" >/tmp/vpnkit-prod-deploy-test.out 2>&1; then echo "expected success: $*"; cat /tmp/vpnkit-prod-deploy-test.out; fail=1; fi; }
assert_grep() { local pattern=$1 file=${2:-/tmp/vpnkit-prod-deploy-test.out}; if ! grep -q -- "$pattern" "$file"; then echo "missing pattern: $pattern"; fail=1; fi; }
assert_not_grep() { local pattern=$1 file=${2:-/tmp/vpnkit-prod-deploy-test.out}; if grep -Eq -- "$pattern" "$file"; then echo "unexpected pattern: $pattern"; fail=1; fi; }

check_fail "$script" deploy --target-ref main example.invalid
assert_grep "deploy requires --yes"
check_fail "$script" rollback example.invalid
assert_grep "rollback requires --yes"
check_ok "$script" plan --target-ref main example.invalid
assert_not_grep '([0-9]{1,3}\.){3}[0-9]{1,3}|secret|token=[^<]'
check_ok env VPNKIT_PROD_DEPLOY_HOSTS='example.invalid example2.invalid' "$script" dry-run --target-ref main
if [[ $(grep -c 'mutation=none' /tmp/vpnkit-prod-deploy-test.out) -ne 2 ]]; then echo "env host list not handled sequentially"; fail=1; fi

mock_root=$(mktemp -d /tmp/vpnkit-prod-deploy-mock.XXXXXX)
trap 'rm -rf "$mock_root"' EXIT
fakebin=$mock_root/bin
remote_root=$mock_root/remote
mkdir -p "$fakebin" "$remote_root/bin" "$remote_root/workdir" "$remote_root/workdir/.rollback/vpnkit/20260610T000000Z"
cat >"$remote_root/workdir/compose.yaml" <<'YAML'
services:
  vpnkit:
    env_file:
      - .env
YAML
cat >"$remote_root/workdir/.rollback/vpnkit/20260610T000000Z/rollback.sh" <<'ROLLBACK'
#!/usr/bin/env bash
echo rollback_payload=ran
ROLLBACK
chmod +x "$remote_root/workdir/.rollback/vpnkit/20260610T000000Z/rollback.sh"

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
# cmd shape: bash -s -- 'mode' 'target_ref' 'rollback_id'
mode=$(printf '%s\n' "$cmd" | sed -E "s/.*-- '([^']*)' '([^']*)' '([^']*)'.*/\1/")
target_ref=$(printf '%s\n' "$cmd" | sed -E "s/.*-- '([^']*)' '([^']*)' '([^']*)'.*/\2/")
rollback_id=$(printf '%s\n' "$cmd" | sed -E "s/.*-- '([^']*)' '([^']*)' '([^']*)'.*/\3/")
PATH="$VPNKIT_MOCK_REMOTE_BIN:$PATH" VPNKIT_MOCK_REMOTE_ROOT="$VPNKIT_MOCK_REMOTE_ROOT" bash -s -- "$mode" "$target_ref" "$rollback_id" <<<"$script"
MOCK
chmod +x "$fakebin/ssh"

cat >"$remote_root/bin/date" <<'MOCK'
#!/usr/bin/env bash
printf '20260610T000000Z\n'
MOCK
cat >"$remote_root/bin/git" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  rev-parse) printf 'abc123mock\n' ;;
  fetch) echo git_fetch=ok ;;
  checkout) echo "git_checkout=$3" ;;
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
    if [[ "${2:-}" == up ]]; then echo "compose_up=${*:3}"; exit 0; fi
    ;;
  ps)
    echo mock-container
    ;;
  inspect)
    if [[ "$*" == *'{{.Config.Image}}'* ]]; then echo 'vpnkit:test-tag'; exit 0; fi
    if [[ "$*" == *'{{.Image}}'* ]]; then echo 'sha256:mockimageid'; exit 0; fi
    if [[ "$*" == *'com.docker.compose.project.working_dir'* ]]; then echo "$root/workdir"; exit 0; fi
    if [[ "$*" == *'com.docker.compose.service'* ]]; then echo vpnkit; exit 0; fi
    if [[ "$*" == *'com.docker.compose.project'* ]]; then echo vpnkit-prod; exit 0; fi
    if [[ "$*" == *'{{.State.Running}}'* ]]; then echo true; exit 0; fi
    if [[ "$*" == *'1194/udp'* ]]; then echo udp_1194=mapped; exit 0; fi
    echo '[{"mock":"inspect"}]'
    ;;
  cp)
    dest=${3:-}
    if [[ "$dest" == *sing-box-config.json ]]; then echo '{"mock":"sing-box"}' >"$dest"; fi
    exit 0
    ;;
  exec)
    echo openvpn=up
    echo tun0=present
    echo singbox=up
    echo singbox_check=ok
    echo sb_tun0=present
    echo policy_rule=ok
    echo route_table=ok
    echo udp_1194_listener=ok
    printf 'token=%s\n' 'mock-secret-output'
    ;;
  *) echo "docker_$1=ok" ;;
esac
MOCK
chmod +x "$remote_root/bin/date" "$remote_root/bin/git" "$remote_root/bin/docker"

mock_secret_output=mock-secret-output
mock_env=(env VPNKIT_PROD_DEPLOY_TIMEOUT_BIN="$fakebin/timeout" VPNKIT_PROD_SSH_CMD="$fakebin/ssh" VPNKIT_MOCK_REMOTE_BIN="$remote_root/bin" VPNKIT_MOCK_REMOTE_ROOT="$remote_root")
check_ok "${mock_env[@]}" "$script" verify host-a
assert_grep 'mock_ssh_host=host-a'
assert_grep 'container_running=ok'
assert_grep 'token=<redacted>'
assert_not_grep "token=${mock_secret_output}"

check_ok "${mock_env[@]}" "$script" rollback --yes host-a
assert_grep 'rollback_start=.rollback/vpnkit/20260610T000000Z'
assert_grep 'rollback_payload=ran'

check_ok "${mock_env[@]}" "$script" deploy --yes --target-ref main host-a host-b
if [[ $(grep -c 'mock_ssh_host=' /tmp/vpnkit-prod-deploy-test.out) -ne 2 ]]; then echo "mock deploy did not sequence two hosts"; fail=1; fi
assert_grep 'rollback_bundle=.rollback/vpnkit/20260610T000000Z'
assert_grep 'deploy=ok'
bundle="$remote_root/workdir/.rollback/vpnkit/20260610T000000Z"
for artifact in git-ref.txt image-ref.txt image-id.txt container-inspect.json sing-box-config.json compose-files.txt compose-file.txt env-references.txt rollback.sh; do
  if [[ ! -s "$bundle/$artifact" ]]; then echo "missing rollback artifact: $artifact"; fail=1; fi
done
assert_grep 'vpnkit:test-tag' "$bundle/image-ref.txt"
assert_grep 'sha256:mockimageid' "$bundle/image-id.txt"
assert_grep 'compose.yaml' "$bundle/compose-files.txt"
assert_grep 'VPNKIT_PROD_WORKDIR=<unset>' "$bundle/env-references.txt"
assert_grep 'compose_env_file_section=compose.yaml' "$bundle/env-references.txt"
assert_not_grep 'secret|token=|password=|PRIVATE|BEGIN ' "$bundle/env-references.txt"

exit "$fail"
