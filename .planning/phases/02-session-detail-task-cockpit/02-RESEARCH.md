# Phase 2: Session Detail Task Cockpit - Research

**Researched:** 2026-05-25  
**Domain:** Vue 3 session-detail UI refactor preserving Supabase contracts  
**Confidence:** HIGH

## Summary

Phase 2 should be planned as a preservation-first UI extraction/refactor of `SessionDetailView.vue`, not a behavior rewrite. The current view owns data fetching, attendance mutation, absent state, cost RPC display, finalized snapshot payments, QR/cash modals, admin edit/cancel/finalize actions, realtime subscriptions, and polling.

Primary recommendation: keep data orchestration, Supabase handlers, route id, realtime channel lifecycle, polling lifecycle, modal state, selected snapshot/group state, and mutation handlers in `SessionDetailView.vue` for the first pass. Extract presentational section components only after source checks prove contracts are preserved.

## User Constraints

### Locked Decisions

- Mobile session detail uses four stacked section cards: Overview, Attendance, Costs, Payments.
- Mobile gets a sticky mini-tab/anchor row below header/top controls.
- Desktop/tablet may keep the existing table-oriented structure; do not remove desktop financial/status/action columns.
- Preserve all Supabase contracts, route access behavior, status locks, realtime/polling behavior, and payment entry points.
- Do not add schema changes, backend business logic rewrites, frontend shared-fee allocation, or new UI frameworks.
- Human visual UAT remains skipped/deferred per user instruction.

### the agent's Discretion

- Planner may extract local components/composables or keep the refactor in one file if behavior is preserved.
- Planner may choose exact mini-tab labels/icons/section IDs/scroll implementation if localized.
- Planner may choose whether mobile attendance cards default expanded/collapsed if all intervals and disabled states remain visible/usable.

### Deferred Ideas

- No backend fields, schema changes, RLS changes, or RPC changes.
- No offline attendance mode, audit history, realtime health indicator, or guest "I transferred" confirmation.
- No full desktop redesign.

## Phase Requirements

| ID | Research support |
|---|---|
| SESS-01 | Route `/session/:id` is public; mutation gates must use `authStore.isAdmin`. |
| SESS-02 | Overview must show title, date, fees, status, total collected where relevant, cancelled/read-only messaging, refresh, admin controls. |
| SESS-03 | Preserve `sessions.update`, `finalize_session`, cancel status update, and open-status locks. |
| SESS-04 | Preserve `add_member_to_session_full_presence` and `session_registrations.delete`. |
| SESS-05 | Preserve `interval_presence.upsert` and disabled states for non-admin/waiting/done/absent. |
| SESS-06 | Preserve `is_registered_not_attended` separately from removal. |
| SESS-07 | Display `calculate_session_costs` output; do not recalculate shared fees. |
| SESS-08 | Display `session_costs_snapshot` for waiting/done sessions. |
| SESS-09 | Preserve single QR and authenticated group QR via `create_group_payment`. |
| SESS-10 | Preserve admin-only manual cash via `add_manual_payment`. |
| SESS-11 | Preserve realtime cleanup and 10s polling/manual refresh behavior. |
| SESS-12 | Implement four mobile sections while preserving all operations. |

## Current Behavior Inventory

### Data fetching

- `fetchData()` reads `view_session_summary`, `session_intervals`, `members`, `session_registrations`, `interval_presence`, snapshots when waiting/done, and costs always.
- `fetchSnapshotData()` reads `session_costs_snapshot` joined to `members(display_name)`.
- `fetchCosts()` calls `calculate_session_costs`.

### Registrations and attendance

- Admin add members calls `add_member_to_session_full_presence` once per selected member.
- Admin remove registration deletes from `session_registrations` by registration id.
- Admin interval toggle upserts `interval_presence` with `onConflict: interval_id, member_id`.
- Registered-but-absent updates `session_registrations.is_registered_not_attended` and disables interval controls.

### Status locks

- Edit/cancel/finalize controls render only for admins and only where status permits.
- Attendance mutation UI is hidden for waiting/done, but current checks often exclude waiting/done and not cancelled. Planning should centralize a computed lock like `isSessionEditable = authStore.isAdmin && session.status === 'open'` to avoid inconsistent cancelled handling.
- Mutation controls and handlers must use `authStore.isAdmin`, not `authStore.isAuthenticated`.

### Payments

- Single QR uses `openPaymentQR(snapshot, name)` and `PaymentQRModal`.
- Group QR uses selected snapshot ids and `create_group_payment`; amount breakdown is derived from selected snapshots for display only.
- Manual cash opens `ManualPaymentModal` and calls `add_manual_payment` only after review confirmation.

### Realtime and polling

- Realtime subscribes to `interval_presence`, `session_registrations`, and `session_costs_snapshot`; channel is removed before replacement and on unmount.
- Polling runs every 10 seconds and is cleared on unmount.
- Risk: `fetchData()` returns when `isFetching` is true, so refresh events during an in-flight fetch may be dropped.

## Safe Implementation Seams

### Extract safely

