== moscow-tiger deploy ==
workdir=discovered service=vpnkit project=current
rollback=prepared tag=vpnkit-rollback:20260609T142100Z env_backup=.rollback/vpnkit/singbox-dns-20260609T142100Z/env runtime_backup=.rollback/vpnkit/singbox-dns-20260609T142100Z/runtime-config.json
render=full
rendered_check=ok
time="2026-06-09T17:21:02+03:00" level=warning msg="project has been loaded without an explicit name from a symlink. Using name \"current\""
 Image current-vpnkit Building 
 Image current-vpnkit Built 
 Container current-vpnkit-1 Recreate 
 Container current-vpnkit-1 Recreated 
 Container current-vpnkit-1 Starting 
 Container current-vpnkit-1 Started 
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
