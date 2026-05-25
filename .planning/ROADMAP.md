# Roadmap: Badminton Session Manager v1.0 UI Refactor

**Milestone:** v1.0 UI refactor from Open Design  
**Created:** 2026-05-20  
**Granularity:** coarse  
**Phase count:** 3 exactly  
**Core value:** Members and guests can understand what they owe and pay it quickly, while admins can manage sessions without redoing spreadsheet work.

## Milestone Context

This milestone refactors the existing Vue/Supabase app UI using Open Design as a directional reference only. The live application remains the source of truth for routes, permissions, Supabase contracts, payment semantics, attendance behavior, realtime/polling behavior, and i18n.

This is a preservation-first UI refactor:

- No backend business logic rewrite.
- No database schema change.
- No frontend fee recalculation.
- No route/access behavior changes without explicit approval.
- All new UI labels must support Vietnamese and English.
- Changed mobile screens must work at 360-430px without bottom navs, floating CTAs, toasts, or sheets blocking primary actions.

## Phase Table

| # | Name | Goal | Requirements | Dependencies / Status |
|---|------|------|--------------|-----------------------|
| 1 | Mobile Shell + Debt/Payment Foundation | Guests and authenticated users can use the refactored mobile shell and debt-first payment flows without losing current route access, language, auth, or Supabase payment behavior. | SHELL-01, SHELL-02, SHELL-03, SHELL-04, SHELL-05, DEBT-01, DEBT-02, DEBT-03, DEBT-04, DEBT-05, DEBT-06, ADMIN-04 | Depends on: Nothing. Status: Complete |
| 2 | Session Detail Task Cockpit | Guests and admins can use the session detail screen as mobile task-focused sections for overview, attendance, costs, and payments while every current session operation and Supabase contract remains intact. | SESS-01, SESS-02, SESS-03, SESS-04, SESS-05, SESS-06, SESS-07, SESS-08, SESS-09, SESS-10, SESS-11, SESS-12 | Depends on: Phase 1. Status: Complete |
| 3 | Admin/Supporting Screens + Payment Polish + Regression Pass | Admin and supporting screens use the same mobile-first design language, payment dialogs behave correctly on mobile/desktop, and final no-regression checks confirm the refactor preserved existing app behavior. | ADMIN-01, ADMIN-02, ADMIN-03, ADMIN-05, ADMIN-06 | Depends on: Phase 2. Status: Not started |

## Phases

- [x] **Phase 1: Mobile Shell + Debt/Payment Foundation** - Establish the mobile shell, shared UI primitives, debt-first homepage/member debt flows, QR payment foundation, auth/header/language preservation, and phase guardrails.
- [x] **Phase 2: Session Detail Task Cockpit** - Refactor session detail into task-focused mobile sections while preserving attendance, costs, snapshots, payments, admin actions, readonly gates, realtime, and polling.
- [ ] **Phase 3: Admin/Supporting Screens + Payment Polish + Regression Pass** - Polish sessions, create session, members, table-to-card layouts, QR/manual payment sheets, and final regression coverage.

## Phase Details

### Phase 1: Mobile Shell + Debt/Payment Foundation

**Goal**: Guests and authenticated users can use the refactored mobile shell and debt-first payment flows without losing current route access, language, auth, or Supabase payment behavior.

**Depends on**: Nothing

**Requirements**: SHELL-01, SHELL-02, SHELL-03, SHELL-04, SHELL-05, DEBT-01, DEBT-02, DEBT-03, DEBT-04, DEBT-05, DEBT-06, ADMIN-04

**Success Criteria** (what must be TRUE):

1. Guest can open the home page without login, immediately understand member debt from `view_member_debt_summary`, use loading/empty/load-more states, and navigate to member debt details.
2. Guest can create single-member, single-session, and grouped debt QR payments from home/member debt entry points using existing payment contracts without frontend recalculating debt amounts.
3. User can navigate changed mobile screens through a public Home/Members/Sessions bottom shell and compact header without unapproved route access drift, admin-action leakage, or blocked primary actions at 360-430px.
4. User can switch Vietnamese/English and see all new shell, debt, payment, auth, and state labels translated in both locales.
5. Developer can verify route/access behavior, feature inventory, no-regression checklist, and Supabase contract preservation before moving to Phase 2.

