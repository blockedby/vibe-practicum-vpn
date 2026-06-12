# Slice owner progress: runtime data-path / DNS / SOCKS

- Read repo guidance and current Steam Deck lab plan/evidence.
- Kept slice whole: one lab runtime config fix and one live lifecycle verification story.
- Identified confirmed lab-only causes from prior live logs plus render behavior:
  - dummy VLESS `selected-native-out` to `127.0.0.1:443` makes SOCKS/default egress impossible in lab;
  - pushed DNS `10.89.0.1` targets local OpenVPN server `tun0`, bypassing sing-box TUN in tun mode.
- Implemented explicit renderer knobs:
  - `VPNKIT_SELECTED_OUTBOUND_MODE=proxy|direct-fixture` (renderer default `proxy`, lab default `direct-fixture`);
  - `VPNKIT_OPENVPN_PUSH_DNS` (renderer default `10.89.0.1`, lab default `172.19.0.1`).
- Updated README and smart-routing proof.
- Local checks passed; live Deck sequence blocked because `config/private-endpoints.local.env` is absent in this worktree.
