openvpn_status=ready
outer_route_dev=tun0
outer_dns_github=ok
outer_ping_1_1_1_1=ok loss=0%
outer_ping_8_8_8_8=ok loss=0%
outer_https_github=ok code=200 remote_hash=5e1633ad
sing-box version 1.13.13
singbox_check=ok_without_deprecated_dns_env
singbox_status=no_tun
+0000 2026-06-09 14:10:19 [36mINFO[0m network: updated default interface eth0, index 2
[33mWARN[0m[0000] legacy `download_detour` remote rule-set option is deprecated in sing-box 1.14.0 and will be removed in sing-box 1.16.0.
+0000 2026-06-09 14:10:19 [37mDEBUG[0m router: updating rule-set geoip-ru from URL: https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geoip/geoip-ru.srs
+0000 2026-06-09 14:10:19 [37mDEBUG[0m router: updating rule-set geosite-category-ru from URL: https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite/geosite-category-ru.srs
+0000 2026-06-09 14:10:19 [36mINFO[0m outbound/direct[direct-out]: outbound connection to raw.githubusercontent.com:443
+0000 2026-06-09 14:10:19 [37mDEBUG[0m dns: lookup domain raw.githubusercontent.com
+0000 2026-06-09 14:10:19 [36mINFO[0m outbound/direct[direct-out]: outbound connection to raw.githubusercontent.com:443
+0000 2026-06-09 14:10:19 [37mDEBUG[0m dns: lookup domain raw.githubusercontent.com
+0000 2026-06-09 14:10:19 [37mDEBUG[0m outbound/vless[selected-native-out]: outbound connection to <IP>:853
+0000 2026-06-09 14:10:19 [37mDEBUG[0m outbound/vless[selected-native-out]: outbound connection to <IP>:853
+0000 2026-06-09 14:10:29 [33mWARN[0m router: initialize rule-set take too much time to finish!
+0000 2026-06-09 14:10:29 [37mDEBUG[0m dns: lookup failed for raw.githubusercontent.com: context deadline exceeded
+0000 2026-06-09 14:10:29 [37mDEBUG[0m outbound/vless[selected-native-out]: outbound connection to <IP>:853
+0000 2026-06-09 14:10:29 [37mDEBUG[0m outbound/vless[selected-native-out]: outbound connection to <IP>:853
+0000 2026-06-09 14:10:29 [37mDEBUG[0m dns: lookup failed for raw.githubusercontent.com: initialize rule-set[0]: initial rule-set: geoip-ru: Get "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geoip/geoip-ru.srs": lookup raw.githubusercontent.com: context deadline exceeded
[31mFATAL[0m[0010] start service: (initialize rule-set[0]: initial rule-set: geoip-ru: Get "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geoip/geoip-ru.srs": lookup raw.githubusercontent.com: context deadline exceeded | initialize rule-set[1]: initial rule-set: geosite-category-ru: Get "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite/geosite-category-ru.srs": lookup raw.githubusercontent.com: initialize rule-set[0]: initial rule-set: geoip-ru: Get "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geoip/geoip-ru.srs": lookup raw.githubusercontent.com: context deadline exceeded)
