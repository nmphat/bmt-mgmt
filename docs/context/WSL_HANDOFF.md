# WSL Handoff

## Current Status

- Date: 2026-03-08
- Main repo: `bmt-mgmt`
- Target Supabase project for testing: `bmt-mgmt-002`
- Supabase project ref/id: `cnedidrhfmmyqdotzleq`

## Supabase Provisioning Done

- Database schema applied from SQL export in order `00 -> 08`.
- Migration names on target project:
  - `clone_00_extensions`
  - `clone_01_enums`
  - `clone_02_tables`
  - `clone_03_constraints`
  - `clone_04_indexes`
  - `clone_05_views`
  - `clone_06_functions`
  - `clone_07_triggers`
  - `clone_08_rls`
- `public.session_payments.note` exists (migration was added before export sync).

## Edge Functions Deployment Done

- Deployed and active on `cnedidrhfmmyqdotzleq`:
  - `sepay-webhook` (`verify_jwt=false`)
  - `casso-webhook` (`verify_jwt=false`)

## Runtime Notes

- SePay auth format expected by code:
  - Header: `Authorization: Apikey <SEPAY_API_TOKEN>`
- Verified behavior:
  - Wrong/missing token returns `401 Unauthorized`.
  - Correct token returns `{ "success": true, "logs": [...] }`.
  - Empty logs for test payload is expected if payment code does not exist in DB.

## Required Secrets on Supabase (per project)

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SEPAY_API_TOKEN`
- `CASSO_TOKEN` (only if keeping Casso webhook)

## App Env Needed

- `VITE_SUPABASE_URL=https://cnedidrhfmmyqdotzleq.supabase.co`
- `VITE_SUPABASE_ANON_KEY=<project anon or publishable key>`

## WSL Move Guidance

- Use Linux filesystem for performance (example: `~/work/bmt-mgmt`), not `/mnt/c/...`.
- Do not reuse Windows `node_modules`.
- After cloning in WSL:

```bash
pnpm install
pnpm dev
```

## Quick E2E Payment Test (SePay)

1. Create a session via app.
2. Finalize session to generate `CLxxxxxx` in `session_costs_snapshot.payment_code`.
3. Call webhook with correct token and content containing that `CLxxxxxx` code.
4. Verify:
   - `session_payments` has a new row.
   - `session_costs_snapshot.paid_amount` and `status` are updated.

## Context Files to Keep

- `docs/sql-export/*`
- `docs/context/*`
- `.env.example` (template only, no secrets)
