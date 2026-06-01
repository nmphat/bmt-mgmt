# Phase 1: Mobile Shell + Debt/Payment Foundation - Context

**Gathered:** 2026-05-21  
**Status:** Ready for planning

<domain>

## Phase Boundary

Phase 1 delivers the mobile app shell, debt-first home/member debt experience, QR payment foundation, hidden-admin-login behavior, and preservation guardrails. It may refactor UI structure and presentation, but it must not rewrite backend business logic, recalculate debt/cost allocation in the frontend, or remove existing guest/admin/payment capabilities.

Open Design is a directional reference for mobile hierarchy, bottom navigation, cards, sticky action bars, safe-area behavior, and sheets. The Vue/Supabase source remains the behavior source of truth unless this context explicitly records a changed decision.

</domain>

<decisions>

## Implementation Decisions

### Mobile shell and navigation

- **D-01:** Mobile bottom navigation has exactly three public tabs: Home/Debt, Members, and Sessions.
- **D-02:** `/sessions` is public read-only. Admin-only actions on that screen, including Create Session, remain gated by `authStore.isAdmin`; `/create-session` remains admin-only.
- **D-03:** Login is a hidden admin feature. The UI must not show a guest login button. Admins open `/login` manually; after login, profile/logout/admin actions become visible.
- **D-04:** The mobile header holds secondary actions. The language switcher is a compact top-right header control, always visible for guest and admin. Admin actions/profile/logout also live in the compact header/menu, not in an Admin bottom-nav tab.
- **D-05:** Members is public read-only for guests. Guests can open the member list and member detail to view sessions attended and payment status. Admins, after login, can add/edit/delete members.

### Debt discovery and selection

- **D-06:** Home debt uses member-name search and keeps sorting by total debt. Do not add overdue, high-debt, or partial-payment filter chips unless the current backend exposes reliable fields for them.
- **D-07:** On mobile debt cards, tapping the card body toggles selection. Only an explicit Details link/button navigates to member detail, so a missed checkbox tap does not accidentally navigate away.
- **D-08:** Home debt cards show name, total debt, unpaid session count, selected state, QR action, and Details link. Do not show per-session rows on the home card.
- **D-09:** Group payment uses clear selected state plus a sticky group payment bar positioned above the bottom nav. Do not implement prototype long-press selection in v1.
- **D-10:** Loading uses skeleton/card placeholders. Empty debt state clearly communicates debt-free/clean state. Keep the current load-more button behavior; do not switch to infinite scroll or pull-to-refresh in Phase 1.
- **D-11:** Do not change current cash-payment logic during Phase 1. Guests/members see QR payment actions only. Admin cash is visible only where the current snapshot context safely supports it, and never for guests.

### QR and cash payment sheets

- **D-12:** On mobile, QR/cash payment UI is a bottom sheet capped around `88dvh`, with inner content scrolling and sticky/safe-area-aware footer actions. On desktop, keep a dialog presentation.
- **D-13:** QR sheet content order is: amount first, QR image, transfer content with copy action, member/group breakdown, then status note/actions.
- **D-14:** Payment polling runs only while the sheet is open. When payment is detected, show a success state, emit a refresh, and let the user close with Done/Close instead of auto-closing.
- **D-15:** Admin cash payment requires double confirmation. After entering amount/note, show a second confirmation step in the same sheet with member/session, amount, remaining debt, and note before calling `add_manual_payment`.

### Feature-preservation guardrails

- **D-16:** Before implementation, create a preservation matrix for touched screens containing route, component, role/access behavior, Supabase contract, and payment entry points.
- **D-17:** Route/access verification must cover guest access to `/`, `/members`, `/member/:id`, `/sessions`, and `/session/:id`; only admin can create/edit/delete/finalize/cash/admin actions.
- **D-18:** Every new label has Vietnamese and English locale keys. Changed mobile screens must be visually swept at 360px, 390px, and 430px to confirm bottom nav, sticky group bar, sheets, and toasts do not cover primary content/actions.
- **D-19:** Phase 1 validation requires type-check/build plus manual guest/admin sweeps for debt, members, sessions list, QR/group QR, hidden login, and admin actions.

### the agent's Discretion

- Exact component names, extraction boundaries, icon choices, skeleton styling, spacing values, and Tailwind class composition are left to the planner/implementer, provided the decisions above and existing codebase conventions are preserved.
- The planner may decide whether shared UI primitives live in `src/components/` directly or a subfolder, as long as the implementation stays consistent and avoids duplicating one-off card/sheet patterns.

</decisions>

<canonical_refs>

## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone and phase scope

- `.planning/PROJECT.md` — milestone goal, constraints, validated existing capabilities, Open Design direction.
- `.planning/REQUIREMENTS.md` — Phase 1 requirement IDs and milestone out-of-scope boundaries.
- `.planning/ROADMAP.md` — Phase 1 goal, success criteria, validation notes, no-regression guardrails.
- `.planning/research/SUMMARY.md` — synthesized research and risk framing for the UI refactor.

