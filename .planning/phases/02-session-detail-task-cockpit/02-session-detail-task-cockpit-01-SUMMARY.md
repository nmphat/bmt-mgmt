---
phase: 02-session-detail-task-cockpit
plan: 01
subsystem: ui
tags: [vue, typescript, supabase, i18n, session-detail]

requires:
  - phase: 01-mobile-shell-debt-payment-foundation
    provides: Public read-only route/access baseline, payment sheet behavior, and admin-gate preservation decisions.
provides:
  - Centralized session editability/status-lock helpers for session detail.
  - Guarded session mutation handlers for open/admin-only operations.
  - Phase 2 session cockpit locale copy in Vietnamese and English.
  - Session-detail preservation inventory for Supabase contracts and operations.
affects: [session-detail-task-cockpit, phase-2-layout, payments, attendance]

tech-stack:
  added: []
  patterns:
    - "Session mutation visibility and handlers use isSessionEditable = authStore.isAdmin && session.status === 'open'."
    - "Phase 2 preservation inventory records route/access, operation, realtime, polling, and payment contracts before layout work."

key-files:
  created:
    - .planning/phases/02-session-detail-task-cockpit/02-PRESERVATION-INVENTORY.md
  modified:
    - src/views/SessionDetailView.vue
    - src/locales/messages.ts

key-decisions:
  - "Session detail editability is centralized on authStore.isAdmin plus open status, preserving public read-only /session/:id access."
  - "Registered-but-absent members are blocked from interval_presence upserts before any Supabase mutation."
  - "Manual cash modal opening is explicitly admin-only while QR payment entry points remain public for unpaid snapshots."

patterns-established:
  - "Use attendanceLockMessage for cancelled/finalized/read-only/admin-only status messaging."
  - "Document every required Supabase contract in the phase preservation inventory before further UI layout refactors."

requirements-completed: [SESS-01, SESS-03, SESS-04, SESS-05, SESS-06]

duration: 162s
completed: 2026-05-25T11:21:16Z
---

# Phase 02 Plan 01: Preservation inventory, status locks, and locale foundation Summary

**Session-detail admin/open editability lock with guarded Supabase mutations and Phase 2 preservation inventory.**

## Performance

- **Duration:** 162s
- **Started:** 2026-05-25T11:18:34Z
- **Completed:** 2026-05-25T11:21:16Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- Added `isSessionEditable`, `isReadOnlyViewer`, `isSessionFinalized`, `isSessionCancelled`, and `attendanceLockMessage` helpers in `SessionDetailView.vue`.
- Replaced session mutation control visibility with the centralized editable lock so cancelled, waiting, and done sessions stay read-only.
- Guarded edit/cancel/finalize/register/remove/presence/absent handlers with `isSessionEditable.value`, added absent-member protection before `interval_presence.upsert`, and added an admin-only `openCashPayment` guard.
- Added Phase 2 session cockpit locale keys to both Vietnamese and English.
- Created `02-PRESERVATION-INVENTORY.md` covering `/session/:id`, operation inventory, realtime/polling, payment flows, and required Supabase contracts.

## Task Commits

1. **Task 1: Centralize session editability and status locks** - `d3bea5e` (`feat`)
2. **Task 2: Guard mutation handlers with centralized editability** - `5ea4dd3` (`fix`)
3. **Task 3: Add Phase 2 locale keys and preservation inventory** - `8034485` (`docs`)

## Files Created/Modified

- `src/views/SessionDetailView.vue` - Centralized admin/open editability and status locks; guarded mutation handlers and cash modal opening.
- `src/locales/messages.ts` - Added Phase 2 session cockpit keys in Vietnamese and English.
- `.planning/phases/02-session-detail-task-cockpit/02-PRESERVATION-INVENTORY.md` - Records route/access expectations, operation inventory, Supabase contracts, and skipped/deferred human UAT note.

## Decisions Made

- Session mutation controls and handlers must use `isSessionEditable` rather than repeating status exclusions.
- `togglePresence` now returns before Supabase writes when the registration is marked `is_registered_not_attended`.
- `openPaymentQR` remains public for unpaid snapshots, while `openCashPayment` returns immediately for non-admin users.

## Deviations from Plan

None - plan executed exactly as written.

## Auth Gates

None.

## Verification

- `pnpm type-check` — PASS
- Phase 2 locale parity node check — PASS
- Source check for no old incomplete `authStore.isAdmin && session.status !== 'waiting_for_payment'` mutation-lock pattern — PASS
- Preservation inventory contract grep for `view_session_summary`, `calculate_session_costs`, `finalize_session`, `add_member_to_session_full_presence`, `create_group_payment`, `add_manual_payment`, `session_costs_snapshot`, `session_registrations`, `interval_presence`, and `sessions.update` — PASS

## Known Stubs

None. Locale keys containing the word `Placeholder` are existing i18n key names, not stubbed UI data.

## Threat Flags

None. No new endpoints, schema changes, file access patterns, or trust-boundary surfaces were introduced; existing client-to-Supabase mutation surfaces were further guarded.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 2 can continue into session-detail layout/cockpit work with a source-verifiable inventory and centralized lock foundation. Human visual UAT remains skipped/deferred per explicit user instruction.

## Self-Check: PASSED

- FOUND: `src/views/SessionDetailView.vue`
- FOUND: `src/locales/messages.ts`
- FOUND: `.planning/phases/02-session-detail-task-cockpit/02-PRESERVATION-INVENTORY.md`
- FOUND: `.planning/phases/02-session-detail-task-cockpit/02-session-detail-task-cockpit-01-SUMMARY.md`
- FOUND commits: `d3bea5e`, `5ea4dd3`, `8034485`

---
*Phase: 02-session-detail-task-cockpit*
*Completed: 2026-05-25T11:21:16Z*
