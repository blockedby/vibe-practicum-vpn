#!/usr/bin/env bash
# Exercise the host helper against a real disposable Linux network namespace.
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
image=${VPNKIT_LOCAL_UNDERLAY_TEST_IMAGE:-vpnkit-local-lab-vpnkit}
name=${VPNKIT_LOCAL_UNDERLAY_TEST_CONTAINER:-vpnkit-route-helper-lab-$$}
cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM

docker image inspect "$image" >/dev/null 2>&1 || {
  echo "missing test image: $image (run local-docker fixture build first)" >&2
  exit 2
}

docker run --rm --privileged --name "$name" \
  -v "$root:/src:ro" --entrypoint bash "$image" -lc '
set -Eeuo pipefail
mkdir -p /tmp/mockbin /sandbox
cat >/tmp/mockbin/systemctl <<"EOF"
#!/usr/bin/env bash
exit 0
EOF
chmod +x /tmp/mockbin/systemctl
export PATH=/tmp/mockbin:$PATH
export VPNKIT_LOCAL_UNDERLAY_ROOT=/sandbox
export VPNKIT_LOCAL_DOCKER_SUBNET=198.18.0.0/24
helper=/src/scripts/vpnkit/vpnkit-local-underlay-routing.sh
$helper plan | grep -q "install_preflight=ready"
$helper install --yes >/dev/null
$helper verify >/dev/null
installed=/sandbox/usr/local/libexec/vpnkit-local-underlay-routing
$installed --runtime-refresh
$helper verify >/dev/null
$helper install --yes >/dev/null
$helper verify >/dev/null
$helper uninstall --yes >/dev/null
! ip -4 rule show | grep -Eq "198\.18\.0\.0/24|lookup 51840"
if ip -4 route show table 51840 >/tmp/table 2>/dev/null; then test ! -s /tmp/table; fi
for p in \
 /sandbox/etc/vpnkit-local-underlay-routing.conf \
 /sandbox/usr/local/libexec/vpnkit-local-underlay-routing \
 /sandbox/etc/systemd/system/vpnkit-local-underlay-routing.service \
 /sandbox/etc/NetworkManager/dispatcher.d/90-vpnkit-local-underlay-routing; do
  test ! -e "$p"
done
printf "actual_kernel_underlay_lab=pass\n"
'
