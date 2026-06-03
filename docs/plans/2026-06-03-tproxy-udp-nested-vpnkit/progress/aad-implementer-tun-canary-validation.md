# Progress: aad-implementer TUN canary validation

- 2026-06-03: Entered optional Task 6 only after Task 5 checks passed. Safe prereq check (without printing values) showed Docker available and existing gitignored rendered OpenVPN/client configs present.
- 2026-06-03: Full `scripts/vpnkit-render-local-configs.sh` was blocked by missing gitignored source PKI files under `secrets/vps/openvpn/pki/`; existing rendered configs were present. Created only gitignored `secrets/vps/rendered/sing-box/config.tun.json` from existing rendered selected outbound without printing contents; `sing-box check` passed with deprecation env flags.
- 2026-06-03: Isolated local Docker lab `vpnkit_tun_canary_lab_21510` on `21510/udp` passed TUN readiness, baseline OpenVPN connect, UDP DNS `NOERROR`, HTTPS hostname `200`, and literal-IP HTTPS `200`. TUN interface counters incremented and redirect/tproxy capture chains were absent in tun mode.
- 2026-06-03: Cleanup completed via `docker compose -p vpnkit_tun_canary_lab_21510 down -v --remove-orphans`; no matching containers/networks remained. No live-host or production container mutation attempted.
