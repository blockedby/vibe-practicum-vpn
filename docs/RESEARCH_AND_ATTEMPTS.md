# Research and attempts archive

Older tracked runbooks, canary notes, task plans, live checkpoints, snapshots, and postmortems were consolidated for public publication because they contained operator-local hostnames, paths, IP addresses, logs, and historical deployment details.

High-level retained learnings:

- Prefer the current Docker `vpnkit` workflow in `docs/DOCKER_SETUP.md` for local validation before any live runtime change.
- Keep generated OpenVPN profiles, private keys, subscriptions, rendered configs, and runtime logs in gitignored local paths only.
- Use placeholder documentation for private endpoints; operators should keep real endpoint values in `config/private-endpoints.local.env`.
- Compatibility bypass checks are still supported, but real operator bypass endpoints are kept in `config/private-endpoints.local.env`; public availability-check domains remain tracked where tests need them.
- Historical canary, IKEv2, TPROXY, direct-routing, device-specific, and deployment-attempt notes are no longer authoritative public docs. Recreate any needed private runbook from local operator notes, not from committed secrets or logs.
