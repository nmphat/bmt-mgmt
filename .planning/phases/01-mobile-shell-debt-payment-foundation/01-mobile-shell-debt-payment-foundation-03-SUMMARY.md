---
phase: 01-mobile-shell-debt-payment-foundation
plan: 03
subsystem: ui
tags: [vue, supabase, debt, payments, mobile]
requires:
  - phase: 01-mobile-shell-debt-payment-foundation
    provides: mobile shell, hidden login, public bottom navigation, locale debt keys
provides:
  - searchable debt-first home backed by view_member_debt_summary
  - selectable mobile debt cards with explicit Details navigation
  - sticky group QR bar positioned above mobile bottom navigation
  - member detail mobile debt-history cards with single-session and Pay All QR entry points
affects: [payment-modal, mobile-debt, member-detail, phase-01-validation]
tech-stack:
  added: []
  patterns:
    - Vue 3 parent-owned search and payment modal state
    - Supabase view/RPC preservation with mobile card presentation
key-files:
  created:
    - .planning/phases/01-mobile-shell-debt-payment-foundation/01-mobile-shell-debt-payment-foundation-03-SUMMARY.md
  modified:
    - src/views/HomePage.vue
    - src/components/HomeDebtTable.vue
    - src/views/MemberDetailView.vue
key-decisions:
  - "Debt home search remains member-name only and continues to sort by total_debt descending from view_member_debt_summary."
  - "Mobile debt card body toggles selection; only the explicit Details link navigates to member detail."
  - "QR payloads stay backend-owned through session snapshots and create_group_payment; no frontend fee allocation was added."
patterns-established:
  - "HomeDebtTable emits search/payment/selection intents only; parent views own Supabase fetches and modal state."
  - "Mobile table-to-card debt history preserves desktop financial fields while hiding desktop tables below md."
requirements-completed: [SHELL-02, SHELL-03, DEBT-01, DEBT-02, DEBT-03, DEBT-04, DEBT-05]
duration: 3m 6s
completed: 2026-05-25T10:41:09Z
---

# Phase 01 Plan 03: Debt home cards, search, group bar, and member debt entry points Summary

**Searchable Supabase debt home with selectable mobile QR cards and member-detail debt-history QR entry points**

## Performance

- **Duration:** 3m 6s
- **Started:** 2026-05-25T10:38:03Z
- **Completed:** 2026-05-25T10:41:09Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- Added member-name debt search owned by `HomePage.vue` while preserving `view_member_debt_summary`, `total_debt` descending sort, pagination, load-more button behavior, and user-facing fetch errors.
- Refactored `HomeDebtTable.vue` mobile cards so the body toggles stable `member_id` selection, QR actions emit payment events, Details is the only member-detail navigation, skeleton/empty states are present, and the group payment bar sits above the bottom nav.
- Preserved member detail debt/payment semantics with `view_member_session_details`, Pay All via `create_group_payment`, single-session QR payloads containing `id: session.snapshot_id`, and mobile debt-history cards exposing the same financial/status/action data as the desktop table.

## Task Commits

1. **Task 1: Add member-name debt search while preserving total-debt sort and load-more** - `691038d` (feat; shared with Task 2 due tightly coupled parent/table contract)
2. **Task 2: Refactor debt cards and sticky group payment bar** - `691038d` (feat)
3. **Task 3: Preserve member detail debt history and QR entry points** - `52cc271` (feat)

**Plan metadata:** pending final docs commit

## Files Created/Modified

- `src/views/HomePage.vue` - Added search state, filtered/paginated Supabase debt queries, error toasts/state, and non-auto-closing payment-complete refresh.
- `src/components/HomeDebtTable.vue` - Added search input, skeleton/empty/error states, mobile selectable debt cards, explicit Details navigation, load-more CTA, and safe-area group QR bar.
- `src/views/MemberDetailView.vue` - Added snapshot id to single-session QR payloads and mobile debt-history cards preserving table financial fields.
- `.planning/phases/01-mobile-shell-debt-payment-foundation/01-mobile-shell-debt-payment-foundation-03-SUMMARY.md` - Execution summary and verification record.

## Decisions Made

- Kept search as an `ilike` filter on `display_name` only, with pagination reset to page 1 and `total_debt` descending order preserved.
- Kept selected group total display-only; `create_group_payment` remains the authoritative source for group QR amount/code.
- Left selected QR/modal payloads parent-owned and visible through payment completion until explicit user close.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Preserved QR success state instead of auto-closing home payment modal**
- **Found during:** Task 1/2 (home payment flow review)
- **Issue:** `HomePage.vue` closed `PaymentQRModal` immediately on `payment-complete`, conflicting with the approved payment behavior that success remains visible until explicit close.
- **Fix:** Payment completion now refreshes debt data without closing the modal or clearing group payload.
- **Files modified:** `src/views/HomePage.vue`
- **Verification:** `pnpm type-check`, `pnpm build`
- **Committed in:** `691038d`

**2. [Rule 1 - Bug] Fixed invalid adjacent `v-else` structure in member detail card/table rendering**
- **Found during:** Task 3 verification
- **Issue:** The initial mobile/desktop history split used two sibling `v-else` blocks, causing Vite/Vue build failure.
- **Fix:** Wrapped mobile and desktop non-loading layouts in a single `template v-else`.
- **Files modified:** `src/views/MemberDetailView.vue`
- **Verification:** `pnpm type-check`, `pnpm build`
- **Committed in:** `52cc271`

---

**Total deviations:** 2 auto-fixed (1 missing critical, 1 bug)
**Impact on plan:** Both fixes were required to preserve approved payment behavior and build correctness; no backend, schema, route, or auth changes were introduced.

## Issues Encountered

- Build initially failed on the member detail `v-else` adjacency issue and was fixed before commit.
- Existing untracked Open Design artifacts and `.planning/config.json` orchestration state were intentionally left untouched and uncommitted.

## Verification

- `pnpm type-check` — passed
- `pnpm build` — passed
- Targeted source checks:
  - `HomePage.vue` still queries `view_member_debt_summary`.
  - Debt query still orders by `total_debt` descending.
  - Search filters by `display_name` and resets `currentPage` to 1.
  - No overdue/high-debt/partial-payment chip code or labels were introduced.
  - `HomeDebtTable.vue` contains no modal close/payment-complete ownership.
  - `MemberDetailView.vue` still uses `view_member_session_details` and `create_group_payment`.
  - Single-session QR payload includes `id: session.snapshot_id`.

## Known Stubs

None. Stub-pattern scan produced only false positives for intentional empty arrays/maps/null modal-state initialization and search placeholder locale usage.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Debt home and member detail now expose the Phase 1 mobile debt entry points needed for the payment sheet work in Plan 04.
- Plan 04 should continue validating payment sheet close/done ownership and QR success behavior across home and member detail.

## Self-Check: PASSED

- Found expected modified files: `src/views/HomePage.vue`, `src/components/HomeDebtTable.vue`, `src/views/MemberDetailView.vue`
- Found summary file: `.planning/phases/01-mobile-shell-debt-payment-foundation/01-mobile-shell-debt-payment-foundation-03-SUMMARY.md`
- Found task commits: `691038d`, `52cc271`

---
*Phase: 01-mobile-shell-debt-payment-foundation*
*Completed: 2026-05-25*
