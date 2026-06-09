== vibe-practicum deploy ==
workdir=discovered service=vpnkit project=src
rollback=prepared tag=vpnkit-rollback:20260609T141209Z env_backup=.rollback/vpnkit/singbox-dns-20260609T141209Z/env runtime_backup=.rollback/vpnkit/singbox-dns-20260609T141209Z/runtime-config.json
render=singbox-only-fallback
rendered_check=ok
 Image src-vpnkit Building 
 Image src-vpnkit Built 
 Container src-vpnkit-1 Recreate 
 Container src-vpnkit-1 Recreated 
 Container src-vpnkit-1 Starting 
 Container src-vpnkit-1 Started 
deploy=recreated
Error response from daemon: Container fa4d6bc7053bcd7afb48d3a4172d92b97e25e0b5347eba963b60c97a58bc2b14 is restarting, wait until the container is running
