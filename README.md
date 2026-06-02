# vibe-practicum-vpn

Public-safe operational tooling for the containerized `vpnkit` VPN/routing setup and the `vibe-vpn` Go helper.

## Documentation

- Current Docker setup: [`docs/DOCKER_SETUP.md`](./docs/DOCKER_SETUP.md)
- Consolidated historical notes: [`docs/RESEARCH_AND_ATTEMPTS.md`](./docs/RESEARCH_AND_ATTEMPTS.md)
- Private endpoint template: [`config/private-endpoints.example.env`](./config/private-endpoints.example.env)
- Vercel DNS failover runbook: [`docs/VERCEL_DNS_FAILOVER.md`](./docs/VERCEL_DNS_FAILOVER.md)

Real private endpoints belong in gitignored `config/private-endpoints.local.env`, never in tracked docs or configs.

## Local checks

```bash
go test ./...
go vet ./...
go build -o /tmp/vibe-vpn ./cmd/vibe-vpn
bash -n scripts/*.sh
```

See `docs/DOCKER_SETUP.md` for Docker lab verification and secret/rendered-config paths.