- `SessionOverviewCard.vue`: status, date/time, fees, total collected, cancelled/read-only messages, refresh/admin actions.
- `SessionAttendanceSection.vue`: mobile cards plus desktop table, with handlers passed as props.
- `SessionCostsSection.vue`: live cost table/cards using `costs` and `surplus`.
- `SessionPaymentsSection.vue`: snapshot table/cards, single QR, group selection, cash action.
- Small composable or local helper group for formatting only: currency/date/time/status label.

### Keep in the view initially

- Supabase fetch orchestration.
- Realtime channel lifecycle.
- Polling lifecycle.
- Route id and loading state.
- Payment modal state.
- Selected snapshot/group state.
- All mutation handlers.

## Mobile Cockpit Layout Strategy

Use four stacked mobile cards with anchors: Overview, Attendance, Costs, Payments.

- Overview: compact summary and admin open-session controls only.
- Attendance: mobile member cards/accordions showing absent state, remove, absent toggle, interval toggles, and disabled reasons; desktop keeps matrix.
- Costs: open/cancelled editable-era sessions show live `calculate_session_costs` output; waiting/done can use snapshot/breakdown context.
- Payments: waiting/done show snapshot cards/table with QR/cash/group actions.
- Floating group payment bar must use a bottom offset above the Phase 1 bottom nav, such as `bottom: calc(92px + env(safe-area-inset-bottom))`, not current `bottom-6`.

## Supabase Contracts to Preserve

| Contract | Current use |
|---|---|
| `view_session_summary` | session summary fetch |
| `session_intervals` | interval list |
| `members` | active member dropdown |
| `session_registrations` | fetch, delete, absent update, realtime |
| `interval_presence` | fetch, upsert, realtime |
| `calculate_session_costs` | live costs |
| `session_costs_snapshot` | finalized payments and modal polling |
| `finalize_session` | finalize open session |
| `sessions.update` | edit fields and cancel status |
| `add_member_to_session_full_presence` | add registration with full presence |
| `create_group_payment` | group QR |
| `add_manual_payment` | admin cash |

## Common Pitfalls

- Dropping desktop columns while building mobile cards. Preserve financial/status/action data.
- Treating authenticated users as admins. Use `authStore.isAdmin` for all mutations.
- Recalculating fees in frontend. Display RPC/snapshot values only.
- Leaving group payment bar at `bottom-6`, overlapping mobile bottom nav.
- Losing payment modal semantics: QR success should refresh but not auto-close.
- Missing cancelled locks because current checks often exclude waiting/done but not cancelled.

## Validation Architecture

### Required checks

- Source inventory check: grep required contracts in `SessionDetailView.vue`, `PaymentQRModal.vue`, and `ManualPaymentModal.vue`.
- Type/build: run `pnpm type-check` and `pnpm build`.
- Route/access: verify `/session/:id` has no auth meta and mutation controls/handlers use `authStore.isAdmin`.
- Payment contracts: verify QR/cash/group flows still call `create_group_payment`, `add_manual_payment`, and `session_costs_snapshot`.
- Realtime/polling cleanup: verify `removeChannel`, `stopPolling`, and document click listener cleanup remain in `onUnmounted`.
- Mobile safe-area: source-check no session group bar uses `bottom-6`; require bottom offset above nav and page padding reserve.
- Locale parity: new `session.*` labels must exist in both `vi` and `en`.

### Deferred

- Human guest/admin visual UAT and 360/390/430px manual sweeps are skipped/deferred by user instruction.

## Environment Availability

| Dependency | Available | Version |
|---|---:|---|
| Node | yes | v22.22.0 |
| pnpm | yes | 8.15.9 |
| npm | yes | 11.12.0 |

## Sources

- `.planning/phases/02-session-detail-task-cockpit/02-CONTEXT.md`
- `.planning/REQUIREMENTS.md`
- `.planning/ROADMAP.md`
- `.planning/STATE.md`
- `.planning/phases/01-mobile-shell-debt-payment-foundation/01-UI-SPEC.md`
- `.planning/phases/01-mobile-shell-debt-payment-foundation/01-PHASE1-VALIDATION.md`
- `.planning/phases/01-mobile-shell-debt-payment-foundation/01-VERIFICATION.md`
- `src/views/SessionDetailView.vue`
- `src/components/PaymentQRModal.vue`
- `src/components/ManualPaymentModal.vue`
- `src/components/BottomNav.vue`
- `src/App.vue`
- `src/locales/messages.ts`
- `src/types/index.ts`
- `docs/api.yaml`
- `docs/summary.md`
- `mobile-screen-audit.html`
- `mobile-screen-audit-2.html`
- `mobile-prototypes/screens/session-detail.html`
- `brand-spec.md`

## Key Findings

1. Phase 2 is mostly a layout/componentization refactor, not data or backend work.
2. Keep Supabase handlers and realtime/polling in the parent view initially.
3. Extract cards/sections only as presentational components with handler props.
4. Fix known mobile overlap: session group payment bar currently uses `bottom-6`.
5. Centralize status/admin locks to avoid accidental cancelled/waiting/done mutation leakage.
