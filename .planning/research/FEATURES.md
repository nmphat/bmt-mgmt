# Feature Research — UI Refactor Milestone

**Project:** Badminton Session Manager  
**Scope:** No-regression feature inventory for Open Design-guided UI refactor  
**Researched:** 2026-05-20

## Summary

This milestone is a UI/UX refactor, not a product expansion. The live app’s most important path is debt-first: guests can open `/`, understand what they owe, and create QR payments without logging in. The highest-risk screen is `/session/:id`, which currently combines attendance, registration, costs, realtime/polling, finalization, cancellation, snapshots, QR, cash, and group payment.

Open Design should influence layout and mobile interaction patterns, but it must not override current route access, role permissions, payment semantics, attendance behavior, or Supabase-backed business logic.

## Feature Categories

### Guest debt discovery and payment

Must preserve:

- Guest can access `/` without login.
- Debt summary loads from `view_member_debt_summary`.
- Rows/cards show member name, total debt, and unpaid session count.
- Guest can open `/member/:id`.
- Guest can pay one member’s unpaid debt via QR.
- Guest can select multiple members and create a group QR via `create_group_payment`.
- Pagination/load more, empty states, loading states, and i18n remain.

Open Design to adopt:

- debt summary prominent at top
- mobile-first cards
- search/selection affordance if supported by current data
- safe-area floating group-pay CTA

### Member debt history

Must preserve:

- Public/readable `/member/:id`.
- Member name and total debt, including fallback when member has no debt row.
- Per-session debt history from `view_member_session_details`.
- Session title/date, final amount, paid amount, remaining amount, court fee, shuttle fee, status, and interval summary.
- Pay all unpaid sessions and pay a single session via QR.
- Payment completion refresh.

### Session list

Must preserve:

- `/sessions` route and current admin route guard.
- Session cards with title, date, status, interval count, registration count.
- Navigation to `/session/:id`.
- Admin create-session CTA.
- Loading and empty states.

Do not make `/sessions` public just because the prototype has a guest “Buổi” tab unless route/RLS requirements explicitly change.

### Session detail

Must preserve:

- `/session/:id` route and guest read-only access.
- Session header: title, date, court fee, shuttle fee, status, total collected where relevant.
- Admin edit, cancel, finalize for allowed statuses.
- Cancelled read-only banner.
- Open sessions show attendance and live costs.
- Waiting-for-payment/done sessions show payment snapshots.

Attendance:

- all registered members and intervals
- interval presence toggles
- guest read-only disabled controls
- disabled controls for absent/done/waiting states
- add active members to session
- remove registered members
- registered-but-absent toggle
- visible absent state
- sticky member column or mobile equivalent that preserves interval-level editing

Costs:

- live costs from `calculate_session_costs`
- member totals, interval count, court fee, shuttle fee
- surplus fund
- refresh after attendance changes

Payments:

- snapshots from `session_costs_snapshot`
- must-pay, paid, status, intervals, court fee, shuttle fee
- single QR for unpaid snapshot
- admin cash/manual payment
- group selection and group QR via `create_group_payment`
- floating selected-payment CTA
- payment completion refresh

Realtime/sync:

- `interval_presence` realtime
- `session_registrations` realtime
- `session_costs_snapshot` update handling
- polling or validated fallback
- manual refresh

### Member management

Must preserve:

- `/members` route and guest-visible member list.
- Authenticated CRUD controls as current behavior unless explicitly changed.
- Add member: display name, role, active, permanent, create another.
- Edit: display name, role, active, permanent.
- Delete confirmation.
- Loading and toast feedback.

Warning: current UI gates CRUD with `authStore.isAuthenticated`, not `isAdmin`. Changing this is an authorization decision, not a visual refactor detail.

### Create session

Must preserve:

- `/create-session` protected by auth/admin route guard.
- Form fields: title, date, start, end, court fee, shuttle fee.
- End time validation.
- RPC `create_session_with_intervals`.
- Loading, success/error toast, and redirect.

Reject prototype-only “number of intervals” unless derived from start/end only.

### Login/header/language/profile

Must preserve:

- `/login` email/password login via Supabase.
- Inline error and toast on failure.
- Global header.
- Logo home link.
- Language switch.
- Login/logout.
- User menu.
- Profile link to `/member/:id`.
- Admin link.
- Authenticated debt badge.
- Vietnamese and English strings for all new labels.

## Open Design Inputs to Adopt

| Input | Decision |
|-------|----------|
| Debt-first home | Required direction |
| Bottom navigation | Required mobile shell pattern |
| 44px+ tap targets | Required on mobile |
| Safe-area floating CTA | Required for selected-payment bars |
| Cards/status chips | Adopt across mobile layouts |
| Bottom-sheet payment modal | Strongly adopt while preserving modal behavior |
| Session detail task tabs | Strongly adopt: overview, attendance, costs, payments |
| Vietnamese-friendly compact labels | Adopt with i18n |

## Open Design Inputs to Adapt or Reject

| Prototype idea | Decision |
|----------------|----------|
| Overdue/late filters | Defer; current backend fields not present |
| Guest “I transferred” manual confirmation | Reject for this milestone; not current behavior |
| Arbitrary selected-session payments on member detail | Defer; current UI supports pay all and single session |
| Number-of-intervals selector on create session | Reject/adapt; backend derives intervals from start/end |
| Admin activity feed | Reject; no backend support |
| Replacing attendance matrix with simple player list | Reject; loses interval-level attendance |
| Making sessions public | Reject unless route requirements change |

## Suggested 3-Phase Fit

1. **Mobile Shell + Debt/Payment Foundation** — app shell, bottom nav, debt home, member debt entry, QR foundation.
2. **Session Detail Task Cockpit** — session detail decomposition and no-regression attendance/cost/payment preservation.
3. **Admin + Supporting Screens Polish** — sessions, create session, members, login, payment/manual sheets, i18n, cleanup.

## Regression Checks by Phase

Phase 1:

- guest debt home without login
- debt pagination/load more
- single and group QR
- language toggle
- authenticated debt badge
- bottom nav and floating bar safe-area

Phase 2:

- session read-only guest view
- edit/cancel/finalize
- add/remove members
- attendance toggle
- absent toggle
- live costs from RPC
- snapshot table
- QR/cash/group payments
- realtime/polling/manual refresh

Phase 3:

- admin route guards
- create session RPC
- member CRUD
- login success/error
- all new i18n keys
- mobile overflow/tap target pass
