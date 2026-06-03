# Next task: finish vpnkit sing-box TUN-mode validation

## Current state

Branch/worktree:

```text
branch: vpnkit-tproxy-udp-nested
worktree: /home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vpnkit-tproxy-udp-nested
```

Relevant latest evidence:

```text
docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/tun-canary-runtime.md
docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/tun-canary-result-matrix.md
docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/aad-implementer-tun-canary-validation.md
```

Implemented already:

- Opt-in `VPNKIT_ROUTING_MODE=tun` path exists.
- Default production `redirect` mode is intended to remain unchanged.
- Local Docker lab TUN mode passed:
  - OpenVPN connect.
  - UDP DNS `NOERROR`.
  - HTTPS `200`.
  - Literal-IP HTTPS `200`.
  - `sb-tun0` RX/TX counters incremented.
- Isolated live `vibe-practicum` TUN server on `21631/udp` proved public non-DNS UDP with a Python UDP client:
  - local disposable OpenVPN client route to public echo endpoint used outer `tun0`;
  - public echo endpoint on `moscow-tiger` received UDP from `45.12.74.211`;
  - local client received echo response.

Important distinction:

- TPROXY public UDP variants failed.
- TUN mode public UDP echo passed in the local-host-client -> isolated `vibe-practicum` TUN server -> `moscow-tiger` public echo topology.

## Hard constraints

Do **not** mutate production containers:

- Do not restart/recreate/adopt/remove/change production `vpnkit` on `vibe-practicum`.
- Do not restart/recreate/adopt/remove/change production `current-vpnkit-1` on `moscow-tiger`.
- Do not touch Steam Deck.

Use only isolated resources:

- Fresh high UDP ports.
- Unique Docker project/container/network/volume names.
- Temp paths under `/tmp` or gitignored paths only.
- Generated profiles, rendered configs, logs, tcpdump output, tarballs, and secrets must not be committed or printed.
- Commit only source/tests/docs/reports.

## What needs to be finished

### 0. Cleanup/status preflight

Before starting new tests, verify and clean any leftovers from the interrupted TUN run.

Known previous isolated names/ports:

```text
vibe-practicum:
  vpnkit_tun_live_21631
  vpnkit_tun_inner_21632
  vpnkit_tun_net_21631_21632
  /tmp/vpnkit_tun21631_server

moscow-tiger:
  vpnkit-tun-echo-tun21631
  vpnkit-tun-echo-reprobe-21634
  vpnkit-tun-echo-reprobe-21635
  /tmp/vpnkit_tun21631_moscow
```

A cleanup command was issued for those known resources, but final `moscow-tiger` listing was not confirmed because SSH port 22 timed out. First action should be a read-only/safe status check and exact-name cleanup if anything remains.

Record sanitized production metadata before and after:

```text
vibe-practicum production: docker inspect vpnkit status/restart/start-time only
moscow-tiger production: docker inspect current-vpnkit-1 status/restart/start-time only
```

### 1. Fix the live TUN validation harness

The prior live wrapper had shell/path/quoting bugs and should not be reused blindly.

Build a simpler harness with explicit steps:

1. Package current worktree and matching gitignored rendered material without printing contents.
2. Copy to `/tmp/<fresh-name>` on `vibe-practicum`.
3. Start isolated outer TUN vpnkit server on fresh high UDP port.
4. Optionally start isolated inner server on a fresh high UDP port and shared private Docker network.
5. Generate temp client profiles by rewriting only `remote` lines and, for inner OpenVPN, `dev tun1` plus non-conflicting inner subnet if needed.
6. Run local host client container first.
7. Run `moscow-tiger` client container second.
8. Always cleanup by exact names/paths in a trap.

Avoid broad `/tmp` scans. Use exact temp names.

### 2. Required validation matrix

Run all feasible stages. Do not stop at first pass.

#### Stage A: local-host client -> isolated `vibe-practicum` TUN server

Acceptance evidence:

- OpenVPN outer tunnel up.
- Route to public UDP echo endpoint uses outer `tun0`.
- Public UDP echo succeeds using Python UDP client, not bash `/dev/udp`.
- UDP DNS `NOERROR`.
- HTTPS hostname `200`.
- Literal-IP HTTPS `200`.
- `sb-tun0` RX/TX counters increment.
- No redirect/tproxy capture chains are used in TUN mode.

#### Stage B: local-host client nested OpenVPN through isolated TUN server

Acceptance evidence:

- Outer `tun0` up.
- Route to inner OpenVPN endpoint uses outer `tun0`.
- Inner `tun1` up.
- Inner server assigns inner tunnel address.
- If this fails, capture sanitized sing-box TUN logs showing destination and outbound route, plus route/counter summaries.

#### Stage C: `moscow-tiger` client -> isolated `vibe-practicum` TUN server

Acceptance evidence:

- OpenVPN outer tunnel up from isolated client container on `moscow-tiger`.
- UDP DNS `NOERROR`.
- HTTPS hostname `200`.
- Literal-IP HTTPS `200`.
- Public UDP echo through outer tunnel succeeds, preferably to an echo endpoint not on the same host as the client unless route proof shows it uses outer `tun0`.

#### Stage D: `moscow-tiger` client nested OpenVPN through isolated TUN server

Acceptance evidence:

- Outer `tun0` up on `moscow-tiger` client container.
- Route to inner endpoint uses outer `tun0`.
- Inner `tun1` up.
- Inner server accepts client.

### 3. If something fails

Do not guess. Capture decisive sanitized evidence:

- `ip route get <target>` from client.
- `ip addr show tun0/tun1` from client.
- `ip addr show sb-tun0`, `ip rule show`, `ip route show table 101` from server.
- `ip -s link show sb-tun0` before/after.
- sing-box logs filtered to lines containing `inbound/tun`, destination, outbound tag, `packet connection`, `error`, `warn`.
- UDP echo server received count and source address, but no raw secrets.
- Production metadata unchanged.

### 4. Cleanup requirements

At end, remove all isolated resources:

- Docker compose projects.
- Containers/images created for clients/echo.
- Networks/volumes.
- Temp paths on local host, `vibe-practicum`, and `moscow-tiger`.

Then run final exact-name leftover checks for all fresh prefixes and ports.

### 5. Documentation/commit requirements

Update or create:

```text
docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/verification/tun-live-complete-matrix.md
docs/plans/2026-06-03-tproxy-udp-nested-vpnkit/reports/tun-live-complete-report.md
```

The report must include:

- ports/names used;
- pass/fail matrix for Stage A-D;
- public UDP echo result;
- nested OpenVPN result;
- cleanup status;
- production untouched evidence;
- final recommendation: whether TUN mode is ready for a guarded production canary or still blocked.

Run before commit:

```bash
bash tests/vpnkit-singbox-template-test.sh
bash tests/vpnkit-setup-routing-test.sh
bash -n docker/vpnkit/*.sh scripts/*.sh tests/*.sh
go test ./...
git diff --check
```

Commit only source/test/docs/report changes. Do not commit generated `.ovpn`, rendered configs, logs, tarballs, or secrets.

## Suggested final verdict criteria

TUN mode can be considered ready for the next guarded production-canary planning step only if:

- Stage A public UDP echo passes.
- Stage C public UDP echo passes from `moscow-tiger` client or an equivalent different-host client.
- Baseline DNS/HTTPS/literal smoke passes in both local-host and different-host client cases.
- No production metadata changes occur.
- Cleanup is complete.

Nested OpenVPN Stage B/D is highly desirable. If public UDP passes but nested OpenVPN fails, classify separately as nested-profile/MTU/routing issue, not as generic TUN UDP failure.
