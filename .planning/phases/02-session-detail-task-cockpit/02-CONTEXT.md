# Phase 2: Session Detail Task Cockpit - Context

**Gathered:** 2026-05-25  
**Status:** Ready for planning  
**Mode:** Autonomous defaults from prior partial discussion plus local Open Design artifacts; Open Design MCP daemon was unavailable, so local prototype/audit files are directional input only.

<domain>

## Phase Boundary

Phase 2 refactors `SessionDetailView.vue` into a mobile task cockpit with task-focused sections for overview, attendance, costs, and payments. It may reorganize layout, extract local components, add UI-only computed helpers, and add locale labels, but it must preserve every existing Supabase contract, route access behavior, status lock, realtime/polling behavior, and payment entry point.

This phase is the highest-risk preservation phase. The screen currently owns session summary, interval presence, registrations, live cost RPCs, finalized snapshots, group QR, manual cash, edit/cancel/finalize, realtime, and polling. Layout can change only after those behaviors are inventoried and kept available.

</domain>

<decisions>

## Implementation Decisions

### Mobile cockpit structure

- **D-01:** Mobile session detail uses four stacked section cards: Overview, Attendance, Costs, and Payments.
- **D-02:** A sticky mini-tab/anchor row sits below the header/top controls on mobile. Tapping a mini-tab scrolls to the section; active state tracks the section in view when feasible without adding fragile dependencies.
- **D-03:** Default highlighted section is status-aware: open sessions highlight Attendance, waiting-for-payment and done sessions highlight Payments, and cancelled sessions highlight Overview.
- **D-04:** The Overview card is compact. It shows title, date/time, status, court fee, shuttle fee, total collected when relevant, cancelled/read-only messaging, manual refresh, and admin edit/cancel/finalize controls. Do not duplicate deep attendance/payment rows here.
- **D-05:** Desktop and tablet layouts may keep the existing table-oriented structure with light cleanup only. Do not remove desktop financial/status/action columns while optimizing mobile.

### Attendance operations

- **D-06:** Attendance remains its own task section. On mobile, prefer member cards/accordions or compact interval rows over forcing the full matrix as the primary mobile experience. Desktop can keep the sticky-column matrix.
- **D-07:** Admin can still add active members through `add_member_to_session_full_presence`, remove registrations through `session_registrations.delete`, toggle interval presence through `interval_presence.upsert`, and mark registered-but-absent through `session_registrations.update({ is_registered_not_attended })`.
- **D-08:** Guest/read-only, non-admin authenticated, waiting-for-payment, done, cancelled, and registered-but-absent disabled states must remain explicit in UI and handler guards. Mutation controls and handlers use `authStore.isAdmin`, not only authenticated state.
- **D-09:** Registered-but-absent is not member removal. Preserve a visible absent state, preserve disabled interval controls for absent members, and preserve the separate absent toggle for admins while the session is editable.

### Cost and payment sections

- **D-10:** Costs section displays live `calculate_session_costs` results for open/editable sessions: member total, interval count, court fee, shuttle fee, and surplus. The frontend must not recalculate authoritative shared fees.
- **D-11:** Payments section displays finalized `session_costs_snapshot` data for waiting-for-payment and done sessions: member name, must-pay amount, paid amount, payment status, interval count, court fee, shuttle fee, and surplus.
- **D-12:** Guests can create single QR payments from unpaid snapshots where that entry point already exists. Authenticated users can select unpaid snapshots and create group QR payments through `create_group_payment`. Admins can record manual cash through `add_manual_payment`.
- **D-13:** Reuse the Phase 1 `PaymentQRModal.vue` and `ManualPaymentModal.vue` sheet semantics. Do not reintroduce tall modal overflow, auto-close-on-paid behavior, or frontend payment allocation.
- **D-14:** The session-detail group payment bar must sit above the mobile bottom nav with safe-area spacing, matching the Phase 1 fixed-layer guidance. It must not use `bottom-6` on mobile if that can overlap the bottom nav.

### Realtime, polling, and status behavior

- **D-15:** Preserve realtime subscriptions to `interval_presence`, `session_registrations`, and `session_costs_snapshot`. Preserve cleanup on unmount and channel replacement before re-subscribing.
- **D-16:** Preserve polling/manual refresh fallback and avoid duplicate timers. Payment completion refresh should update visible snapshot/cost state without stale state after navigation.
- **D-17:** Preserve distinct behavior for open, waiting-for-payment, done, and cancelled sessions. Waiting/done show snapshot/payment flows; open shows editable attendance and live costs; cancelled is read-only with clear messaging.

### Copy, accessibility, and visual rules

- **D-18:** New UI labels must be added to both Vietnamese and English in `src/locales/messages.ts`.
- **D-19:** Changed mobile controls must keep at least 44px tap targets, visible focus states, semantic buttons/links/inputs, labelled refresh/section navigation controls, and clear disabled states.
- **D-20:** Use the Phase 1 visual language: neutral gray shell, white cards, hairline borders, indigo primary actions, semantic blue/orange/green/gray statuses, mobile density controls, and no new third-party UI framework.
- **D-21:** Local Open Design artifacts are directional, not authoritative. Use their session-detail cockpit idea and mobile card density, but the Vue/Supabase behavior remains source of truth.

### the agent's Discretion

- The planner may choose whether to extract local components from `SessionDetailView.vue` or keep the refactor in one file, provided behavior is preserved and type-check/build stay clean.
- The planner may choose exact mini-tab labels, icons, section IDs, and scroll implementation, provided labels are localized and source-verifiable.
- The planner may decide whether mobile attendance cards default expanded or collapsed, provided all intervals and disabled states are visible and usable.

