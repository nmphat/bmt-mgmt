# Requirements: Badminton Session Manager v1.0 UI Refactor

**Defined:** 2026-05-20  
**Core Value:** Members and guests can understand what they owe and pay it quickly, while admins can manage sessions without redoing spreadsheet work.

## v1 Requirements

Requirements for the Open Design-guided UI refactor. This is preservation-first: the UI may change, but existing Vue/Supabase behavior must remain available.

### Foundation and Shell

- [ ] **SHELL-01**: User can navigate the app on mobile with a bottom navigation shell that exposes only role-appropriate destinations and preserves current route access behavior.
- [ ] **SHELL-02**: User can use shared mobile-first UI primitives for cards, status chips, buttons, tabs, bottom sheets, floating action bars, loading states, empty states, and error states consistently across changed screens.
- [ ] **SHELL-03**: User can interact with changed mobile screens at 360-430px without bottom navs, floating CTAs, toasts, or sheets covering primary content or actions.
- [ ] **SHELL-04**: User can switch Vietnamese/English language and see all new UI labels translated in both locales.
- [ ] **SHELL-05**: Developer can verify route/access behavior, feature inventory, and no-regression checklists before shipping each refactor phase.

### Guest Debt and Payment

- [ ] **DEBT-01**: Guest can open the home page without login and immediately see debt as the primary content using data from `view_member_debt_summary`.
- [ ] **DEBT-02**: Guest can view each debtor’s name, total debt, unpaid session count, loading state, empty state, and additional pages via the existing load-more behavior.
- [ ] **DEBT-03**: Guest can open a member debt detail page from debt/home/member list and see debt history from `view_member_session_details`.
- [ ] **DEBT-04**: Guest can create a QR payment for one member or one unpaid session without frontend recalculating debt amounts.
- [ ] **DEBT-05**: Guest can select multiple debt members and create a group QR payment through the existing `create_group_payment` flow.
- [ ] **DEBT-06**: User can see QR payment amount, transfer content, copied code, member breakdown, and payment completion state consistently across home and member-detail entry points.

### Session Detail Cockpit

- [ ] **SESS-01**: Guest can open session detail in read-only mode while authenticated/admin users retain existing mutation controls according to current auth and session status gates.
- [ ] **SESS-02**: User can view session overview details including title, date/time, court fee, shuttle fee, status, total collected when relevant, and cancelled/read-only messaging.
- [ ] **SESS-03**: Admin can edit allowed session fields, cancel an open session, and finalize an open session using the existing Supabase contracts and status locks.
- [ ] **SESS-04**: Admin can add active members to a session and remove registered members without changing `add_member_to_session_full_presence` or `session_registrations` behavior.
- [ ] **SESS-05**: Admin can toggle interval-level attendance for every registered member and interval, with guest/read-only/done/waiting/absent disabled states preserved.
- [ ] **SESS-06**: Admin can mark a registered member as registered-but-absent through `is_registered_not_attended`, and the UI preserves that state separately from member removal.
- [ ] **SESS-07**: User can view live cost summary from `calculate_session_costs`, including member total, interval count, court fee, shuttle fee, and surplus fund.
- [ ] **SESS-08**: User can view finalized payment snapshots for waiting-for-payment and done sessions, including must-pay amount, paid amount, payment status, interval count, court fee, shuttle fee, and surplus.
- [ ] **SESS-09**: User can create single QR payments and authenticated/admin group QR payments from session snapshots using existing snapshot and `create_group_payment` behavior.
- [ ] **SESS-10**: Admin can record manual cash payment from session snapshots using the existing `add_manual_payment` flow, with non-admin access prevented.
- [ ] **SESS-11**: User can rely on realtime updates, polling/manual refresh fallback, and payment completion refresh without duplicate timers or stale visible state after navigation.
- [ ] **SESS-12**: User can use the session detail screen as task-focused mobile sections for overview, attendance, costs, and payments while preserving all current session operations.

### Admin and Supporting Screens

