#!/usr/bin/env bash
set -euo pipefail
script=${1:-scripts/vpnkit-prod-deploy.sh}
fail=0
check_fail() { if "$@" >/tmp/vpnkit-prod-deploy-test.out 2>&1; then echo "expected failure: $*"; fail=1; fi; }
check_ok() { if ! "$@" >/tmp/vpnkit-prod-deploy-test.out 2>&1; then echo "expected success: $*"; cat /tmp/vpnkit-prod-deploy-test.out; fail=1; fi; }
check_fail "$script" deploy --target-ref main example.invalid
if ! grep -q -- "deploy requires --yes" /tmp/vpnkit-prod-deploy-test.out; then echo "missing deploy refusal"; fail=1; fi
check_fail "$script" rollback example.invalid
if ! grep -q -- "rollback requires --yes" /tmp/vpnkit-prod-deploy-test.out; then echo "missing rollback refusal"; fail=1; fi
check_ok "$script" plan --target-ref main example.invalid
if grep -Eq '([0-9]{1,3}\.){3}[0-9]{1,3}|secret|token=[^<]' /tmp/vpnkit-prod-deploy-test.out; then echo "plan output not redacted"; fail=1; fi
check_ok env VPNKIT_PROD_DEPLOY_HOSTS='example.invalid example2.invalid' "$script" dry-run --target-ref main
if [[ $(grep -c 'mutation=none' /tmp/vpnkit-prod-deploy-test.out) -ne 2 ]]; then echo "env host list not handled sequentially"; fail=1; fi
exit "$fail"
