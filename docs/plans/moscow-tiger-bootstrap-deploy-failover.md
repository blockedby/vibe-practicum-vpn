# moscow-tiger bootstrap/deploy/failover plan

Planning status: recommended default plan; scripts are not implemented yet.

Source context: this plan builds on `docs/plans/hosting-research-moscow-vps.md` and the adjacent prior-exploration reports/checklists for a cheap Moscow/RU secondary VPN host. Provider choice and purchase remain an operator decision.

## Goals

- Provision and operate a secondary/passive VPS VPN node named `moscow-tiger`.
- Make the node easy to bootstrap, deploy, verify, fail over to, and roll back with a small script suite.
- Keep all tracked repository artifacts public-safe: no real endpoints, credentials, rendered configs, OpenVPN profiles, subscription URLs, logs, snapshots, or image exports.
- Preserve the existing local-first validation posture: prove container/runtime changes in the local Docker lab before mutating any live VPS.
- Treat DNS/domain failover automation as a follow-on task after the base `moscow-tiger` bootstrap/deploy path is implemented and verified; it is not in scope for the first bootstrap implementation.

## Constraints and safety boundaries

- Do not mutate remote hosts during planning or script design.
- Real endpoint values belong only in gitignored `config/private-endpoints.local.env`; tracked docs and examples use placeholders from `config/private-endpoints.example.env` style.
- The future implementation must stop before live mutation when required private values are absent.
- Recommended VPS baseline follows the hosting research checklist: Linux KVM/cloud VM, root access, at least 1 vCPU, 1 GB RAM, 10-20 GB disk, public IPv4, Docker-capable kernel, UDP/OpenVPN allowed or not prohibited by the provider AUP.
- Public-safe placeholder names should be used in docs, for example `<MOSCOW_TIGER_SSH_HOST>`, `<MOSCOW_TIGER_PUBLIC_ENDPOINT>`, and `<VPN_PUBLIC_DOMAIN>`.
- Existing runtime validation guidance in `docs/DOCKER_SETUP.md` remains the default pre-live gate for vpnkit/OpenVPN/sing-box/vibe-vpn changes.
- The VPN/failover domain is currently managed on Vercel, and Vercel CLI is available for a later DNS automation task. The initial bootstrap/deploy implementation must not mutate Vercel DNS or any other DNS provider.

## Approved firewall policy

Default inbound posture for `moscow-tiger`: deny by default and open only the approved minimal set.

Allowed inbound:

- `22/tcp` for SSH administration.
- `80/tcp` for HTTP bootstrap/challenge/health or redirect use when explicitly needed.
- `443/tcp` for HTTPS, TLS-based health, or future compatible front-door use.
- `1194/udp` for OpenVPN.
- ICMP for basic reachability/path diagnostics.

No other inbound ports should be opened unless a future decision updates this plan. Outbound should remain permissive enough for package install, Docker image pulls, DNS, NTP, upstream proxy/VPN dependencies, and health checks, subject to provider policy.

Future scripts should apply firewall rules idempotently and print the final ruleset before returning success. If a host already exposes unapproved inbound ports, preflight should warn and require an explicit operator override before proceeding.

## Recommended script suite and subcommands

Prefer one top-level dispatcher with subcommands plus small helpers where reuse is clearer:

- `scripts/moscow-tiger.sh preflight [--local|--remote] [--dry-run]`
  - Purpose: validate local repo state, required env names, SSH reachability, OS compatibility, root privileges, disk/RAM, Docker availability/installability, allowed provider assumptions, and firewall drift.
  - Inputs: `config/private-endpoints.local.env` values such as `MOSCOW_TIGER_SSH_HOST`, `MOSCOW_TIGER_PUBLIC_ENDPOINT`, optional `MOSCOW_TIGER_USER`, and public-safe defaults.
  - Safety/idempotency: read-only except optional package metadata checks; must support `--dry-run`; fails closed when private env is missing.
  - Order: first command before purchase validation, bootstrap, deploy, or failover.

