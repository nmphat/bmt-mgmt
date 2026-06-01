# Research Summary — Badminton Session Manager v1.0 UI Refactor

**Project:** Badminton Session Manager  
**Milestone:** v1.0 UI refactor from Open Design  
**Scope:** Coarse roadmap, exactly 3 phases, preserve all existing Vue/Supabase behavior  
**Researched:** 2026-05-20

## Executive Summary

This milestone is a UI refactor, not a product expansion or backend rewrite. The Open Design output should guide mobile interaction patterns, visual hierarchy, and ergonomics, but the live app remains the source of truth for routes, permissions, Supabase contracts, payment semantics, and session behavior.

Keep the current Vue 3, TypeScript, Tailwind v4, Pinia, Vue Router, and Supabase stack intact. Refactor by introducing shared UI primitives, a mobile app shell, route-scoped composables, and task-focused panels.

The highest-risk area is `SessionDetailView.vue`, which must be decomposed carefully without losing attendance, registration, absent flags, realtime/polling, finalization, cancellation, cost snapshots, QR payments, group payments, or manual cash payment.

## Stack Decisions

### Keep

- Vue 3, TypeScript strict, Vite, TailwindCSS v4
- Pinia for auth/language only
- Vue Router paths and guards
- Supabase JS tables/views/RPCs/realtime
- lucide-vue-next, vue-toastification, date-fns
- current `src/locales/messages.ts` i18n pattern

### Add/refactor locally

- app-owned UI primitives under `src/components/ui/`
- mobile shell and bottom navigation
- status chips, cards, bottom sheets, floating action bars, loading/empty/error states
- route-scoped composables around existing Supabase contracts
- optional small dev-only component tests if phase budget allows

### Avoid

- third-party UI framework
- TanStack Query or new data layer
- form/validation framework migration
- frontend fee allocation or payment business logic
- backend/schema changes for prototype-only ideas

## Feature Table Stakes

Must preserve:

- guest access to `/`, `/member/:id`, `/session/:id`, and `/members` as currently allowed
- guest debt home backed by `view_member_debt_summary`
- member debt history backed by `view_member_session_details`
- single and group QR payments via existing payment contracts
- admin sessions, create session, and session detail flows
- interval-level attendance matrix or equivalent mobile UI
- add/remove session members and registered-but-absent flag
- live costs from `calculate_session_costs`
- finalization via `finalize_session`
- waiting/done snapshots from `session_costs_snapshot`
- QR, group QR, and admin manual cash payments
- realtime subscriptions plus polling/manual refresh fallback
- member CRUD with role, active, permanent, create-another behavior
- login/logout, profile link, language switch, authenticated debt badge
- Vietnamese and English labels for all new UI

Adopt from Open Design:

- debt-first homepage
- mobile-first cards
- bottom navigation
- compact Vietnamese-friendly typography
- 44px+ tap targets
- safe-area-aware floating CTAs
- status chips
- bottom-sheet payment modals
- session detail task sections: overview, attendance, costs, payments

Defer/reject:

- overdue/late filters
- guest “I transferred” manual confirmation
- arbitrary selected-session payments on member detail
- prototype-only number-of-intervals selector
- admin activity feed
- public `/sessions` access
- replacing interval attendance with a simple player list

## Architecture Direction

Refactor by decomposition, not backend semantics changes.

```text
Route View
  ├─ owns route params, auth context, top-level loading/error
  ├─ composes route-scoped composables
  └─ renders task-focused panels/components

Composables
  ├─ own Supabase calls and reactive state
  ├─ preserve RPC/table/view contracts
  └─ expose typed state/actions

Components
  ├─ presentational or interaction-focused
  ├─ receive typed props
  └─ emit semantic events
```

Key components:

- `AppShell.vue`, `BottomNav.vue`, `PageHeader.vue`
- `ui/BottomSheet.vue`, `ui/FloatingActionBar.vue`, `ui/StatusChip.vue`, `ui/CurrencyAmount.vue`
- `ui/LoadingState.vue`, `ui/EmptyState.vue`, `ui/ErrorState.vue`

Session detail should use:

- `useSessionDetail`
- `useSessionAttendance`
- `useSessionRegistration`
- `useSessionPayments`
- `useRealtimeRefresh`
- `SessionHeaderCard`, `SessionTabs`, `AttendancePanel`, `CostSummaryPanel`, `PaymentSnapshotPanel`

Keep `/session/:id` as one route; do not create nested tab routes in this milestone.

## Watch Outs / Stop-Ship Risks

Do not ship a phase if:

1. A route disappears or changes access behavior without approval.
2. Guests cannot view debt or create QR payment without login.
3. Admin-only actions appear for non-admin users.
4. QR amount, transfer content, or copy code is wrong.
5. Single, group, home, member-detail, and session-detail payment entry points are not verified.
6. Attendance toggles, absent toggle, member registration, or removal are missing.
7. Frontend recalculates fees instead of displaying RPC/snapshot results.
8. Waiting, done, cancelled, and open session states lose distinct behavior.
9. Realtime subscriptions or polling timers leak after close/navigation.
10. New strings exist in only Vietnamese or only English.
11. Bottom nav or floating CTA blocks content/payment actions at 360-430px.
12. Table-to-card conversion omits financial, status, or action data.
13. `pnpm type-check` or `pnpm build` fails.

## Recommended Exactly-3-Phase Shape

### Phase 1 — Mobile Shell + Debt/Payment Foundation

Establish shared UI guardrails before touching the highest-risk session screen. Deliver app shell, bottom nav, shared primitives, debt-first homepage, member debt entry polish, single/group QR entry points, header/profile/language/debt badge preservation, and route/access verification.

### Phase 2 — Session Detail Task Cockpit

Decompose `SessionDetailView.vue` into composables and task sections. Preserve session loading, interval attendance, registration, absent flag, costs, snapshots, QR/cash/group payments, realtime/polling/manual refresh, guest read-only mode, and admin edit/cancel/finalize gates.

### Phase 3 — Admin/Supporting Screens + Payment Polish + Regression Pass

Polish session list, create session, members, member detail, login, QR/manual payment sheets, i18n completion, mobile overflow/tap-target pass, and final no-regression validation.

## Requirements Implications

Requirements should be preservation-first UI requirements, not new product feature requirements.

Include:

- preserve every existing route and access behavior
- preserve guest debt discovery and QR payment without login
- preserve all Supabase views/RPCs as frontend contracts
- preserve session detail operations across open, waiting, done, and cancelled states
- preserve admin-only action gates
- preserve i18n coverage for all changed screens
- preserve mobile usability at 360-430px with 44px+ tap targets
- add phase-level regression checklists before implementation begins

Avoid:

- backend schema or business logic rewrites
- new payment semantics
- new public session browsing
- new fee allocation logic
- prototype-only interactions without existing backend support

## Gaps to Address During Planning

- Confirm exact current route guard behavior for `/members` and `/session/:id`.
- Confirm whether member CRUD should remain `isAuthenticated` gated or become stricter `isAdmin` gated; this is a product/security decision, not visual polish.
- Decide whether optional component tests fit phase budget.
- Create explicit feature inventory before implementation so every existing control maps to the new UI.

## Sources

- `.planning/PROJECT.md`
- `.planning/research/STACK.md`
- `.planning/research/FEATURES.md`
- `.planning/research/ARCHITECTURE.md`
- `.planning/research/PITFALLS.md`
