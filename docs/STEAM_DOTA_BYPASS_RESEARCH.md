# Steam/Dota bypass research

Date: 2026-05-03

## Goal

Route Steam/Dota 2 on Arch/Linux outside the VPN/VPS path while keeping normal browser/default traffic through the existing VPN/VPS path.

Desired policy:

```text
browser/OpenAI/Google/default -> VPN/VPS/VLESS
Steam/Dota                  -> local ISP / physical interface
```

## Important lesson from previous attempt

Do **not** assume that the existing local sing-box TUN config will work if simply applied again.

Previous attempt failed and is documented in:

```text
docs/KCNC_SAFE_TUN_POSTMORTEM.md
```

Key observed evidence:

```text
open-conn-track: timeout opening (TCP 100.68.65.56:45524 => 198.18.0.0:80); no associated peer node
```

`198.18.0.0/15` is commonly used for fake-IP DNS/proxy modes. This suggests the test was not a clean sing-box process-routing test; it was likely a mixed stack involving active V2RayA/fake-IP, system DNS, sing-box TUN, Tailscale, and VPS routing.

## Why `process_name = dota2` is not enough

Steam on Linux can launch games through multiple wrapper/runtime processes:

- `steam`
- `steamwebhelper`
- `pressure-vessel`
- `pressure-vessel-adverb`
- `bwrap`
- Steam Linux Runtime (`sniper`, `soldier`, etc.)
- Proton/Wine wrappers for Proton titles

Even if the game is visually Dota 2, host-side socket/process lookup may see a wrapper process, not `dota2`.

sing-box supports Linux process matching (`process_name`, `process_path`, `process_path_regex`, `user`, `user_id`), but Linux process lookup is not perfect. Related sing-box issue reports mention errors such as:

```text
router: failed to search process: netlink message: NLMSG_ERROR
```

Therefore, process-based bypass must be verified from sing-box debug logs, not assumed.

## DNS problem

Steam/Dota DNS may not originate from the Dota process. It can come from:

- `systemd-resolved`
- NetworkManager
- V2RayA DNS/fake-IP layer
- Steam helper processes
- browser/webhelper components

So traffic rules matching `dota2` may not affect DNS. If DNS returns fake-IP addresses or VPN-resolved CDN endpoints, game traffic can still fall into the wrong path.

Known problematic pattern:

```text
TUN + hijack-dns + fake-ip + systemd-resolved
```

This can produce DNS loops or bad classification, especially when fake-IP addresses like `198.18.0.0/15` appear.

## Research conclusion

The previous config did not prove that sing-box process bypass is impossible. It proved that applying local sing-box TUN on top of the active V2RayA/fake-IP environment is unsafe and inconclusive.

Before another attempt, gather evidence while Dota is actually running.

## Forensic checklist before changing routes

Run with Steam/Dota open.

### 1. Find relevant processes

```bash
pgrep -af 'steam|dota|pressure|bwrap|soldier|sniper|proton|wine'
```

### 2. Check host-visible sockets

```bash
sudo ss -tunap | grep -Ei 'steam|dota|pressure|bwrap|wine|proton'
```

### 3. Check whether Dota/Steam Runtime uses a separate network namespace

For a candidate PID:

```bash
PID=<pid>
readlink /proc/$PID/ns/net
readlink /proc/1/ns/net
```

If they differ, inspect from inside the namespace:

```bash
sudo nsenter -t $PID -n ss -tunap
sudo nsenter -t $PID -n ip route
sudo nsenter -t $PID -n cat /etc/resolv.conf
```

### 4. Look for fake-IP evidence

```bash
sudo ss -tunap | grep '198.18.'
ip route get 198.18.0.1
resolvectl query steamcommunity.com
resolvectl query dota2.com
```

Any `198.18.x.x` result means fake-IP is still involved and process-based bypass results are not clean.

### 5. If testing sing-box again, require debug logs

Use `log.level = debug` and verify actual matches:

```text
router: found process path: ...
match process_path_regex => route(local-internet)
outbound/direct[local-internet]
```

If logs do not explicitly show Dota/Steam matching `local-internet`, the bypass is not proven.

## Candidate solutions

### Option A: clean sing-box TUN test, no V2RayA/fake-IP

Only test after V2RayA/fake-IP is stopped or isolated.

Use process rules for all observed Steam Runtime processes and paths, then verify by debug logs.

Pros:

- fits current architecture;
- keeps normal traffic through VPS;
- simplest if process lookup works.

Cons:

- process lookup may miss wrapper/containerized traffic;
- DNS can still be tricky.

### Option B: run Steam under a dedicated Linux user

Use sing-box `user` or `user_id` rules:

```json
{
  "user": ["steamdirect"],
  "outbound": "local-internet"
}
```

Pros:

- more reliable than process names;
- all child processes should inherit the user.

Cons:

- desktop integration pain: GUI, audio, controllers, Steam library permissions.

### Option C: systemd cgroup/scope + nftables policy routing

Run Steam in a dedicated systemd user scope:

```bash
systemd-run --user --scope --unit=steam-direct.scope steam
```

Then route/mark the whole cgroup/scope outside VPN with nftables/policy routing.

Pros:

- more reliable for child processes than process names;
- avoids guessing every `pressure-vessel`/Proton subprocess.

Cons:

- more moving parts;
- nftables cgroup matching has lifecycle caveats: cgroup IDs can change when scopes are recreated.

### Option D: network namespace for Steam

Run Steam/Dota in a namespace with direct default route.

Pros:

- strongest isolation.

Cons:

- high desktop complexity: Wayland/X11, PipeWire/PulseAudio, controllers, Steam overlay, Proton.

## Current recommendation

Do not re-apply the old local TUN config blindly.

Next safe step should be a read-only diagnostic script, e.g.:

```text
scripts/diagnose-steam-dota-routing.sh
```

It should collect:

- Steam/Dota process tree;
- socket owners;
- network namespace info;
- routes from host and namespace;
- DNS/resolved state;
- fake-IP evidence;
- Tailscale/V2RayA/sing-box service state.

Only after this evidence should we decide between clean sing-box process routing, dedicated user, cgroup routing, or network namespace.
