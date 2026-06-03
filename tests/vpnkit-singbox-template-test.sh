#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
placeholder = json.dumps({"type":"direct","tag":"selected-native-out"}, indent=4)

def load(rel):
    text = (root / rel).read_text().replace('{{SELECTED_NATIVE_OUT_JSON}}', placeholder)
    return json.loads(text)

redirect = load('config/sing-box/config.json.template')
tproxy = load('config/sing-box/config.tproxy.json.template')

def inbound_by_tag(cfg):
    return {inbound['tag']: inbound for inbound in cfg['inbounds']}

redirect_in = inbound_by_tag(redirect)
assert redirect_in['vpnkit-redirect-in']['type'] == 'redirect'
assert redirect_in['vpnkit-redirect-in']['listen_port'] == 2082
assert 'vpnkit-tproxy-in' not in redirect_in
assert redirect_in['vpnkit-dns-in']['type'] == 'direct'
assert redirect_in['vpnkit-dns-in']['listen_port'] == 5353

rules = redirect['route']['rules']
sniff = [rule for rule in rules if rule.get('action') == 'sniff'][0]
assert 'vpnkit-redirect-in' in sniff['inbound']
assert 'vpnkit-socks-in' in sniff['inbound']

tproxy_in = inbound_by_tag(tproxy)
assert tproxy_in['vpnkit-tproxy-in']['type'] == 'tproxy'
assert tproxy_in['vpnkit-tproxy-in']['listen_port'] == 2082
assert 'network' not in tproxy_in['vpnkit-tproxy-in']
assert tproxy_in['vpnkit-redirect-in']['type'] == 'redirect'
assert tproxy_in['vpnkit-redirect-in']['listen_port'] == 2083
assert tproxy_in['vpnkit-dns-in']['type'] == 'direct'
assert tproxy_in['vpnkit-dns-in']['listen_port'] == 5353

rules = tproxy['route']['rules']
udp_route = [rule for rule in rules if rule.get('inbound') == 'vpnkit-tproxy-in' and rule.get('network') == 'udp'][0]
assert udp_route['action'] == 'route'
assert udp_route['outbound'] == 'selected-native-out'
assert rules.index(udp_route) < next(i for i, rule in enumerate(rules) if rule.get('action') == 'sniff')
sniff = [rule for rule in rules if rule.get('action') == 'sniff'][0]
assert 'vpnkit-tproxy-in' in sniff['inbound']
assert 'vpnkit-redirect-in' in sniff['inbound']
assert 'vpnkit-socks-in' in sniff['inbound']
print('vpnkit sing-box templates ok')
PY
