# Phase 2 Validation — Session Detail Task Cockpit

**Plan:** `02-05`  
**Date:** 2026-05-25  
**Scope:** Automated command validation, source contract validation, route/access checks, realtime/polling/payment refresh evidence, mobile fixed-layer evidence, locale parity, and payment sheet preservation.

> Human UAT skipped/deferred by user instruction. Evidence below is automated/source/build evidence only; no manual visual checkpoint was requested.

## Automated Commands

| Command | Result | Evidence |
|---|---:|---|
| `pnpm type-check` | PASS | `vue-tsc --build` exited `0`. |
| `pnpm build` | PASS | Vite production build exited `0`; build transformed 2608 modules and emitted `dist/` assets. |
| Route/access source assertions | PASS | `/session/:id` exists in `src/router/index.ts` with no `requiresAuth` or `requiresAdmin` meta. |
| Supabase contract source assertions | PASS | Required contracts remain source-verifiable in `SessionDetailView.vue` and `ManualPaymentModal.vue`. |
| Mutation guard assertions | PASS | Session mutations use `isSessionEditable` / `authStore.isAdmin`; no authenticated-only mutation guard pattern remains. |
| Locale parity source assertion | PASS | Phase 2 session cockpit keys are present in both `vi` and `en`. |
| Fixed-layer/modal source assertions | PASS | No `bottom-6`; safe-area group payment bar and `88dvh` sheets with sticky footers/dialog semantics remain present. |

## Phase 2 Requirements

| Requirement | Result | Evidence |
|---|---:|---|
| SESS-01 | PASS | `/session/:id` remains public read-only; mutation controls and handlers are gated through `isSessionEditable`/`authStore.isAdmin`. |
| SESS-02 | PASS | Overview shows title, date/time, court fee, shuttle fee, status, total collected for finalized states, cancelled/read-only messaging, refresh, and admin controls. |
| SESS-03 | PASS | Edit and cancel preserve explicit `.from('sessions').update({ ... })`; finalization preserves `finalize_session`. |
| SESS-04 | PASS | Add member preserves `add_member_to_session_full_presence`; removal preserves `session_registrations.delete()`. |
| SESS-05 | PASS | Attendance toggles preserve `interval_presence.upsert` with admin/open locks and disabled states. |
| SESS-06 | PASS | Registered-but-absent remains `session_registrations.update({ is_registered_not_attended })`; toggle presence returns before upsert for absent members. |
| SESS-07 | PASS | Live cost cards/tables display `calculate_session_costs` output; no frontend fee allocation was added. |
| SESS-08 | PASS | Finalized payments display `session_costs_snapshot` data and snapshot-derived payment status/paid/must-pay fields. |
| SESS-09 | PASS | Single QR remains public for unpaid snapshots; authenticated group selection uses `create_group_payment`. |
| SESS-10 | PASS | Manual cash payment is admin-only in `openCashPayment`; cash modal preserves `add_manual_payment`. |
| SESS-11 | PASS | `pendingRefresh`, `startPolling`, `stopPolling`, realtime `removeChannel`, and `@payment-complete="fetchData"` preserve refresh behavior without duplicate timers or stale selected state after QR close. |
| SESS-12 | PASS | Mobile cockpit tabs/sections for overview, attendance, costs, and payments are present while desktop tables and all operations remain available. |

## Locked Decisions D-01 through D-21

| Decision | Result | Evidence |
|---|---:|---|
| D-01 | PASS | Mobile renders Overview, Attendance, Costs, and Payments sections. |
| D-02 | PASS | Sticky mobile mini-tab row controls the four anchored sections. |
| D-03 | PASS | Default active section is status-aware via `getDefaultActiveSection`. |
| D-04 | PASS | Overview is compact and keeps refresh/admin controls without duplicating deep rows. |
| D-05 | PASS | Desktop attendance, cost, and payment tables remain. |
| D-06 | PASS | Mobile attendance member cards exist; desktop matrix remains. |
| D-07 | PASS | Add/remove/toggle/absent operations preserve existing Supabase contracts. |
| D-08 | PASS | Guest/non-admin/finalized/cancelled/absent disabled states and handler guards are explicit. |
| D-09 | PASS | Registered-but-absent is visible and separate from removal. |
| D-10 | PASS | Costs display backend-owned `calculate_session_costs` fields. |
| D-11 | PASS | Payments display finalized `session_costs_snapshot` fields. |
| D-12 | PASS | Single QR, group QR, and admin manual cash entry points remain. |
| D-13 | PASS | Phase 1 QR/manual sheet semantics remain reused. |
| D-14 | PASS | Group payment bar uses safe-area bottom offset, not `bottom-6`. |
| D-15 | PASS | Realtime subscriptions cover `interval_presence`, `session_registrations`, and `session_costs_snapshot`, with cleanup/replacement. |
| D-16 | PASS | Polling/manual/payment-complete refresh paths remain; in-flight refreshes are queued. |
| D-17 | PASS | Open, waiting-for-payment, done, and cancelled states retain distinct UI behavior. |
| D-18 | PASS | New session cockpit labels are in both Vietnamese and English. |
| D-19 | PASS | Changed controls use native buttons/inputs, visible labels/ARIA, focus rings, and 44px targets where applicable. |
| D-20 | PASS | Existing Tailwind/Vue visual language is preserved; no new UI framework was added. |
| D-21 | PASS | Open Design remains directional only; Vue/Supabase behavior remains the source of truth. |

## Route and Access Evidence

