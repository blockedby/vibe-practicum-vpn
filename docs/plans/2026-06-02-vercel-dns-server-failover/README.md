# Vercel DNS + server failover task package

- Status: plan/package complete; ready for next implementation owner; no live mutation performed.
- Slice: plan the next AAD implementation task only.
- Branch: `aad/vercel-dns-server-failover-plan`
- Worktree: `/home/kcnc/code/tools/vibe-practicum-vpn/.worktrees/vercel-dns-server-failover-plan`
- PR: not opened/pushed by this planning slice.

## Package index

- `plan.md` — acceptance-driven implementation plan and execution ledger for the next task.
- `verification/local.md` — fresh doc-only verification evidence for this planning slice.
- `reports/slice-owner.md` — final slice-owner report.
- `progress/` — reserved for future owner/implementer progress notes.
- `artifacts/` — reserved for future public-safe artifacts only; do not store logs containing private endpoints.

## Public-safety reminder

Real endpoint values, private domains, SSH aliases, tokens, generated profiles, rendered configs, subscription URLs, auth files, and logs belong only in gitignored operator-local paths such as `config/private-endpoints.local.env`, `secrets/`, or explicit gitignored runtime output. Use placeholders like `<VIBE_PRACTICUM_PUBLIC_ENDPOINT>`, `<MOSCOW_TIGER_PUBLIC_ENDPOINT>`, and `<VPN_PUBLIC_DOMAIN>` in tracked files.