- `scripts/moscow-tiger.sh bootstrap [--dry-run] [--yes]`
  - Purpose: prepare a fresh VPS with base packages, Docker/Compose support, root-only directories, firewall policy, and service prerequisites.
  - Inputs: SSH host/user, selected OS family, approved firewall ports, release root path.
  - Safety/idempotency: re-runnable; checks before installing; does not overwrite root-only secrets; applies firewall only after confirming SSH will remain allowed; `--dry-run` prints intended changes.
  - Order: after remote preflight and before first deploy.

- `scripts/moscow-tiger.sh render-local [--release <version>]`
  - Purpose: render configs and package deployable assets locally from tracked templates plus gitignored secrets.
  - Inputs: local endpoint env, existing `secrets/` tree, current git revision or explicit release ID.
  - Safety/idempotency: writes only to gitignored rendered/staging paths; refuses to run when outputs would enter tracked paths.
  - Order: before deploy; should reuse existing render patterns from `scripts/vpnkit-render-local-configs.sh` where possible.

- `scripts/moscow-tiger.sh deploy [--release <version>] [--dry-run] [--yes]`
  - Purpose: upload a versioned release bundle, install/update systemd/container assets, update the `current` symlink only after health gates pass, and leave previous releases available.
  - Inputs: SSH host, release bundle, root-only remote env/config paths, desired firewall mode.
  - Safety/idempotency: never deletes active release during deploy; stages to a new versioned directory; flips symlink atomically; can re-run the same release without duplicating service definitions.
  - Order: after bootstrap and local render.

- `scripts/moscow-tiger.sh verify [--local|--remote|--post-deploy]`
  - Purpose: run local Docker lab checks, remote service status checks, OpenVPN UDP listener checks, firewall checks, DNS/HTTP(S) health probes, and public-safety checks.
  - Inputs: endpoint env, expected release ID, optional health URLs/domains.
  - Safety/idempotency: read-only; returns non-zero on missing evidence; writes logs only to gitignored or operator-selected paths.
  - Order: before deploy, after deploy, before DNS failover, and after failover.

- `scripts/moscow-tiger.sh failover-plan [--domain <placeholder>]`
  - Purpose: print the operator steps for moving DNS/client traffic to `moscow-tiger`, including TTL checks and rollback target.
  - Inputs: DNS record names from local env, new endpoint, old endpoint, current TTL.
  - Safety/idempotency: no DNS API mutation by default; if a future `failover` mutating subcommand exists, it must require explicit `--yes` and current/expected record checks.
  - Order: after post-deploy verification passes.
  - Scope note: keep this as non-mutating guidance in the first bootstrap/deploy implementation. Vercel-backed DNS failover automation belongs to the later domain/DNS task.

- `scripts/moscow-tiger.sh rollback [--to <release>] [--dry-run] [--yes]`
  - Purpose: restore previous `current` symlink, restart services, and re-run health checks.
  - Inputs: release ID or default previous release, remote release root, service names.
  - Safety/idempotency: refuses rollback if target release is missing or fails static checks; does not delete failed release automatically.
  - Order: during failed deploy, failed post-deploy health, or DNS rollback.

- `scripts/moscow-tiger.sh status`
  - Purpose: summarize local env presence, remote release/symlink target, service status, firewall state, and last known health status.
  - Inputs: SSH host and release root.
  - Safety/idempotency: read-only.
  - Order: anytime.

## Release and symlink layout

Recommended remote layout:

```text
/opt/vpnkit-moscow-tiger/
  releases/
    2026-06-02T120000Z-<git-sha>/
      compose.yaml
      scripts/
      config/
      VERSION
    2026-06-02T130000Z-<git-sha>/
      ...
  current -> /opt/vpnkit-moscow-tiger/releases/2026-06-02T130000Z-<git-sha>
  previous -> /opt/vpnkit-moscow-tiger/releases/2026-06-02T120000Z-<git-sha>   # optional convenience link
  shared/
    env/              # root-only env files, not tracked
    secrets/          # root-only secrets/profile material, not tracked
    state/            # runtime state that survives release swaps
    logs/             # local remote logs, never copied into git
```

