# Pitfalls Research — UI Refactor Milestone

**Project:** Badminton Session Manager  
**Scope:** Risks and no-regression gates for Open Design-guided UI refactor  
**Researched:** 2026-05-20

## Summary

This UI refactor is high-risk because current Vue views coordinate Supabase auth, guest/admin behavior, payment RPCs, realtime, polling, session finalization, attendance mutations, and i18n. The biggest mistake would be copying the Open Design prototype shape while dropping hidden live behavior.

Use exactly 3 phases with risk gates:

1. **Feature Inventory + App Shell Guardrails**
2. **Session Detail Cockpit Refactor**
3. **Payments/Admin Polish + Regression Pass**

## Pitfall Table

| Risk | How it happens | Prevention | Phase |
|------|----------------|------------|-------|
| Guest debt flow goes behind login | Shell treats `/`, `/member/:id`, `/session/:id` as authenticated app pages | Preserve route guard matrix and guest QA | 1 |
| Admin actions leak | New bottom CTAs/cards show mutation actions without auth/admin checks | Keep UI gating and function guards | 1-2 |
| `/sessions` access drifts | Prototype shows guest sessions tab but current route is admin-only | Do not make public unless requirements change | 1 |
| Prototype copied too literally | Prototype omits live attendance/payment/finalization details | Treat prototype as direction only | 1 |
| Session tabs drop controls | Existing functions not mapped to new panels | Map each function/control before extraction | 2 |
| Attendance card loses interval semantics | Mobile card shows summaries only | Every interval toggle must remain reachable | 2 |
| Absent behavior breaks | Absent treated as remove/disable without backend flag | Preserve `is_registered_not_attended` toggle | 2 |
| Frontend recalculates costs | Cards calculate fee splits | Use `calculate_session_costs` and snapshots | 2 |
| Status transitions break | Open/waiting/done/cancelled gates get mixed | Preserve status-specific UI locks | 2 |
| QR amount/code wrong | Refactor passes stale snapshot/group data | Centralize payment props and verify QR URL/copy/polling | 3 |
| Group payment mismatch | Home/member/session entry paths conflated | Keep entry paths separate, normalize to `GroupPaymentData` | 3 |
| Manual cash exposed | Cash button appears for non-admin users | Keep `authStore.isAdmin` gate | 3 |
| Polling leaks | Modal/session timers duplicated or not cleared | One owner per timer, cleanup on close/unmount | 2-3 |
| Realtime silently fails | Subscription status ignored | Preserve manual refresh/polling; add status handling if touched | 2 |
| Home debt selection regresses | Card redesign drops selection/events/load more | Preserve `pay-single`, `pay-group`, `load-more` | 1 |
| Table-to-card hides fields | Secondary columns omitted | Create column-to-card mapping | 1-3 |
| Bottom nav overlaps CTAs | New nav conflicts with group bar/modals/toasts | Define z-index and safe-area rules | 1 |
| Tap targets too small | Dense matrix/check icons stay tiny | Require 44px mobile hit areas | 1-2 |
| Modal accessibility worsens | Bottom sheet loses dialog roles/labels/close | Keep dialog semantics and close controls | 3 |
| i18n missing | New prototype labels hardcoded in Vietnamese | Add every new label in `vi` and `en` | 1-3 |
| Auth initialization breaks | Shell/nav renders before auth resolves | Keep `authStore.initialize()` and router guard behavior | 1 |
| Error handling disappears | Console-only failures hidden by polished empty states | Preserve/improve toasts for mutations/payments | 2-3 |
| No tests/regression harness | Build passes but behavior disappears | Use phase checklists and optional component tests | 1 |

## Required Regression Checklist

### Route/access

- Guest can open `/`, `/member/:id`, `/session/:id`, and `/members` as currently allowed.
- Guest cannot open `/sessions` or `/create-session`.
- Admin can open `/sessions`, `/create-session`, `/members`, `/session/:id`.
- Non-admin cannot access admin-only routes.
- Header/bottom nav shows role-appropriate actions.
- Logout clears profile/debt badge and routes safely.

### Debt home

- Debt list loads from `view_member_debt_summary`.
- Sorting by `total_debt` descending remains.
- Pagination/load-more works.
- Mobile cards show member, total debt, unpaid count, QR action, details link.
- Single and group QR work.
- Selected count/total update.
- Floating group bar does not overlap bottom nav/safe area.

### Session detail

- Summary loads from `view_session_summary`.
- Intervals load by `idx`.
- Registrations load and sort by Vietnamese display name.
- Active unregistered members can be registered.
- Add/remove registration works.
- Attendance upserts to `interval_presence`.
- Absent updates `session_registrations.is_registered_not_attended`.
- Costs display from `calculate_session_costs`.
- Open/waiting/done/cancelled states have distinct read/write behavior.
- QR, cash, and group payments work.
- Manual refresh remains.
- Realtime/polling does not leak duplicate timers.

### Payments

- Single QR amount is `final_amount - paid_amount`.
- Group QR amount is RPC `total_amount`.
- Transfer content/copy code align for single and group payments.
- QR URL encodes amount/content correctly.
- Modal polling starts/stops correctly.
- Paid state emits refresh.
- Manual cash only visible to admin and calls `add_manual_payment`.
- Partial status remains distinct.

### Member detail/admin

- Member no-debt fallback works.
- Debt history loads from `view_member_session_details`.
- Intervals merge through `mergeTimeIntervals`.
- Pay all and per-session pay work.
- Members add/edit/delete preserve role/active/permanent/create-another.
- Create session calls `create_session_with_intervals`.
- Login success/error behavior remains.

### i18n/mobile UX

- New strings exist in both languages.
- Language toggle updates changed screens.
- Vietnamese labels fit at 360px.
- Mobile tap targets are at least 44px.
- Bottom nav, bulk bars, toasts, and sheets respect safe areas.
- Dialogs retain labels, close controls, QR alt text.

## Stop-Ship Criteria

Do not ship a phase if:

1. A route disappears or changes access behavior without approval.
2. Guests cannot view debt or open QR payment without login.
3. Admin-only actions leak to non-admins.
4. Any QR shows wrong amount, wrong content, or copied code mismatch.
5. Single, group, home, member-detail, and session-detail payment entry points are not verified.
6. Attendance toggles, absent toggle, registration, or removal are missing.
7. Costs are recalculated in frontend instead of displayed from RPC/snapshot data.
8. Waiting/done/cancelled states lose distinct read/write behavior.
9. Timers leak after navigation or modal close.
10. Any new UI string exists in only one language.
11. Bottom nav/floating CTA blocks payment buttons or content at 360-430px.
12. Table-to-card conversion omits financial/status/action data.
13. Build/type-check fails.
