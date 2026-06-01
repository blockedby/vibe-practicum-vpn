## Acceptance plan for apply-adapter slice

### Root acceptance criteria to audit
1. Container-safe switching works after apply/failover.
2. VPS/systemd behavior remains preserved as default.
3. No secrets or VPS mutation are introduced.
4. REDIRECT/DNS path remains intact.
5. E2E integration exists and proves the switched path.
6. Logs and cleanup behavior are preserved.
7. Relevant commit/push evidence exists.

### Evidence to check
- `verification/apply-adapter.md`
- `reports/apply-adapter-slice-owner.md`
- `reports/slice-owner-implementation.md`
- `verification/real-e2e-2026-06-01.md`
- task-package logs or artifacts referenced by those reports

### Decision rule
Accept only if the evidence shows a fresh passing post-switch OpenVPN/DNS/HTTPS/literal-IP path for the container-safe adapter, with systemd default unchanged and no secret/VPS mutation.
If post-switch evidence fails or is missing, mark the root request not accepted or accepted only with explicit limitations, depending on scope closure.