Systemd units, if used, should reference `current` rather than a versioned release path. Deploy should stage a new release, validate static files, run health checks where possible, update `previous`, atomically switch `current`, restart/reload services, then run post-deploy checks. Rollback switches `current` back to `previous` or an explicit known-good release.

## Secrets strategy

Local operator values:

- Keep real endpoints, SSH aliases, private domains, auth tokens, and provider details in `config/private-endpoints.local.env` only.
- Extend `config/private-endpoints.example.env` in a future script-implementation task with sanitized names if needed, for example `MOSCOW_TIGER_SSH_HOST=your-moscow-tiger-ssh-alias` and `MOSCOW_TIGER_PUBLIC_ENDPOINT=203.0.113.30`.
- Keep generated OpenVPN profiles, PKI material, rendered configs, subscription URLs, logs, snapshots, and image exports under gitignored `secrets/` or another explicitly gitignored operator path.

Remote values:

- Store remote env/config under root-owned paths such as `/opt/vpnkit-moscow-tiger/shared/env/` and `/opt/vpnkit-moscow-tiger/shared/secrets/`.
- Permission expectations: directories `0700`, secret/env files `0600`, owner `root:root` unless a dedicated service user is introduced later.
- Never place secrets inside versioned tracked release content unless the file is generated into the remote release during deploy and excluded from git locally.
- Future copy/sync commands should show destination paths but redact values from terminal output and logs.

## Idempotency requirements

- Every mutating command supports `--dry-run` and shows planned changes without applying them.
- Preflight detects missing env, unsupported OS, insufficient disk/RAM, unapproved open ports, missing Docker, and stale/dirty local generated assets before mutation.
- Bootstrap is safe to re-run on a partially prepared host and must not reset secrets or lock out SSH.
- Deploy stages to a new release and only flips `current` after validation; re-running the same release should converge rather than create conflicting services.
- Firewall application is declarative: desired policy is compared to actual policy before changes, and final policy is verified after changes.
- Rollback is explicit and does not delete failed releases until the operator decides retention cleanup.

## Verification gates, testing matrix, and stop conditions

Local/document gates before any live mutation:

- `git status --short` reviewed so no private files are staged.
- `git diff --check` passes for docs/scripts changes.
- Public-safety grep/check passes for obvious private keys, generated profiles, URLs with credentials, private endpoint names/values, and rendered config paths.
- `bash -n scripts/*.sh` for future shell changes.
- For runtime-affecting changes, run the Docker lab checks described in `docs/DOCKER_SETUP.md` before touching `moscow-tiger`.

Testing matrix for the first bootstrap/deploy implementation:

