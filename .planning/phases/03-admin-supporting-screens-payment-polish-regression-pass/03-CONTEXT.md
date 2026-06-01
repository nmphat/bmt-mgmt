# Phase 3: Admin/Supporting Screens + Payment Polish + Regression Pass - Context

**Gathered:** 2026-05-25  
**Status:** Ready for planning  
**Mode:** Autonomous defaults from roadmap, prior phase decisions, and current Vue/Supabase source. Open Design/local artifacts remain directional only.

<domain>

## Phase Boundary

Phase 3 completes the preservation-first UI refactor across the remaining admin/supporting surfaces: sessions list, create-session flow, members list/CRUD, member detail/table-to-card polish, shared QR/manual payment dialogs, and final milestone regression evidence.

This phase may refactor layout, responsive presentation, copy, local component extraction, and accessibility/fixed-layer behavior. It must not change route permissions, Supabase schemas, RPC contracts, payment semantics, member/session mutation authority, or backend-owned financial calculations.

</domain>

<decisions>

## Implementation Decisions

### Sessions list and create-session flow

- **D-01:** `/sessions` remains public read-only. Guests and members can view session cards and navigate to `/session/:id`; only admins see create/mutation affordances.
- **D-02:** Sessions list mobile cards must preserve title, status, date, interval count, registration count, and detail navigation. Desktop/tablet may keep or lightly polish the current grid/card layout.
- **D-03:** `/create-session` remains guarded by `requiresAuth` and `requiresAdmin`. The form must keep current validation, toast behavior, loading state, date/time/fee fields, and `create_session_with_intervals` RPC payload.
- **D-04:** Create-session polish should improve mobile form density, labels, safe spacing, and submit affordance without inventing new recurrence, court, fee-splitting, or default-member behavior.

### Members list and member detail support

- **D-05:** `/members` remains public read-only for viewing members and navigating to member detail. Add/edit/delete controls and handlers remain admin-only through `authStore.isAdmin`.
- **D-06:** Members mobile cards must preserve display name, role, active state, permanent state, Details navigation, and admin edit/delete actions. Desktop table information must remain available.
- **D-07:** Member add/edit/delete semantics remain unchanged: `members.insert`, `members.update`, `members.delete`, role field, active/permanent fields, create-another behavior, loading state, toast feedback, and delete confirmation.
- **D-08:** Member detail must preserve debt summary, session history, interval time display, final amount, court fee, shuttle fee, paid/remaining/status fields, single QR, group/pay-all QR, and `view_member_session_details`/`create_group_payment` behavior.

### Payment modal polish

- **D-09:** `PaymentQRModal.vue` remains the single QR/group QR sheet for home, member detail, and session detail. It must preserve QR URL generation, transfer content copy, group breakdown, polling, payment-complete event, explicit close/Done dismissal, and cleanup on close/unmount.
- **D-10:** `ManualPaymentModal.vue` remains the admin manual cash sheet. It must preserve two-step entry/review confirmation and `add_manual_payment`; non-admin access remains prevented by callers.
- **D-11:** Payment sheets use the Phase 1/2 mobile contract: bottom sheet on mobile, dialog on desktop, `max-h-[88dvh]`, internal scroll, sticky safe-area footer, labelled dialog semantics, accessible close controls, QR alt text, and 44px controls.
- **D-12:** Do not add guest "I transferred" confirmation, auto-close-on-paid, frontend payment allocation, aggregate cash splitting, or new payment status authority.

### Final regression and no-regression guardrails

- **D-13:** Final validation must cover all public routes: `/`, `/members`, `/member/:id`, `/sessions`, `/session/:id`, `/login`, and guarded `/create-session`.
- **D-14:** Final validation must re-check Supabase preservation for all milestone contracts, especially `create_session_with_intervals`, member CRUD, `view_member_debt_summary`, `view_member_session_details`, `view_session_summary`, `calculate_session_costs`, `finalize_session`, `add_member_to_session_full_presence`, `create_group_payment`, `add_manual_payment`, `session_costs_snapshot`, `session_registrations`, `interval_presence`, and `sessions.update(...)`.
- **D-15:** Table-to-card conversions must not omit financial, status, or action fields. Desktop tables/grids should remain available where already used; mobile cards are additive unless the plan proves equivalent preservation.
- **D-16:** Human visual UAT remains skipped/deferred per the user's autonomous execution instruction. Use automated/source/build evidence, route/access checks, contract checks, locale parity checks, and fixed-layer source evidence unless a real blocker appears.

### Copy, accessibility, and visual rules

- **D-17:** All new labels must be added to both Vietnamese and English in `src/locales/messages.ts`.
- **D-18:** Use the established app visual language: neutral gray shell, white cards, rounded borders, indigo primary actions, semantic blue/orange/green/red/gray statuses, visible focus rings, and no new UI framework.
- **D-19:** Changed mobile screens must keep 44px tap targets and safe-area-aware spacing so bottom nav, floating bars, toasts, and sheets do not cover primary actions at 360-430px.
- **D-20:** Open Design/local prototypes are directional for hierarchy, cards, status chips, and sheet density only. The current Vue/Supabase behavior remains authoritative.

### the agent's Discretion

- The planner may decide exact component extraction boundaries, card grouping, status chip helpers, skeleton styling, and icons, provided all fields/contracts remain source-verifiable and type-check/build pass.
- The planner may decide whether to touch member detail in this phase beyond final validation if the existing Phase 1 card layout already satisfies ADMIN-06 preservation.
- The planner may sequence payment modal polish before or after admin/supporting screens, provided final regression covers all payment entry points.