**Validation Notes**:

- Open Design guides mobile hierarchy, bottom navigation, cards, safe-area CTAs, and bottom-sheet patterns only.
- Preserve guest access to `/`, `/member/:id`, `/session/:id`, `/members`, and approved public read-only `/sessions`.
- Preserve protected behavior for `/create-session` and all mutation/admin-only actions.
- Preserve Supabase contracts: `view_member_debt_summary`, `view_member_session_details`, and `create_group_payment`.
- Stop ship if QR amount/content/copy code is wrong, if guest debt requires login, or if bottom nav/floating bars cover payment actions.

**Plans**: TBD

**UI hint**: yes

### Phase 2: Session Detail Task Cockpit

**Goal**: Guests and admins can use the session detail screen as mobile task-focused sections for overview, attendance, costs, and payments while every current session operation and Supabase contract remains intact.

**Depends on**: Phase 1

**Requirements**: SESS-01, SESS-02, SESS-03, SESS-04, SESS-05, SESS-06, SESS-07, SESS-08, SESS-09, SESS-10, SESS-11, SESS-12

**Success Criteria** (what must be TRUE):

1. Guest can open session detail in read-only mode and authenticated/admin users see only the mutation controls allowed by current auth, role, status, and session locks.
2. User can view task-focused mobile sections for overview, attendance, costs, and payments while still seeing title, date/time, fees, status, cancelled/read-only messaging, live costs, and finalized payment snapshots.
3. Admin can edit/cancel/finalize sessions, add/remove registered members, toggle interval attendance, and mark registered-but-absent without changing existing Supabase table/RPC behavior.
4. User can create session QR payments, authenticated/admin group QR payments, and admin manual cash payments from existing snapshots/contracts with non-admin access prevented.
5. User can rely on realtime updates, polling/manual refresh fallback, and payment completion refresh without duplicate timers or stale visible state after navigation.

**Validation Notes**:

- Highest-risk phase: `SessionDetailView.vue` behavior must be preserved before layout replacement is considered complete.
- Preserve Supabase contracts: `view_session_summary`, `calculate_session_costs`, `finalize_session`, `add_member_to_session_full_presence`, `create_group_payment`, `add_manual_payment`, `session_costs_snapshot`, `session_registrations`, `interval_presence`, and `sessions.update`.
- Preserve distinct open, waiting-for-payment, done, and cancelled behavior.
- Stop ship if attendance toggles, absent toggle, add/remove registration, payment snapshots, manual refresh, or admin gates regress.
- Frontend must display RPC/snapshot results; it must not recalculate shared fees.

**Plans**: TBD

**UI hint**: yes

### Phase 3: Admin/Supporting Screens + Payment Polish + Regression Pass

**Goal**: Admin and supporting screens use the same mobile-first design language, payment dialogs behave correctly on mobile/desktop, and final no-regression checks confirm the refactor preserved existing app behavior.

**Depends on**: Phase 2

**Requirements**: ADMIN-01, ADMIN-02, ADMIN-03, ADMIN-05, ADMIN-06

**Success Criteria** (what must be TRUE):

1. User can view the sessions list read-only, navigate to session detail, and admins can create sessions through the guarded `create_session_with_intervals` flow with validation and feedback preserved.
2. User can view the member list on mobile, and currently authorized users can add, edit, and delete members without losing role, active, permanent, create-another, loading, toast, or confirmation behavior.
3. User can use QR and manual payment dialogs as responsive mobile sheets or desktop dialogs without losing dialog semantics, close actions, QR alt text, payment polling, refresh behavior, or admin-only cash payment gates.
4. User can view converted mobile card layouts without losing financial fields, status fields, route actions, or desktop-table information.
5. Developer can complete the final no-regression pass confirming route/access behavior, Supabase contract preservation, i18n completeness, mobile safe-area behavior, and build/type-check health.