| Test area | Scope | Expected evidence | Mutation boundary |
| --- | --- | --- | --- |
| Local script tests | Shell syntax, argument parsing, missing-env handling, public-safety checks, redaction behavior, and helper function/unit-style coverage where practical. | `bash -n scripts/*.sh` plus scripted local test output showing pass/fail cases for `preflight`, `status`, `verify`, `bootstrap --dry-run`, `deploy --dry-run`, and `rollback --dry-run`. | Local only; no remote or DNS mutation. |
| Dry-run tests | Every mutating command prints planned changes and exits before applying them. | Captured dry-run output for bootstrap, deploy, firewall changes, release symlink changes, rollback, and failover-plan guidance. | Local/remote read-only depending on command; no package installs, service restarts, firewall writes, release swaps, or DNS writes. |
| Remote idempotency tests | Re-run safe commands against an already prepared or partially prepared host. | Repeated preflight/bootstrap/deploy/status/verify results show convergence, no duplicate service definitions, no secret overwrite, and stable release layout. | Requires operator-approved live host only after local gates pass; no DNS mutation. |
| Firewall connectivity tests | Confirm desired inbound policy and avoid SSH lockout. | Evidence that `22/tcp`, `80/tcp`, `443/tcp`, `1194/udp`, and ICMP are allowed as intended, unapproved inbound ports are denied or flagged, and SSH remains usable after firewall application. | Remote firewall mutation only in the bootstrap/deploy implementation after dry-run and confirmation; no broad emergency defaults. |
| Docker runtime tests | Validate container runtime and Compose/service wiring. | Docker/Compose installed/active, expected containers start, service status is healthy, and Docker lab checks from `docs/DOCKER_SETUP.md` pass before live deploy. | Local Docker lab first; remote runtime mutation only after approved bootstrap/deploy. |
| OpenVPN smoke | Confirm OpenVPN readiness without exposing generated profiles. | UDP listener on `1194`, service health, sanitized client smoke result, and no tracked logs/profiles. | Remote read-only smoke after deploy; generated client artifacts remain gitignored/operator-local. |
| RU-direct / 2ip smoke | Verify intended routing behavior with public-safe probe domains. | Sanitized output showing RU-direct/2ip-style connectivity result and expected route classification; no private endpoint values committed. | Remote/client smoke only after OpenVPN health; public-safe probe evidence only. |
| Rollback test | Prove previous release can be restored. | `rollback --dry-run`, explicit rollback execution in a controlled test, post-rollback `verify --post-deploy`, and confirmation failed release is retained for diagnosis. | Remote release symlink/service mutation only in controlled test after deploy path works; no DNS mutation. |

Later DNS/Vercel failover automation testing matrix:

| Test area | Scope | Expected evidence | Mutation boundary |
| --- | --- | --- | --- |
| Vercel DNS dry-run | Use Vercel CLI against operator-local domain/record values to read intended state and print planned changes. | Dry-run output shows current record, expected old value, proposed `moscow-tiger` value, TTL/record metadata where available, and rollback target with values redacted in tracked evidence. | Read-only Vercel CLI/DNS operations; no DNS mutation. |
| Vercel DNS apply | Mutating failover/rollback command for the Vercel-managed VPN/failover domain. | Apply evidence shows expected-old-value check, explicit `--yes`, successful DNS change, propagation monitoring, client/OpenVPN smoke after TTL window, and rollback dry-run/apply evidence. | Later task only, after base bootstrap/deploy is verified; requires operator approval and private env loaded from gitignored local config. |

Remote preflight gates before live mutation:

- Required local env exists and is sourced intentionally.
- SSH target resolves through operator-local alias/value, not a tracked endpoint.
- Host OS, architecture, disk, RAM, kernel, and virtualization are compatible.
- SSH access is stable; firewall bootstrap plan keeps `22/tcp` allowed.
- Provider/TOS assumptions have been manually checked for OpenVPN/UDP and Docker.
- Current inbound firewall state is inspected; unapproved open ports require operator decision.

Post-bootstrap/deploy gates:

- Docker/Compose or selected container runtime is installed and active.
- Expected services are enabled/running.
- Approved firewall policy is active: `22/tcp`, `80/tcp`, `443/tcp`, `1194/udp`, ICMP allowed; deny-by-default for other inbound traffic.
- OpenVPN listens on `1194/udp` and local/remote health checks pass.
- HTTP/HTTPS health endpoints, if configured, return expected public-safe status.
- No secrets are printed in logs or copied back into tracked paths.

Stop conditions:

- Missing `config/private-endpoints.local.env` values for any live command.
- Unknown or unsupported OS/runtime.
- Existing unapproved services/ports that cannot be explained.
- Docker/OpenVPN/sing-box health failure after deploy.
- DNS record mismatch before failover or rollback.
- Any evidence that generated profiles, rendered configs, secrets, logs, snapshots, or real endpoints would be committed.

## DNS failover steps

Default recommendation for the first bootstrap/deploy implementation: keep `moscow-tiger` passive until post-deploy verification passes, then manually update DNS/client routing as a controlled operation.

Current domain ownership assumption: the VPN/failover domain is managed on Vercel, and Vercel CLI is available. Provider-specific DNS automation should be planned as the next task after the base `moscow-tiger` bootstrap/deploy path is working, with dry-run/read-only checks first and mutating apply guarded by expected-current-record checks plus explicit operator confirmation.