- [ ] **ADMIN-01**: Admin can view the sessions list, see session cards with status/date/interval/registration counts, and navigate to session detail while current `/sessions` guard behavior remains intact.
- [ ] **ADMIN-02**: Admin can create a session with title, date, start time, end time, court fee, and shuttle fee through `create_session_with_intervals`, with end-time validation and loading/error/success feedback preserved.
- [ ] **ADMIN-03**: User can view the member list on mobile, and currently authorized users can add, edit, and delete members with display name, role, active, permanent, and create-another behavior preserved.
- [ ] **ADMIN-04**: User can log in, see login errors, log out, access profile/member link, see authenticated debt badge, and use header actions after the shell refactor.
- [ ] **ADMIN-05**: User can use QR and manual payment modals as responsive mobile sheets or desktop dialogs without losing dialog semantics, close actions, QR alt text, or payment polling/refresh behavior.
- [ ] **ADMIN-06**: User can view table-to-card mobile layouts without losing financial fields, status fields, or actions that existed in desktop tables.

## Future Requirements

Deferred to future milestones.

### Debt Enhancements

- **DEBT-F01**: User can filter debt by overdue, high amount, partial payment, or due date after backend exposes reliable fields.
- **DEBT-F02**: Guest can submit “I transferred” confirmation for admin review after a backend confirmation workflow exists.
- **DEBT-F03**: User can select arbitrary unpaid sessions from member detail and create a partial group QR payment.

### Operations

- **OPS-F01**: Admin can view activity/audit history for session, attendance, member, and payment changes.
- **OPS-F02**: User can use offline-friendly attendance capture when network is unstable.
- **OPS-F03**: Admin can see explicit realtime health or sync status beyond manual refresh/fallback behavior.

### Quality

- **QA-F01**: Developer can run a full automated E2E suite for guest debt payment and admin session flows against stable test data.

## Out of Scope

Explicitly excluded from this milestone.

| Feature | Reason |
|---------|--------|
| Backend business logic rewrite | Existing Supabase RPCs/views own cost, session creation, payment grouping, and manual payment logic |
| Database schema change | UI refactor can use current contracts; prototype-only fields are deferred |
| Public `/sessions` access | Current router protects `/sessions`; changing this is product/access scope |
| Frontend fee allocation | Violates backend boundary and risks wrong shared-cost behavior |
| Prototype-only overdue/late debt filters | Current frontend does not have reliable backend fields for these states |
| Guest manual transfer confirmation | Current behavior is QR polling and admin manual cash payment |
| Native mobile app | Milestone remains Vue SPA |
| Third-party UI framework migration | Current Tailwind/Vue stack is sufficient and lower risk |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SHELL-01 | — | Pending |
| SHELL-02 | — | Pending |
| SHELL-03 | — | Pending |
| SHELL-04 | — | Pending |
| SHELL-05 | — | Pending |
| DEBT-01 | — | Pending |
| DEBT-02 | — | Pending |
| DEBT-03 | — | Pending |
| DEBT-04 | — | Pending |
| DEBT-05 | — | Pending |
| DEBT-06 | — | Pending |
| SESS-01 | — | Pending |
| SESS-02 | — | Pending |
| SESS-03 | — | Pending |
| SESS-04 | — | Pending |
| SESS-05 | — | Pending |
| SESS-06 | — | Pending |
| SESS-07 | — | Pending |
| SESS-08 | — | Pending |
| SESS-09 | — | Pending |
| SESS-10 | — | Pending |
| SESS-11 | — | Pending |
| SESS-12 | — | Pending |
| ADMIN-01 | — | Pending |
| ADMIN-02 | — | Pending |
| ADMIN-03 | — | Pending |
| ADMIN-04 | — | Pending |
| ADMIN-05 | — | Pending |
| ADMIN-06 | — | Pending |

**Coverage:**
- v1 requirements: 29 total
- Mapped to phases: 0
- Unmapped: 29 ⚠

---
*Requirements defined: 2026-05-20*
*Last updated: 2026-05-20 after initial definition*
