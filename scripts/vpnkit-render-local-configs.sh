#!/usr/bin/env bash
set -euo pipefail
BASE=${VPNKIT_SECRETS_DIR:-secrets/vps}
RENDERED="$BASE/rendered"
mkdir -p "$RENDERED/openvpn/pki" "$RENDERED/openvpn/ccd" "$RENDERED/sing-box" "$BASE/openvpn/client"
cp config/openvpn/server.tpl "$RENDERED/openvpn/server.conf"
cp "$BASE/openvpn/pki/ca.crt" "$BASE/openvpn/pki/ta.key" "$BASE/openvpn/pki/vibe-asus.crt" "$BASE/openvpn/pki/vibe-asus.key" "$RENDERED/openvpn/pki/"
cp "$BASE/openvpn/server/ccd-ignat" "$RENDERED/openvpn/ccd/ignat" 2>/dev/null || true
python3 - "$BASE/sing-box/tproxy-canary.json" config/sing-box/config.json.template "$RENDERED/sing-box/config.json" <<'PY'
import json, sys
src, tmpl, out = sys.argv[1:]
data=json.load(open(src))
vless=[o for o in data.get('outbounds',[]) if o.get('tag')=='selected-native-out' and o.get('type')=='vless']
if not vless:
    raise SystemExit('selected-native-out vless outbound not found')
text=open(tmpl).read().replace('{{SELECTED_NATIVE_OUT_JSON}}', json.dumps(vless[0], indent=4))
open(out,'w').write(text)
PY
python3 - "$BASE/openvpn/pki" config/openvpn/test-client.ovpn.template "$BASE/openvpn/client/test-client.ovpn" <<'PY'
import pathlib, sys
p=pathlib.Path(sys.argv[1]); text=pathlib.Path(sys.argv[2]).read_text()
repl={
 '{{CA_CRT}}':(p/'ca.crt').read_text().strip(),
 '{{CLIENT_CRT}}':(p/'ignat.crt').read_text().strip(),
 '{{CLIENT_KEY}}':(p/'ignat.key').read_text().strip(),
 '{{TA_KEY}}':(p/'ta.key').read_text().strip(),
}
for k,v in repl.items(): text=text.replace(k,v)
pathlib.Path(sys.argv[3]).write_text(text)
PY
chmod 600 "$RENDERED/sing-box/config.json" "$BASE/openvpn/client/test-client.ovpn"
echo "Rendered $RENDERED/openvpn/server.conf, $RENDERED/sing-box/config.json, and $BASE/openvpn/client/test-client.ovpn"