### Product/API constraints

- `docs/summary.md` — original frontend requirements, Supabase boundary, mobile and formatting rules.
- `docs/api.yaml` — Supabase/PostgREST contract reference.

### Open Design directional reference

- `mobile-prototypes/index.html` — prototype index and stated mobile-first system intent.
- `mobile-prototypes/screens/home.html` — debt-first home layout, public bottom nav, selection bar, payment sheet reference.
- `mobile-prototypes/styles.css` — directional tokens/patterns for cards, status chips, bottom nav, bulk bar, sheets, safe-area spacing.

### Current Vue implementation

- `src/router/index.ts` — route/access source of truth.
- `src/App.vue` — root shell structure.
- `src/components/AppHeader.vue` — current header, language switcher, auth/profile/logout/debt badge behavior.
- `src/views/DashboardView.vue` — sessions list; now public read-only with admin-gated create action.
- `src/views/HomePage.vue` — debt home data fetching and group QR creation.
- `src/components/HomeDebtTable.vue` — current debt list/card/table selection UI and floating group payment bar.
- `src/components/PaymentQRModal.vue` — QR modal, group breakdown, copy, polling, success behavior.
- `src/components/ManualPaymentModal.vue` — admin cash modal and `add_manual_payment` integration.
- `src/views/MemberDetailView.vue` — member debt history and single/group QR entry points.
- `src/stores/auth.ts` — auth/admin profile state.
- `src/stores/lang.ts` and `src/locales/messages.ts` — i18n store and VI/EN message keys.

</canonical_refs>

<code_context>

## Existing Code Insights

### Reusable Assets

- `AppHeader.vue`: already owns language switching, profile/logout, auth state, and authenticated debt badge; Phase 1 should convert it to the compact header pattern while keeping login hidden.
- `HomeDebtTable.vue`: already has mobile card layout, selected member state, desktop table, load more, and a fixed group payment bar. Reuse/refactor rather than replacing the flow.
- `PaymentQRModal.vue`: already handles QR URL generation, transfer content copy, group member breakdown, polling, success state, and payment refresh events.
- `ManualPaymentModal.vue`: existing admin cash entry point with `add_manual_payment`; should be converted/polished as a responsive sheet/dialog without changing RPC semantics.
- `MemberDetailView.vue`: already has member debt history from `view_member_session_details`, pay-all group QR, and single-session QR from snapshot-like data.
- `src/locales/messages.ts`: existing VI/EN structure should receive every new shell/debt/payment string.

### Established Patterns

- Vue 3 `<script setup lang="ts">`, Pinia stores, Tailwind utility styling, `vue-toastification`, and Supabase queries/RPCs are the established patterns.
- Business logic stays in Supabase views/RPCs. The frontend may display totals returned by views/snapshots, but must not allocate shared costs or split aggregate cash payments itself.
- Route access is enforced in `src/router/index.ts`, while component-level visibility still needs role gates for admin-only actions.
- Payment polling should clean up on modal/sheet close/unmount to prevent timer leaks.

### Integration Points

- Shell changes connect through `App.vue`, `AppHeader.vue`, and a new/refactored bottom navigation component.
- Debt home changes connect through `HomePage.vue` and `HomeDebtTable.vue`.
- Payment sheet changes connect through `PaymentQRModal.vue` and later `ManualPaymentModal.vue`.
- Session list access connects through `src/router/index.ts` and `DashboardView.vue`.

### Source corrections already made during discussion

- `/sessions` route guard was removed so the sessions list can be public read-only.
- `DashboardView.vue` Create Session link was changed from `authStore.isAuthenticated` to `authStore.isAdmin`.
- Guest login button was removed from `AppHeader.vue`; `/login` remains directly addressable for admins.

</code_context>

<specifics>

## Specific Ideas

- The user explicitly wants login to be hidden: no visible guest login button, admin opens `/login` manually.
- The user explicitly wants a public mobile bottom nav with Home/Debt, Members, and Sessions.
- The user called out a current modal bug: payment/cash modal content can become too tall and obscure information. Payment sheets must cap height, scroll content, and keep actions safe-area-aware.
- Avoid accidental navigation on debt cards: card body selects, Details navigates.

</specifics>

<deferred>

## Deferred Ideas

- Overdue/high-debt/partial-payment filter chips are deferred until backend fields reliably support them.
- Long-press debt selection from the prototype is deferred; v1 uses explicit tap/select behavior.
- Aggregate cash payment directly from a member's home debt card is not part of Phase 1 unless a backend-safe snapshot allocation contract exists; do not implement frontend allocation.
- Guest "I transferred" confirmation remains out of scope for this milestone.

</deferred>

---

*Phase: 01-mobile-shell-debt-payment-foundation*  
*Context gathered: 2026-05-21*
