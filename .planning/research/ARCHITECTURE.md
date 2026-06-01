# Architecture Research — UI Refactor Milestone

**Project:** Badminton Session Manager  
**Scope:** Frontend UI refactor architecture  
**Researched:** 2026-05-20

## Summary

Keep the current Vue 3 + TypeScript + Pinia + Supabase architecture, but introduce a clearer frontend composition layer. Route views should remain route owners, while data-heavy UI behavior moves into route-scoped composables and task-focused components.

The architectural change is decomposition, not backend redesign. Supabase tables, views, RPC names, parameters, and semantics must remain intact.

`SessionDetailView.vue` is the critical target. It should become a thin orchestrator around session-specific composables and panels for overview, attendance, costs, and payments.

## Current Architecture

| Layer | Current Files | Notes |
|-------|---------------|-------|
| App shell | `App.vue`, `AppHeader.vue` | Header exists; mobile navigation is weak |
| Routing | `src/router/index.ts` | Preserve route paths and guards |
| Global state | `stores/auth.ts`, `stores/lang.ts` | Keep auth/lang global; avoid domain global store migration |
| Data access | Direct Supabase calls in views/components | Keep contracts; move complex route calls into composables |
| Utilities | `utils/formatters.ts`, `utils/time.ts` | Centralize duplicated formatting |
| Components | Header, debt table, QR modal, manual payment modal | Add shared primitives and domain panels |
| Views | Route-level pages | `SessionDetailView.vue` is monolithic/highest risk |

## Supabase Contracts to Preserve

| Use | Contract |
|-----|----------|
| Home debt | `view_member_debt_summary` |
| Member debt history | `view_member_session_details` |
| Session summary | `view_session_summary` |
| Create session | RPC `create_session_with_intervals` |
| Session costs | RPC `calculate_session_costs` |
| Finalize session | RPC `finalize_session` |
| Register member | RPC `add_member_to_session_full_presence` |
| Group payment | RPC `create_group_payment` |
| Manual payment | RPC `add_manual_payment` |
| Attendance mutation | `interval_presence.upsert(..., { onConflict: 'interval_id, member_id' })` |
| Absent flag | `session_registrations.update({ is_registered_not_attended })` |
| Session edit/cancel | `sessions.update(...)` |
| Payment snapshots | `session_costs_snapshot` |

## Proposed UI Architecture

```text
Route View
  ├─ owns route params, top-level loading/error state, and auth role context
  ├─ composes route-scoped composables
  └─ renders task-focused panels/components

Composables
  ├─ own Supabase calls and reactive state
  ├─ preserve existing RPC/table/view contracts
  └─ expose typed state/actions

Components
  ├─ presentational or interaction-focused
  ├─ receive typed props
  └─ emit semantic events
```

## Component Extraction Map

### Shell/shared UI

- `AppShell.vue` — header, router outlet, bottom nav, safe-area padding.
- `BottomNav.vue` — mobile role-aware navigation.
- `PageHeader.vue` — reusable compact page title/back/action header.
- `ui/BottomSheet.vue` — mobile sheet + desktop modal foundation.
- `ui/FloatingActionBar.vue` — safe-area selected-items CTA.
- `ui/StatusChip.vue` — status labels.
- `ui/CurrencyAmount.vue` — VND display.
- `ui/LoadingState.vue`, `ui/EmptyState.vue`, `ui/ErrorState.vue`.

### Session domain

- `session/SessionHeaderCard.vue`
- `session/SessionEditSheet.vue`
- `session/SessionTabs.vue`
- `session/AttendancePanel.vue`
- `session/AttendanceMemberCard.vue`
- `session/AttendanceMatrix.vue`
- `session/MemberRegistrationSheet.vue`
- `session/CostSummaryPanel.vue`
- `session/PaymentSnapshotPanel.vue`

### Payment/debt domain

- evolve `PaymentQRModal.vue` toward a responsive QR sheet.
- evolve `ManualPaymentModal.vue` toward a responsive manual payment sheet.
- `debt/DebtSummaryCard.vue`
- `debt/DebtMemberList.vue` or evolution of `HomeDebtTable.vue`.

## Recommended Composables

| Composable | Responsibility |
|------------|----------------|
| `useCurrency.ts` | VND formatter by language |
| `useSessionDetail.ts` | Load session, intervals, registrations, members, presence, costs, snapshots |
| `useSessionAttendance.ts` | Presence matrix, toggle presence, toggle absent |
| `useSessionRegistration.ts` | Available members, register, remove registration |
| `useSessionPayments.ts` | Snapshot selection, QR/cash/group payment state |
| `useRealtimeRefresh.ts` | Realtime subscription lifecycle and polling fallback |
| `usePaymentPolling.ts` | Payment status polling currently in QR modal |
| `useDebtPayments.ts` | Shared group payment creation for home/member detail |

## Session Detail Target Shape

```text
views/SessionDetailView.vue
  ├─ useSessionDetail(sessionId)
  ├─ useSessionAttendance(...)
  ├─ useSessionRegistration(...)
  ├─ useSessionPayments(...)
  ├─ useRealtimeRefresh(...)
  ├─ SessionHeaderCard
  ├─ SessionTabs
  │   ├─ Overview
  │   ├─ AttendancePanel
  │   ├─ CostSummaryPanel
  │   └─ PaymentSnapshotPanel
  ├─ PaymentQRSheet
  └─ ManualPaymentSheet
```

Keep `/session/:id` as one route; do not add new tab routes in this milestone.

## Data Flow Preservation

Session detail read flow:

```text
/session/:id
  → view_session_summary
  → session_intervals
  → members
  → session_registrations + member join
  → interval_presence
  → calculate_session_costs
  → if waiting_for_payment/done: session_costs_snapshot
```

Mutations:

```text
toggle presence → interval_presence.upsert
toggle absent → session_registrations.update
register members → add_member_to_session_full_presence
remove registration → session_registrations.delete
finalize → finalize_session
cancel/edit → sessions.update
group payment → create_group_payment
manual payment → add_manual_payment
```

## Realtime/Polling Guidance

Route all refreshes through one debounced refresh function. Preserve existing behavior first; if improving:

- subscribe to `interval_presence`
- subscribe to `session_registrations`
- subscribe to `session_costs_snapshot` updates
- use polling only as fallback when realtime is unavailable
- keep manual refresh visible

## Suggested 3-Phase Build Order

### Phase 1 — Shell, shared UI primitives, debt/payment foundation

Add app shell, bottom nav, shared primitives, currency helper, debt layout improvements, group-pay bar fixes, and translation keys. Keep routes unchanged.

### Phase 2 — Session detail decomposition and task cockpit

Extract session composables and panels, then introduce mobile tabs/task sections. Verify every current session action before replacing layout.

### Phase 3 — Payment sheets, admin/supporting screens, cleanup

Refactor payment/manual modals into sheets, polish sessions/create/members/member-detail/login, replace duplicated formatting, remove touched `any`/console logs, and validate i18n.

## Risks

- Losing session detail behavior during decomposition.
- Accidentally changing Supabase business semantics.
- Realtime/polling races or duplicate timers.
- QR/modal refactor breaking payment completion events.
- Bottom nav exposing admin-only links to guests.
- Mobile attendance cards losing desktop matrix efficiency.
- Missing i18n keys or weaker type safety.
