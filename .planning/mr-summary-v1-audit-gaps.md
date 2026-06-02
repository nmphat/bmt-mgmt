# MR: Close v1.0 milestone audit backend-contract gaps

Base: `master`
Head: `fix/v1-audit-gaps`
Compare: https://github.com/nmphat/bmt-mgmt/compare/master...fix/v1-audit-gaps?expand=1
Manual PR URL: https://github.com/nmphat/bmt-mgmt/compare/master...fix/v1-audit-gaps?quick_pull=1

## Summary

This follow-up MR closes the v1.0 milestone audit gaps found after PR #2 was merged. It aligns the UI refactor with the current Supabase/Postgres backend contract and updates the milestone audit artifact to `status: passed`.

## Key changes

- Replaces the retired `create_session_with_intervals` RPC call with `create_session_with_bookings` in the create-session flow.
- Removes the retired `members.is_permanent` field from frontend member CRUD and TypeScript types.
- Updates session edit writes to use current `sessions` table fields: `price_per_hour`, `court_fee_addon`, and `shuttle_fee_total`.
- Preserves `court_fee_total` only as a read-model/view value, not a writable `sessions` column.
- Archives the v1.0 milestone audit report with all three blockers closed:
  - `ADMIN-02` create-session RPC mismatch.
  - `ADMIN-03` member CRUD removed-column mismatch.
  - `SESS-03` session edit non-table field mismatch.
- Updates current planning docs to reference the current backend contract.

## Validation

- `pnpm type-check`
- `pnpm build`
- `pnpm i18n:audit` with `MISSING_COUNT=0`
- Scoped GSD integration recheck: `verdict: passed`
- `.planning/v1.0-MILESTONE-AUDIT.md`: `status: passed`, requirements `29/29`, phases `3/3`, integration `11/11`, flows `11/11`

## Notes

- PR #2 (`feat/refactor-ui` into `master`) was already merged before the audit-gap closure branch was created, so this branch should be merged as a follow-up before or alongside final milestone archival.
- Automatic PR creation was unavailable in the CLI environment because `gh` was not installed, GitHub token environment variables were not set, and the browser harness GitHub session was signed out.