</decisions>

<canonical_refs>

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone and requirements

- `.planning/PROJECT.md` - milestone goal, non-negotiables, preservation-first rules.
- `.planning/REQUIREMENTS.md` - Phase 2 requirement IDs SESS-01 through SESS-12.
- `.planning/ROADMAP.md` - Phase 2 goal, success criteria, validation notes, no-regression guardrails.
- `.planning/STATE.md` - current progress and Phase 1 decisions.

### Phase 1 foundations to preserve

- `.planning/phases/01-mobile-shell-debt-payment-foundation/01-UI-SPEC.md` - shared mobile visual contract, safe-area/fixed-layer guidance, copy/i18n rules.
- `.planning/phases/01-mobile-shell-debt-payment-foundation/01-PRESERVATION-MATRIX.md` - route/access/Supabase preservation baseline.
- `.planning/phases/01-mobile-shell-debt-payment-foundation/01-PHASE1-VALIDATION.md` - validated route/access/payment/fixed-layer evidence and stricter session admin gates.
- `.planning/phases/01-mobile-shell-debt-payment-foundation/01-VERIFICATION.md` - Phase 1 verification and deferred human-UAT note.

### Current Vue implementation

- `src/views/SessionDetailView.vue` - primary refactor target and behavior source of truth.
- `src/components/PaymentQRModal.vue` - QR sheet, group breakdown, copy, polling, success behavior.
- `src/components/ManualPaymentModal.vue` - admin cash sheet and `add_manual_payment` integration.
- `src/components/BottomNav.vue` - mobile bottom nav safe-area baseline.
- `src/App.vue` - app shell bottom padding and fixed-layer/toast guidance.
- `src/stores/auth.ts` - auth/admin state source.
- `src/stores/lang.ts` and `src/locales/messages.ts` - i18n source.
- `src/types/index.ts` - session, registration, interval, cost, snapshot, group payment types.

### Supabase/API contracts

- `docs/api.yaml` - API reference.
- `docs/summary.md` - app requirements and Supabase boundary.
- Supabase contracts to preserve: `view_session_summary`, `calculate_session_costs`, `finalize_session`, `add_member_to_session_full_presence`, `create_group_payment`, `add_manual_payment`, `session_costs_snapshot`, `session_registrations`, `interval_presence`, and `sessions.update`.

### Directional Open Design/local prototype references

- `mobile-screen-audit.html` and `mobile-screen-audit-2.html` - identifies session detail as too heavy on mobile and recommends tabs/sections for overview, attendance, costs, payments.
- `mobile-prototypes/screens/session-detail.html` - rough mobile card/tabs direction only; do not copy its simplified feature set because it omits current app operations.
- `brand-spec.md` - neutral shell, white cards, indigo accent, semantic statuses, density guidance.

</canonical_refs>

<code_context>

## Existing Code Insights

### Reusable Assets

- `SessionDetailView.vue` already fetches all required data: `view_session_summary`, intervals, all members, registrations, `interval_presence`, `calculate_session_costs`, and `session_costs_snapshot`.
- Existing methods already cover required mutations: `saveSession`, `cancelSession`, `finalizeSession`, `registerMembers`, `removeRegistration`, `togglePresence`, `toggleAbsent`, `handleCreateGroupPayment`, `openPaymentQR`, `openCashPayment`, and `handleCloseQR`.
- Phase 1 payment sheets are already mobile-safe and should be reused from session detail instead of reimplemented.
- `BottomNav.vue` and `App.vue` established bottom-safe spacing that Phase 2 fixed/floating controls should respect.

### Established Patterns

- Vue 3 `<script setup lang="ts">`, Pinia stores, Tailwind utilities, `vue-toastification`, and Supabase JS are the established stack.
- Frontend displays values returned by Supabase views/RPCs/snapshots. It may compute presentation-only totals from returned values, but must not own fee allocation logic.
- Component visibility and handler guards both matter. Phase 1 found and fixed session mutation gates to `authStore.isAdmin`.
- Realtime and polling cleanup are preservation criteria, not optional polish.

### Integration Points

- Route remains `/session/:id`, public read-only.
- Payment completion from `PaymentQRModal` should refresh session detail data without clearing the sheet unless the user closes it.
- Manual cash success should refresh snapshots and leave backend semantics unchanged.
- Section anchors and sticky mini-tabs should account for the sticky app header and mobile bottom nav.

</code_context>

<specifics>

## Specific Ideas

- Use four labels conceptually equivalent to Overview, Attendance, Costs, Payments.
- Open sessions should feel like an admin attendance task cockpit; waiting/done sessions should feel like a payment collection cockpit.
- Do not let the local prototype's simplified "players/cost/debt" tabs drop attendance matrix operations, absent state, snapshots, manual cash, realtime, or polling.
- Fix the known Phase 1 warning that the session-detail group payment bar still uses `bottom-6` and can overlap the Phase 1 bottom nav on mobile.

</specifics>

<deferred>

## Deferred Ideas

- No new backend fields, schema changes, RLS changes, or RPC changes.
- No offline attendance mode, audit history, realtime health indicator, or guest "I transferred" confirmation.
- No full desktop redesign beyond preserving existing table information and lightly improving consistency.
- Human visual UAT remains skipped/deferred per the user's autonomous execution instruction unless a real blocker appears.

</deferred>

---

*Phase: 02-session-detail-task-cockpit*  
*Context gathered: 2026-05-25 via autonomous defaults*
