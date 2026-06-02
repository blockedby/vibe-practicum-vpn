# Moscow tiger runtime smoke fix plan

## Goal

Diagnose and fix the existing `moscow-tiger` Docker `vpnkit` runtime so a fresh Docker OpenVPN client smoke passes baseline checks: OpenVPN connection, tunnel address assignment, DNS `NOERROR`, HTTPS by hostname, HTTPS by literal IP, and RU/2ip-style routing evidence.

## Scope

In scope:
- Existing `moscow-tiger` target only.
- Evidence from Docker logs/config/processes/iptables and targeted in-container checks.
- Minimal safe runtime or repo/config fix for the confirmed cause.
- Public-safe docs/source commit only if a repository change is required.

Out of scope:
- Vercel/DNS mutation.
- Steam Deck.
- Mutation of unrelated existing `vibe-practicum` deployments.
- Committing real endpoints, rendered configs, generated profiles, subscription URLs, auth files, logs, snapshots, or private values.

## Constraints

- Load `config/private-endpoints.local.env` before live target commands; stop before live mutation if required values are missing.
- Do not record real endpoints or secrets in tracked task artifacts.
- Use local Docker lab as the default pre-live gate for runtime-affecting repo changes when practical.

## Acceptance criteria

AC1. Reproduce and classify the reported failure with sanitized evidence.
AC2. Inspect `moscow-tiger` runtime state: Docker containers/logs, rendered sing-box/OpenVPN/vibe-vpn config shape, relevant processes/listeners, routes, and iptables/nftables counters without exposing secrets.
AC3. Run targeted checks proving whether traffic fails at redirect/routing, selected native/proxy outbound, DNS hijack, route matching, or upstream/proxy selection.
AC4. Implement the smallest safe fix for the confirmed current-goal blocker, limited to runtime config or public-safe repo docs/source as needed.
AC5. Fresh host Docker OpenVPN client smoke is green for DNS, HTTPS hostname, HTTPS literal IP, and RU/2ip-style routing evidence, or unresolved blockers are reported honestly with evidence.
AC6. Public-safety check confirms no secrets/private artifacts are staged or committed.

## Ownership model

Single slice under `aad-slice-owner` because diagnosis, runtime fix, and final smoke share one target, one acceptance story, and one live-runtime verification path. No parallel slices are useful until root cause is classified.

## Delegated slice

### Slice 1: Runtime diagnosis, minimal fix, and smoke verification

Goal:
- Make the existing `moscow-tiger` runtime pass the requested Docker client smoke or report a hard blocker with evidence.

Boundary:
- System area: Docker `vpnkit` runtime on `moscow-tiger`, related public-safe repo docs/source if needed.
- Primary verification: fresh Docker OpenVPN client smoke and targeted in-container route/outbound checks.

Acceptance criteria:
- Covers AC1-AC6 above.

Expected report:
- `reports/slice-owner-runtime-diagnosis-fix.md`
- Include commands run with private values redacted, root cause classification, fix details, verification matrix, committed files/commit hash if any, and unresolved risks/follow-ups.

Status:
- blocked: delegated to `aad-slice-owner`; initial pre-live safety gate found `config/private-endpoints.local.env` absent in the active worktree.
- still blocked on continuation: the file is now present, but it contains the example placeholder `VPNKIT_VPS_SSH_HOST` value, which is not a resolvable operator-local SSH target. Live target inspection/mutation and fresh host Docker client smoke still cannot be run safely from this environment.

## Execution ledger

### 2026-06-02 — slice owner pre-live gate

- Read repo/worktree guidance and confirmed public-safety constraints.
- Confirmed task package paths are present.
- Checked for `config/private-endpoints.local.env`; result: absent.
- Stopped before SSH/live-runtime/client-smoke commands per repo rule: if required private endpoint values are absent, stop before live/runtime mutation.
- Verification artifact: `verification/runtime-smoke.md`.
- Report: `reports/slice-owner-runtime-diagnosis-fix.md`.

### 2026-06-02 — slice owner continuation pre-live gate

- Rechecked the task package after root owner copied `config/private-endpoints.local.env` into the worktree.
- Confirmed the file is present without printing values.
- Sourced it and attempted the narrowest live-read gate: `ssh -o BatchMode=yes "$VPNKIT_VPS_SSH_HOST" ...` with sanitized remote output.
- The SSH target failed before connection because `VPNKIT_VPS_SSH_HOST` is still the example placeholder (`your-vps-ssh-alias`), so no live target evidence or mutation was possible.
- Verification artifact updated: `verification/runtime-smoke.md`.
- Report updated: `reports/slice-owner-runtime-diagnosis-fix.md`.

## Current done-state

- AC1: not achieved; prior user-provided failure is recorded in routing context, but this owner could not reproduce/classify it without a usable private endpoint SSH target.
- AC2: not achieved; live runtime inspection blocked by placeholder `VPNKIT_VPS_SSH_HOST` in the local endpoint file.
- AC3: not achieved; targeted in-container checks blocked by placeholder `VPNKIT_VPS_SSH_HOST` in the local endpoint file.
- AC4: not applicable yet; no confirmed root cause or safe fix identified.
- AC5: not achieved; fresh host Docker client smoke blocked by placeholder endpoint/profile access.
- AC6: passed for current work; only public-safe task-package markdown was written.