1. Before an incident, keep relevant DNS TTL modest but not reckless, for example 300-600 seconds where the DNS provider and operational needs allow.
2. Record the current active target and rollback target in operator-local notes, not tracked docs.
3. Run `moscow-tiger.sh verify --post-deploy` and confirm the new node is healthy.
4. Check the live DNS record value and TTL; stop if it differs from the expected current active endpoint.
5. Update the record from the current active endpoint to `<MOSCOW_TIGER_PUBLIC_ENDPOINT>` using the DNS provider UI/API outside this planning task.
6. Monitor propagation with public-safe commands that do not reveal private domains in tracked logs. Do not commit resolver outputs containing private domains/endpoints.
7. Run client/OpenVPN health checks after expected TTL propagation.
8. Keep the old active node unchanged during the observation window so rollback remains possible.

DNS cautions:

- Low TTLs do not guarantee instant client migration; recursive resolvers and clients may cache longer.
- Do not lower TTL during an outage and expect immediate effect; set operational TTLs ahead of time.
- Avoid changing multiple variables at once: deploy first, verify, then DNS failover.
- If the project later uses provider DNS APIs, the mutating command must compare expected old value before writing the new value.

## Rollback

Release rollback:

1. Run `moscow-tiger.sh status` and identify `current`, `previous`, and the desired rollback release.
2. Run `moscow-tiger.sh rollback --to <release> --dry-run`.
3. If the target release passes static checks, run rollback with explicit confirmation.
4. Restart/reload services and run `verify --post-deploy`.
5. Preserve failed release artifacts for diagnosis unless they contain secrets in an unsafe location.

DNS rollback:

1. Confirm the old active node still passes health checks.
2. Check the DNS record still points to the `moscow-tiger` endpoint before changing it back.
3. Restore the prior endpoint through the DNS provider UI/API.
4. Monitor propagation and client health for at least one TTL window, preferably longer.
5. Record incident notes in a public-safe form; keep private endpoints/logs out of git.

Firewall rollback:

- If firewall changes break expected access, use provider console/rescue access when available rather than opening broad inbound access from scripts.
- Do not add emergency wide-open rules to tracked defaults. Any temporary provider-console change must be documented as operator-local incident handling.

## Open decisions

- Provider and final tariff for `moscow-tiger` after manual purchase/TOS verification.
- Whether `80/tcp` and `443/tcp` are only reserved/health ports or should host a concrete health/redirect service.
- Exact Vercel CLI command contract for later DNS failover automation, including dry-run output, expected-old-value checks, apply confirmation, propagation evidence, and rollback handling.
- Whether to add sanitized `MOSCOW_TIGER_*` placeholders to `config/private-endpoints.example.env` during script implementation.
- Whether to use Docker Compose directly, systemd wrapping Compose, or another container lifecycle convention on the remote host.
- Release retention policy, for example keep last 3-5 releases or keep releases for 14-30 days.
- Whether to create a dedicated service user or keep root-owned deployment under `/opt/vpnkit-moscow-tiger`.
- Exact remote health contract for OpenVPN/client verification without exposing private domains or generated profiles.

## Future implementation brief

Implement the script suite as docs-driven, public-safe automation. Start with `preflight`, `status`, and `verify` read-only commands, then add `bootstrap`, `render-local`, `deploy`, and `rollback`. Reuse existing script style and validation patterns from `scripts/vpnkit-render-local-configs.sh`, `scripts/vpnkit-copy-vps-secrets.sh`, `scripts/healthcheck.sh`, and `docs/DOCKER_SETUP.md`. Keep all live mutation behind explicit env loading, dry-run support, confirmation flags, and the stop conditions above.

Next task after the base bootstrap/deploy path works: add Vercel-backed DNS/domain failover automation for the currently Vercel-managed VPN/failover domain. That task should begin with Vercel CLI read-only/dry-run support, then guarded apply/rollback flows only after expected-current-record checks and explicit operator approval.
