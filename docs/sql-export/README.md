# SQL Export Bundle

This folder contains SQL files generated from your current Supabase database (`public` schema) so your friend can recreate an equivalent system.

## Run order

1. `00_extensions.sql`
2. `01_enums.sql`
3. `02_tables.sql`
4. `03_constraints.sql`
5. `04_indexes.sql`
6. `05_views.sql`
7. `06_functions.sql`
8. `07_triggers.sql`
9. `08_rls.sql`

## Important

- This bundle recreates only `public` schema objects (no seed data).
- `auth.users` data is not included. Your friend needs to create users separately.
- Edge Functions are not included in SQL. Deploy them separately (`casso-webhook`, `sepay-webhook`).

## Webhook and SePay Setup

- Preferred provider: SePay.
- Casso should not be used for new setup. It is mainly suitable for OA/Biz account flow.
- For both webhook functions, keep `verify_jwt = false` because calls come from external provider.
- Required Edge Function secrets:
  - `SUPABASE_URL`
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `SEPAY_API_TOKEN`
  - `CASSO_TOKEN` (only if you still keep `casso-webhook` for legacy)
- SePay webhook URL format:
  - `https://<project-ref>.supabase.co/functions/v1/sepay-webhook`
- SePay header expected by current code:
  - `Authorization: Apikey <SEPAY_API_TOKEN>`
- Transfer content must include code format:
  - `CLXXXXXX` for single payment
  - `GRXXXXXX` for group payment
