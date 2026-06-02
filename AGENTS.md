# Repository agent notes

## Public-safety rules

- This repository is being prepared for public publication. Do not commit or reveal secrets, private keys, generated OpenVPN profiles, rendered configs, subscription URLs, auth files, logs, snapshots, image exports, or private endpoint values.
- Real private endpoints/SSH aliases/IPs/domains belong only in the gitignored file:
  - `config/private-endpoints.local.env`
- A sanitized tracked template is available at:
  - `config/private-endpoints.example.env`
- Before running commands that require real private endpoints, agents/operators should inspect and source the gitignored local file if it exists:
  ```bash
  test -r config/private-endpoints.local.env && set -a && . config/private-endpoints.local.env && set +a
  ```
- If `config/private-endpoints.local.env` is absent, use placeholders in docs and stop before live/runtime mutation.
- Public/test availability-check domains used by tests or health probes are intentionally allowed to remain tracked; do not replace them merely because they are public domains.

## Container images and runtimes

- Use the current Docker setup documentation in `docs/DOCKER_SETUP.md` for local validation.
- Steam Deck deployment remains Podman-only when intentionally operating on a Deck, but tracked public docs must not include real Deck LAN endpoints.
- Docker/Podman images are build artifacts, not source artifacts. Do not commit generated image exports or logs.

## Default testing workflow before live deploy

For `vpnkit` runtime, routing, OpenVPN, sing-box, DNS, IPv6, or `vibe-vpn` daemon changes, do not deploy directly to any live host first. Use the local Docker lab and client-test container as the default acceptance path, then mutate a live runtime only after local evidence passes and private endpoint values are loaded from the gitignored local endpoint file.