</decisions>

<canonical_refs>

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone and requirements

- `.planning/PROJECT.md` - milestone goal, non-negotiables, preservation-first rules.
- `.planning/REQUIREMENTS.md` - Phase 3 requirement IDs ADMIN-01, ADMIN-02, ADMIN-03, ADMIN-05, ADMIN-06.
- `.planning/ROADMAP.md` - Phase 3 goal, success criteria, validation notes, no-regression guardrails.
- `.planning/STATE.md` - current progress and locked decisions from Phase 1 and Phase 2.

### Prior phase guardrails to preserve

- `.planning/phases/01-mobile-shell-debt-payment-foundation/01-UI-SPEC.md` - shared shell, card, sheet, safe-area, and copy rules.
- `.planning/phases/01-mobile-shell-debt-payment-foundation/01-PRESERVATION-MATRIX.md` - route/access/Supabase preservation baseline.
- `.planning/phases/01-mobile-shell-debt-payment-foundation/01-VERIFICATION.md` - Phase 1 verification and deferred human-UAT note.
- `.planning/phases/02-session-detail-task-cockpit/02-UI-SPEC.md` - session cockpit sheet/card/fixed-layer patterns to keep consistent.
- `.planning/phases/02-session-detail-task-cockpit/02-PRESERVATION-INVENTORY.md` - session detail contracts that final regression must preserve.
- `.planning/phases/02-session-detail-task-cockpit/02-VERIFICATION.md` - Phase 2 verification evidence and deferred human-UAT note.

### Current Vue implementation

- `src/router/index.ts` - route/access source of truth.
- `src/views/DashboardView.vue` - public sessions list and admin create affordance.
- `src/views/CreateSessionView.vue` - guarded create-session form and `create_session_with_intervals` RPC.
- `src/views/MemberView.vue` - member list, admin add/edit/delete, create-another, and member detail navigation.
- `src/views/MemberDetailView.vue` - member debt/session history, mobile cards, single QR, group QR, `view_member_session_details`.
- `src/components/PaymentQRModal.vue` - shared QR/group payment sheet, polling, copy, success, close behavior.
- `src/components/ManualPaymentModal.vue` - admin cash sheet and `add_manual_payment`.
- `src/components/BottomNav.vue` and `src/App.vue` - bottom nav and fixed-layer/safe-area baseline.
- `src/stores/auth.ts` - auth/admin state source.
- `src/stores/lang.ts` and `src/locales/messages.ts` - i18n source.
- `src/types/index.ts` - Supabase-driven data types and payment/group payload types.

### Product/API constraints

- `docs/api.yaml` - Supabase/PostgREST contract reference.
- `docs/summary.md` - app requirements and Supabase boundary.

### Directional Open Design/local prototype references

- `mobile-prototypes/` - mobile hierarchy/card/sheet direction only.
- `mobile-screen-audit.html` and `mobile-screen-audit-2.html` - mobile issues and fixed-layer risks.
- `brand-spec.md` - neutral shell, indigo accent, semantic statuses, density guidance.

</canonical_refs>

<code_context>

## Existing Code Insights

### Reusable Assets

- `DashboardView.vue` already fetches `view_session_summary`, renders session cards, and gates Create Session with `authStore.isAdmin`.
- `CreateSessionView.vue` already uses `create_session_with_intervals` with title, start/end time, court fee, shuttle fee, and `created_by`.
- `MemberView.vue` already guards add/edit/delete handlers with `authStore.isAdmin` and preserves `members.insert`, `members.update`, and `members.delete`.
- `MemberDetailView.vue` already has mobile session cards and desktop table for debt history, plus single/group QR flows.
- `PaymentQRModal.vue` and `ManualPaymentModal.vue` already have the Phase 1 sheet foundation: `88dvh` cap, internal scroll, sticky safe-area footer, dialog semantics, and explicit close behavior.

### Established Patterns

- Vue 3 `<script setup lang="ts">`, Pinia stores, Tailwind utilities, `vue-toastification`, date-fns formatting, and Supabase JS remain the implementation conventions.
- Component visibility and handler guards both matter for admin actions.
- Frontend displays Supabase view/RPC/snapshot values. It must not split shared fees, allocate cash payments, or redefine payment/debt authority.
- Loading, empty, and error states should use local Vue/Tailwind primitives rather than a new UI framework.

### Integration Points

- Route access remains centralized in `src/router/index.ts`; component-level admin affordances remain in each view.
- Session list cards link to `/session/:id`; member cards/table rows link to `/member/:id`.
- Payment modals are shared across Home, Member Detail, and Session Detail, so any modal polish must validate all entry points.
- Final validation should run type-check/build and source checks across all touched surfaces, not only Phase 3 files.

</code_context>

<specifics>

## Specific Ideas

- Use Phase 1/2 mobile card density and status chips consistently across sessions list, members list, create-session, and payment sheets.
- Prefer additive mobile card layouts with preserved desktop tables/grids over risky full rewrites.
- Keep hidden login behavior: no guest-facing login affordance; `/login` remains directly addressable.
- Keep human UAT skipped/deferred unless an implementation blocker requires user input.

</specifics>

<deferred>

## Deferred Ideas

- No backend schema, RLS, RPC, or view changes.
- No new payment method, guest transfer confirmation, aggregate cash allocation, or offline mode.
- No realtime health dashboard beyond existing manual refresh/polling evidence.
- No new desktop redesign beyond preservation-safe polish.

</deferred>

---

*Phase: 03-admin-supporting-screens-payment-polish-regression-pass*  
*Context gathered: 2026-05-25 via autonomous defaults*
