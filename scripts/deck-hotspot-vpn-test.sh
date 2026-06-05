#!/usr/bin/env bash
set -Eeuo pipefail

SSH_TARGET=${DECK_HOTSPOT_SSH_TARGET:-${VPNKIT_STEAMDECK_SSH_TARGET:-deck}}
HOTSPOT_IFACE=${DECK_HOTSPOT_IFACE:-ap0}
VPN_IFACE=${DECK_HOTSPOT_VPN_IFACE:-tun0}
REPORT_PATH=${DECK_HOTSPOT_REPORT_PATH:-}
SSH_OPTS=()

usage(){ cat <<'EOF'
Usage: scripts/deck-hotspot-vpn-test.sh [--ssh-target deck] [--hotspot-iface ap0] [--vpn-iface tun0] [--report PATH]

Run Deck-side gateway checks and write redacted report. Does not mutate state.
Client devices should additionally run the commands printed at the end while
connected to the Deck hotspot.
EOF
}
while [[ $# -gt 0 ]]; do case "$1" in
  --ssh-target) SSH_TARGET=${2:?}; shift 2;; --hotspot-iface) HOTSPOT_IFACE=${2:?}; shift 2;; --vpn-iface) VPN_IFACE=${2:?}; shift 2;;
  --report) REPORT_PATH=${2:?}; shift 2;; --ssh-option) read -r -a opt <<< "${2:?}"; SSH_OPTS+=("${opt[@]}"); shift 2;;
  -h|--help) usage; exit 0;; *) echo "unknown argument: $1" >&2; usage >&2; exit 2;;
esac; done
[[ "$HOTSPOT_IFACE$VPN_IFACE" =~ ^[A-Za-z0-9_.:-]+$ ]] || { echo "unsafe iface name" >&2; exit 2; }
[[ -n "$REPORT_PATH" ]] || REPORT_PATH="reports/steam-deck-hotspot-test-$(date -u +%Y%m%dT%H%M%SZ).md"
mkdir -p "$(dirname "$REPORT_PATH")"
redact(){ sed -E -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g' -e 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<MAC>/Ig' -e 's/[0-9a-f]{4}(:[0-9a-f]{0,4}){2,7}/<IPv6>/Ig' -e 's/[0-9a-f]{8}-[0-9a-f-]{27,}/<UUID>/Ig' -e 's/(Machine ID:).*/\1 <redacted>/I' -e 's/(Boot ID:).*/\1 <redacted>/I'; }
{
  echo "# Steam Deck hotspot VPN test report"
  echo
  echo "- Timestamp: $(date -u +%FT%TZ)"
  echo "- SSH target: <redacted>"
  echo "- Mutation: none/read-only"
  echo
  echo '```text'
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "HOTSPOT_IFACE='$HOTSPOT_IFACE' VPN_IFACE='$VPN_IFACE' bash -s" <<'REMOTE'
set -Eeuo pipefail
log(){ printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
hash8(){ if command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | cut -c1-8; elif command -v md5sum >/dev/null 2>&1; then printf '%s' "$1" | md5sum | cut -c1-8; else printf unavailable; fi; }
ping_probe(){ target=$1; if ping -4 -c 1 -W 1 "$target" >/dev/null 2>&1; then ping -4 -c 3 -W 3 "$target" || true; else ping -c 3 -W 3 "$target" || true; fi; }
fetch(){ name=$1; url=$2; if command -v curl >/dev/null 2>&1; then body=$(curl -4fsS --max-time 15 "$url" 2>/tmp/${name}.err) && rc=0 || rc=$?; else echo "$name=skip no_curl"; return; fi; if [[ $rc -eq 0 ]]; then ip=$(printf '%s\n' "$body" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true); [[ -n $ip ]] && echo "$name=ok ip_hash=$(hash8 "$ip")" || echo "$name=ok body_hash=$(hash8 "$body")"; else echo "$name=fail rc=$rc"; fi; }
log "interfaces"
ip -br addr || true
log "routes"
ip route get 1.1.1.1 || true
ip route get 8.8.8.8 || true
log "vpn iface"
ip link show "$VPN_IFACE" || true
log "hotspot iface"
ip link show "$HOTSPOT_IFACE" || true
log "icmp"
ping_probe 1.1.1.1
ping_probe 8.8.8.8
log "dns"
if command -v nslookup >/dev/null 2>&1; then nslookup x.com 8.8.8.8 || true; nslookup ya.ru 8.8.8.8 || true; nslookup www.linkedin.com 8.8.8.8 || true; fi
log "ip identity"
fetch ip_ifconfig_me https://ifconfig.me
fetch ip_ipify https://api.ipify.org
log "https"
fetch https_x https://x.com/
fetch https_ya https://ya.ru/
fetch https_linkedin https://www.linkedin.com/
log "nft tables relevant"
command -v nft >/dev/null 2>&1 && sudo nft list tables | grep vpnkit || true
REMOTE
  echo '```'
  cat <<'CLIENT'

## Client-side checks to run while connected to the Deck hotspot

```bash
ip route get 1.1.1.1 || true
ping -4 -c 3 1.1.1.1
ping -4 -c 3 8.8.8.8
nslookup x.com
nslookup ya.ru
nslookup www.linkedin.com
curl -4 --max-time 20 https://x.com/ -o /dev/null -w 'x=%{http_code}\n'
curl -4 --max-time 20 https://ya.ru/ -o /dev/null -w 'ya=%{http_code}\n'
curl -4 --max-time 20 https://www.linkedin.com/ -o /dev/null -w 'linkedin=%{http_code}\n'
curl -4 --max-time 20 https://ifconfig.me
curl -4 --max-time 20 https://api.ipify.org
curl -6 --max-time 10 https://ifconfig.me || true
```
CLIENT
} 2>&1 | redact | tee "$REPORT_PATH"
printf 'report_path=%s\n' "$REPORT_PATH"
