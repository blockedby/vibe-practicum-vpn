# vibe-practicum-vpn

Operational notes, plans, rollback instructions, and sanitized configs for the
`vibe-practicum` VPS VPN/routing setup.

Primary objective: keep clients simple via Tailscale exit-node, while gradually
moving routing/DNS/proxy fallback logic to the VPS safely.

Start with [`NOTES.md`](./NOTES.md).

Useful docs:

- [`docs/TAILSCALE_CLIENT_SETUP.md`](./docs/TAILSCALE_CLIENT_SETUP.md) — install/use Tailscale on Android, Windows, Kubuntu/Ubuntu.
- [`docs/PIXEL_ACCEPTANCE_CHECKLIST.md`](./docs/PIXEL_ACCEPTANCE_CHECKLIST.md) — current accepted canary checklist.
- [`docs/RU_DIRECT_RULESETS.md`](./docs/RU_DIRECT_RULESETS.md) — RU/direct rule-set notes.
- [`docs/ROLLBACK.md`](./docs/ROLLBACK.md) — rollback commands.