| Surface | Expected | Result | Evidence |
|---|---|---:|---|
| `/session/:id` route | Public read-only route, no auth/admin meta | PASS | `src/router/index.ts` line 28; source assertion found no `requiresAuth`/`requiresAdmin` in the route block. |
| Session mutation controls | Admin/open only | PASS | Controls render behind `isSessionEditable`; edit mode additionally checks `authStore.isAdmin`. |
| Session mutation handlers | Admin/open only | PASS | `saveSession`, `cancelSession`, `finalizeSession`, `registerMembers`, `removeRegistration`, `togglePresence`, and `toggleAbsent` return unless `isSessionEditable`. |
| Manual cash | Admin only | PASS | `openCashPayment` returns before selecting state or opening the modal when `!authStore.isAdmin`. |

## Supabase Contract Preservation

| Contract | Result | Evidence |
|---|---:|---|
| `view_session_summary` | PASS | `SessionDetailView.vue` fetches `.from('view_session_summary')`. |
| `session_intervals` | PASS | `SessionDetailView.vue` fetches `.from('session_intervals')`. |
| `members` | PASS | `SessionDetailView.vue` fetches `.from('members')` for add-member choices and joins members for snapshots/registrations. |
| `session_registrations` | PASS | Fetch/delete/absent update and realtime subscription remain. |
| `interval_presence` | PASS | Fetch/upsert and realtime subscription remain. |
| `calculate_session_costs` | PASS | `fetchCosts()` calls `supabase.rpc('calculate_session_costs', { p_session_id: sessionId })`. |
| `session_costs_snapshot` | PASS | Snapshot fetch and realtime `UPDATE` subscription remain; QR modal also polls this table. |
| `finalize_session` | PASS | `finalizeSession()` calls `supabase.rpc('finalize_session', { p_session_id: sessionId })`. |
| `sessions.update({ ... })` | PASS | Source assertion found two explicit `.from('sessions').update({ ... })` flows: cancel and edit. |
| `add_member_to_session_full_presence` | PASS | `registerMembers()` calls the RPC for each selected member. |
| `create_group_payment` | PASS | `handleCreateGroupPayment()` calls the RPC with `p_snapshot_ids`. |
| `add_manual_payment` | PASS | `ManualPaymentModal.vue` calls the RPC after review confirmation. |

## Realtime, Polling, and Refresh Evidence

| Behavior | Result | Evidence |
|---|---:|---|
| No dropped in-flight refresh | PASS | `pendingRefresh` queues one full/cost refresh while `isFetching` is true and drains it in `finally`. |
| No duplicate polling timers | PASS | `startPolling()` returns when `pollTimer` exists. |
| Polling cleanup | PASS | `stopPolling()` clears and nulls `pollTimer`; `onUnmounted()` calls it. |
| Realtime replacement/cleanup | PASS | `initRealtime()` removes an existing channel before subscribing; `onUnmounted()` removes the channel. |
| Realtime coverage | PASS | Realtime watches `interval_presence`, `session_registrations`, and `session_costs_snapshot`. |
| Payment complete refresh | PASS | `PaymentQRModal` emits `payment-complete`; `SessionDetailView.vue` handles it with `@payment-complete="fetchData"` and does not auto-close the QR sheet. |
| QR close state cleanup | PASS | `handleCloseQR()` clears `groupPaymentData` and `selectedSnapshotIds`. |
| Manual cash refresh | PASS | `ManualPaymentModal @success="fetchSnapshotData"` refreshes snapshot payment state after `add_manual_payment`. |

## Mobile / Fixed-Layer Evidence

| Surface | Result | Evidence |
|---|---:|---|
| Mobile cockpit tabs | PASS | Sticky mini-tabs link to four sections. |
| Attendance cards | PASS | Mobile `article` cards show member, present interval count, absent state, interval checkboxes, remove, and absent toggle. |
| Costs cards | PASS | Mobile live costs cards show total, intervals, court fee, shuttle fee, and surplus. |
| Payment cards | PASS | Mobile snapshot cards show must-pay, paid amount, intervals, fees, status, QR/cash actions. |
| Desktop tables | PASS | Desktop attendance matrix, cost table, and payment table remain. |
| Group payment bar | PASS | Uses `bottom-[calc(92px+env(safe-area-inset-bottom))]` and page padding `pb-[calc(148px+env(safe-area-inset-bottom))]`; `bottom-6` is absent. |
| Payment sheets | PASS | QR and manual cash sheets use `max-h-[88dvh]`, `role="dialog"`, `aria-modal="true"`, and `sticky bottom-0` footers. |

## Locale Parity Evidence

| Key set | Result | Evidence |
|---|---:|---|
| Phase 2 session cockpit keys | PASS | `overview`, `attendance`, `costs`, `payments`, `cockpitNavLabel`, `refreshSession`, `readOnlyHint`, `adminOnlyHint`, `lockedSessionHint`, `cancelledSessionHint`, `addMembersTitle`, `noRegisteredMembers`, `markAbsent`, `presentIntervals`, `paymentSnapshotsEmpty`, `liveCostsEmpty`, `sessionLoading`, `sessionLoadError`, and `groupPaymentBar` appear in both locale blocks. |

## User-Skipped Human UAT

| Item | Status | Note |
|---|---|---|
| Manual guest/admin visual UAT | SKIPPED/DEFERRED BY USER INSTRUCTION | User explicitly requested autonomous execution and no human UAT. |
| Manual 360/390/430 overlap sweep | SKIPPED/DEFERRED BY USER INSTRUCTION | Replaced with source checks for safe-area offsets, bottom padding, sheet caps, and sticky footers. |
| Manual payment refresh observation | SKIPPED/DEFERRED BY USER INSTRUCTION | Replaced with source checks for realtime, polling, payment-complete, queued refresh, and close-state cleanup. |

## Remaining Observations

- No Supabase schema changes, migrations, RLS changes, or duplicate frontend database business logic were added.
- Existing untracked Open Design artifacts and `.planning/config.json` runtime state were intentionally not included in this validation artifact or commits.
