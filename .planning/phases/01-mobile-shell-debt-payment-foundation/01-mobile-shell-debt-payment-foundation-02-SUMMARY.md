---
phase: 01-mobile-shell-debt-payment-foundation
plan: 02
subsystem: ui
tags: [vue, mobile-shell, bottom-navigation, auth-header, tailwind]

requires:
  - phase: 01-mobile-shell-debt-payment-foundation
    provides: Preservation matrix, route/access guardrails, and shell/debt locale keys from plan 01
provides:
  - Three-tab public mobile bottom navigation for Home/Debt, Members, and Sessions
  - Safe-area-aware root shell padding and fixed-layer/toast overlap contract
  - Compact secondary-action header with hidden guest login and preserved authenticated controls
affects: [mobile-shell, auth-header, debt-home, members, sessions, payment-overlap]

tech-stack:
  added: []
  patterns:
    - Vue 3 script-setup shell composition
    - Safe-area-aware fixed mobile navigation
    - Token-guarded authenticated debt badge fetch

key-files:
  created:
    - src/components/BottomNav.vue
  modified:
    - src/App.vue
    - src/components/AppHeader.vue

key-decisions:
  - "Kept bottom navigation public and limited to exactly Home/Debt, Members, and Sessions."
  - "Kept hidden /login route behavior by removing all guest header login affordances while preserving authenticated header actions."
  - "Redirected logout to / and token-guarded debt badge fetches to avoid stale updates after sign-out."

patterns-established:
  - "BottomNav owns the mobile primary route set; admin/login/profile/create-session stay out of the bottom nav."
  - "App.vue documents fixed layer order and reserves mobile safe-area padding for fixed actions."
  - "AppHeader uses existing Pinia/Supabase auth state and view_member_debt_summary for authenticated debt only."

requirements-completed: [SHELL-01, SHELL-03, SHELL-04, ADMIN-04]

duration: 1m27s
completed: 2026-05-25
---

# Phase 1 Plan 02: Mobile Shell, Compact Header, and Hidden Login Summary

**Safe-area mobile shell with exactly three public tabs and a compact auth-aware header that keeps login hidden.**

## Performance

- **Duration:** 1m27s
- **Started:** 2026-05-25T10:34:45Z
- **Completed:** 2026-05-25T10:36:12Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- Added `BottomNav.vue` with exactly three mobile tabs: Home/Debt (`/`), Members (`/members`), and Sessions (`/sessions`).
- Wired the app shell to render the bottom nav and reserve `calc(96px + env(safe-area-inset-bottom))` bottom padding on mobile.
- Refactored the header into a compact secondary-action area: language remains visible, guest login stays hidden, authenticated debt/profile/admin/logout remain available.
- Guarded authenticated debt badge fetching and changed logout redirect to `/` to prevent hidden-login surfacing or stale debt badge updates after sign-out.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add exact three-tab public mobile bottom navigation** - `7a24476` (feat)
2. **Task 2: Wire shell layout and safe-area page padding** - `193a54f` (feat)
3. **Task 3: Refactor header into compact secondary-action header** - `de7826c` (feat)

**Plan metadata:** pending final docs commit

## Files Created/Modified

- `src/components/BottomNav.vue` - New fixed mobile bottom navigation with safe-area padding, active indigo state, and no login/admin/create/profile tabs.
- `src/App.vue` - Imports/renders `BottomNav`, keeps `AppHeader`, preserves auth initialization, adds safe-area mobile padding and fixed-layer/toast guidance.
- `src/components/AppHeader.vue` - Compact sticky header with always-visible language switcher, hidden guest login, authenticated menu actions, home logout redirect, and guarded debt badge fetches.

## Verification

- `pnpm type-check` — passed
- `pnpm build` — passed
- Targeted nav/access checks — confirmed:
  - Bottom nav links only to `/`, `/members`, and `/sessions`.
  - `/login` remains directly addressable in `src/router/index.ts`.
  - `/create-session` remains route-gated.
  - Admin header action remains gated by `authStore.isAdmin`.
  - Authenticated debt badge still reads `view_member_debt_summary`.
  - Logout redirects to `/`, not `/login`.

Human UAT/visual sweep was intentionally skipped per the user's autonomous autopilot instruction.

## Decisions Made

- Used existing locale keys (`nav.debtHome`, `nav.members`, `nav.sessions`) instead of adding new copy.
- Kept admin/settings as an authenticated header menu item linking to sessions, gated by `authStore.isAdmin`; did not add any admin bottom tab.
- Used a fetch token to ignore debt badge responses that resolve after logout or profile changes.

## Deviations from Plan

None - plan executed as specified.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None found in created/modified files.

## Next Phase Readiness

- Future debt-home/group-payment work can rely on the root shell bottom padding and documented fixed-layer contract.
- Future route/access validation should continue to preserve the hidden `/login` route and admin-only `/create-session` guard.

## Self-Check: PASSED

- Found created/modified files: `src/components/BottomNav.vue`, `src/App.vue`, `src/components/AppHeader.vue`.
- Found task commits: `7a24476`, `193a54f`, `de7826c`.
- Stub scan found no TODO/FIXME/placeholder/empty-rendering stubs in created/modified files.

---
*Phase: 01-mobile-shell-debt-payment-foundation*
*Completed: 2026-05-25*
