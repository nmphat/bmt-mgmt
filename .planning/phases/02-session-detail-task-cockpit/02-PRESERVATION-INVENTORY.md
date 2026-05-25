# Phase 2 Session Detail Preservation Inventory

**Plan:** `02-01`  
**Route:** `/session/:id`  
**Human UAT:** skipped/deferred by explicit user instruction; validation for this plan is source-based plus type/locale checks.

## Route and Access Expectations

| Surface | Guest / non-admin expectation | Admin expectation | Preservation rule |
|---|---|---|---|
| `/session/:id` route | Public read-only access remains available without login. | Same route plus allowed session mutations when the session is open. | Do not add route auth meta or guest-facing login requirements. |
| Mutation controls | Hidden or disabled for guests, non-admin users, waiting-for-payment, done, and cancelled sessions. | Visible only when `authStore.isAdmin && session.status === 'open'`. | UI visibility and handlers both use centralized `isSessionEditable`. |
| Payment QR | Single QR entry points stay available from unpaid finalized snapshots. | Same plus authenticated/admin group QR and admin cash where currently allowed. | Do not change QR modal payloads, group RPC input, or manual cash RPC semantics. |

## Operation Inventory

| Operation | Current Supabase / source contract | Allowed state / role | Preservation notes |
|---|---|---|---|
| Load session summary | `view_session_summary` | Public read-only | Fetch by route `sessionId`; keep open/waiting/done/cancelled status distinctions. |
| Load intervals | `session_intervals` | Public read-only | Ordered by `idx`; attendance matrix/card refactors must retain every interval. |
| Load active members | `members` | Public read-only data for admin add control | Used to populate add-member choices; active-member filtering remains frontend presentation around existing table data. |
| Load registrations | `session_registrations` joined to `members` | Public read-only | Preserve `is_registered_not_attended` as a distinct absent state. |
| Load interval presence | `interval_presence` | Public read-only | Preserve matrix keyed by `member_id` and `interval_id`. |
| Edit session | `sessions.update` for title/status/fees/updated_at | Admin only, open sessions only | No schema changes; cancelled/waiting/done sessions are read-only. |
| Cancel session | `sessions.update({ status: 'cancelled' })` | Admin only, open sessions only | Cancelled sessions become read-only while preserving data. |
| Finalize session | `finalize_session` RPC with `p_session_id` | Admin only, open sessions only | Do not replace backend finalization or frontend-calculate fee allocation. |
| Add members | `add_member_to_session_full_presence` RPC with `p_session_id`, `p_member_id` | Admin only, open sessions only | Preserve full-presence behavior for newly registered members. |
| Remove registration | `session_registrations.delete().eq('id', regId)` | Admin only, open sessions only | Removal remains separate from absent marking. |
| Toggle interval attendance | `interval_presence.upsert` with `interval_id`, `member_id`, `is_present`, `onConflict: interval_id, member_id` | Admin only, open sessions only, not registered-but-absent | Handler returns before upsert for absent registrations. |
| Toggle absent state | `session_registrations.update({ is_registered_not_attended })` | Admin only, open sessions only | Preserves absent state separately from registration removal. |
| Live costs | `calculate_session_costs` RPC with `p_session_id` | Public read-only display | Frontend displays returned member totals, interval counts, fees, and surplus; no frontend fee allocation. |
| Finalized snapshots | `session_costs_snapshot` joined to `members(display_name)` | Public read-only display for waiting/done | Preserve member name, final amount, paid amount, payment status, and payment code payloads. |
| Single QR payment | `PaymentQRModal` fed by unpaid `session_costs_snapshot` row | Public snapshot entry point where rendered | Keep `openPaymentQR` public for unpaid snapshots and preserve modal close/payment-complete refresh behavior. |
| Group QR payment | `create_group_payment` RPC with `p_snapshot_ids` | Existing authenticated-user group selection behavior | Preserve selected snapshot ids and backend-owned amount/code response; no frontend fee allocation. |
| Manual cash payment | `ManualPaymentModal` and `add_manual_payment` RPC | Admin only | `openCashPayment` must guard non-admin users before selecting member/modal state. |
| Manual refresh | `fetchData()` / `fetchData(true)` | Public read-only | Keep refresh action available without requiring login. |
| Realtime updates | Supabase realtime on `interval_presence`, `session_registrations`, `session_costs_snapshot` | Mounted session detail view | Preserve channel replacement and `supabase.removeChannel` cleanup. |
| Polling fallback | 10-second `setInterval` calling `fetchData(true)` | Mounted session detail view | Preserve `stopPolling` cleanup on unmount; avoid duplicate timers. |

## Required Supabase Contracts

These contract names and parameter shapes must remain source-verifiable through Phase 2:

- `view_session_summary`
- `session_intervals`
- `members`
- `session_registrations`
- `interval_presence`
- `calculate_session_costs`
- `session_costs_snapshot`
- `finalize_session`
- `sessions.update`
- `add_member_to_session_full_presence`
- `create_group_payment`
- `add_manual_payment`

## Non-Negotiable Boundaries

- No Supabase schema, RLS, table, view, or RPC changes in Phase 2 UI refactor work.
- No duplicate database business logic or shared-fee allocation in the frontend.
- `/session/:id` remains public read-only for guests and non-admin users.
- Admin mutation controls and handlers remain locked to `authStore.isAdmin && session.status === 'open'`.
- QR payment entry points, manual cash review/confirmation, payment polling, realtime updates, and manual refresh remain available in their existing allowed states.