**Validation Notes**:

- Preserve `/sessions` public read-only behavior, `/create-session` admin guard, `/members`, `/member/:id`, `/login`, and payment modal behavior.
- Preserve Supabase contracts: `create_session_with_intervals`, member CRUD table behavior, payment polling/refresh behavior, and manual payment flow.
- Stop ship if table-to-card layouts omit financial/status/action fields, payment sheets lose accessibility semantics, or any new UI string exists in only one locale.
- Final validation should include no-regression guardrails from all phases.

**Plans**: TBD

**UI hint**: yes

## Coverage

Every v1 requirement maps to exactly one phase.

| Requirement | Phase |
|-------------|-------|
| SHELL-01 | Phase 1 |
| SHELL-02 | Phase 1 |
| SHELL-03 | Phase 1 |
| SHELL-04 | Phase 1 |
| SHELL-05 | Phase 1 |
| DEBT-01 | Phase 1 |
| DEBT-02 | Phase 1 |
| DEBT-03 | Phase 1 |
| DEBT-04 | Phase 1 |
| DEBT-05 | Phase 1 |
| DEBT-06 | Phase 1 |
| SESS-01 | Phase 2 |
| SESS-02 | Phase 2 |
| SESS-03 | Phase 2 |
| SESS-04 | Phase 2 |
| SESS-05 | Phase 2 |
| SESS-06 | Phase 2 |
| SESS-07 | Phase 2 |
| SESS-08 | Phase 2 |
| SESS-09 | Phase 2 |
| SESS-10 | Phase 2 |
| SESS-11 | Phase 2 |
| SESS-12 | Phase 2 |
| ADMIN-01 | Phase 3 |
| ADMIN-02 | Phase 3 |
| ADMIN-03 | Phase 3 |
| ADMIN-04 | Phase 1 |
| ADMIN-05 | Phase 3 |
| ADMIN-06 | Phase 3 |

**Coverage validation**:

- v1 requirements: 29 total
- Mapped to phases: 29
- Unmapped: 0
- Duplicate mappings: 0

## No-Regression Guardrails

A phase must not be considered complete if any of these fail:

1. A route disappears or changes access behavior without approval.
2. Guests cannot view debt or create QR payments without login.
3. Admin-only actions appear for non-admin users.
4. QR amount, transfer content, copied code, or payment status is wrong.
5. Single, group, home, member-detail, and session-detail payment entry points are not verified.
6. Attendance toggles, absent toggle, member registration, or removal are missing.
7. Frontend recalculates shared fees instead of displaying Supabase RPC/snapshot results.
8. Waiting, done, cancelled, and open session states lose distinct behavior.
9. Realtime subscriptions or polling timers leak after modal close/navigation.
10. New strings exist in only Vietnamese or only English.
11. Bottom nav, floating CTA, toast, or sheet blocks primary content/actions at 360-430px.
12. Table-to-card conversion omits financial, status, or action data.
13. Type-check or build fails.

## Supabase Contract Preservation

The UI refactor must preserve current Supabase tables, views, RPC names, parameters, and semantics, including:

- `view_member_debt_summary`
- `view_member_session_details`
- `view_session_summary`
- `create_session_with_intervals`
- `calculate_session_costs`
- `finalize_session`
- `add_member_to_session_full_presence`
- `create_group_payment`
- `add_manual_payment`
- `session_costs_snapshot`
- `session_registrations`
- `interval_presence`
- `sessions.update(...)`

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Mobile Shell + Debt/Payment Foundation | 5/5 | Complete | 2026-05-25 |
| 2. Session Detail Task Cockpit | 5/5 | Complete | 2026-05-25 |
| 3. Admin/Supporting Screens + Payment Polish + Regression Pass | 0/TBD | Not started | - |

## Next Step

Start phase discussion:

`/gsd-discuss-phase 3`
