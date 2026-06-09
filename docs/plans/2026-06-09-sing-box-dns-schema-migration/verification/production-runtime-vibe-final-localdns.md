== vibe-practicum deploy ==
workdir=discovered service=vpnkit project=src
rollback=prepared tag=vpnkit-rollback:20260609T142256Z env_backup=.rollback/vpnkit/singbox-dns-20260609T142256Z/env runtime_backup=.rollback/vpnkit/singbox-dns-20260609T142256Z/runtime-config.json
render=singbox-only-fallback
rendered_check=ok
 Image src-vpnkit Building 
 Image src-vpnkit Built 
 Container src-vpnkit-1 Recreate 
 Container src-vpnkit-1 Recreated 
 Container src-vpnkit-1 Starting 
 Container src-vpnkit-1 Started 
deploy=recreated
deprecated_env=absent
singbox_check=ok
routing_mode=tun
openvpn=up
tun0=present
singbox=up
sb_tun0=present
policy_rule=ok
route_table=ok
udp_1194_listener=ok
udp_1194=mapped
