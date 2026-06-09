# Slice B verification — smart routing/adblock/dev-direct

Fresh local checks (2026-06-09):

| Check | Result | Evidence |
| --- | --- | --- |
| `python3 test/sing-box-smart-routing-proof.py` | PASS | `PASS sing-box smart routing proof: adblock/dev-direct/RU/default decisions and template invariants` |
| `bash -n scripts/*.sh test/*.sh` | PASS | No output; shell syntax accepted for existing scripts and shell tests. |
| Temp render probe with dummy public-safe secret tree and `VPNKIT_ROUTING_MODE=tun scripts/vpnkit-render-local-configs.sh` | PASS with expected missing-subscription warning | Rendered config parsed; `/rendered/sing-box/rule-sets/vpnkit-adblock.json` and `vpnkit-dev-direct.json` existed; policy order was adblock, dev-direct, RU geoip, RU geosite. |

Acceptance mapping:

- AC5: Covered by template parse/proof and temp render probe. Both redirect and TUN templates retain DNS hijack/sniff before policy rules, add local adblock/dev-direct rule sets, retain RU direct rules, and keep final `selected-native-out`. `config/openvpn/server.tpl` still contains `push "redirect-gateway def1 bypass-dhcp"`, `tun-mtu 1400`, and `mssfix 1360`.
- AC6: Covered by deterministic samples in `test/sing-box-smart-routing-proof.py`: ad domains (`ads.doubleclick.net`, `pagead2.googlesyndication.com`) -> `block-out`; dev/package domains (`github.com`, `codeload.githubusercontent.com`, `registry.npmjs.org`, `pypi.org`) -> `direct-out`; RU sample (`example.ru`) -> `direct-out`; ordinary foreign (`foreign-news.example.com`) -> final `selected-native-out`. Remote RU rule-set entries are asserted as HTTPS binary rule sets with `download_detour: direct-out`.

Limitations:

- This is repo-local config/fixture evidence only. No live sing-box process, remote rule-set download, cache reuse, Deck, or production mutation was performed or claimed.
