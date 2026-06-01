# Slice owner progress

- Created package and preparing delegation.

## 2026-06-01 resumed end-to-end debug
- Resumed slice in existing worktree/branch per routing packet.
- Prior evidence shows OpenVPN client tunnel works and TPROXY rules match, but transparent userland accept failed.
- Keeping slice whole; next execution task is ordered debug sequence: scoped INPUT accept, minimal IP_TRANSPARENT listener, canonical routing, then TUN fallback if blocker remains.

## 2026-06-01 end-to-end result
- TPROXY with scoped INPUT accept still failed transparent socket delivery; minimal Perl `IP_TRANSPARENT` listener saw matched TPROXY counters but no accept.
- TUN fallback with sing-box `auto_route`/`auto_redirect` started but did not preserve original destinations when policy-routed from OpenVPN `tun0`.
- Implemented scoped REDIRECT final architecture: TCP -> sing-box redirect inbound `:2082`, UDP/53 -> sing-box direct inbound `:5353` + `hijack-dns`.
- Fresh Docker verification passed: client `10.89.0.2`, `dig` NOERROR, domain HTTPS 200, literal-IP HTTPS 200, sing-box `selected-native-out` logs for DNS/HTTPS.
