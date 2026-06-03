# Badminton Session Manager

## What This Is

Badminton Session Manager is a mobile-friendly Vue/Supabase web app for managing badminton sessions, interval attendance, member debt, and shared payments. It serves guests who need to check and pay debt without logging in, and admins who create sessions, manage members, track attendance, finalize sessions, configure bank settings, and confirm payments.

## Core Value

Members and guests can understand what they owe and pay it quickly, while admins can manage sessions without redoing spreadsheet work.

## Current State

**Shipped version:** v1.0 UI Refactor, archived 2026-06-02
**Archive:** `.planning/milestones/v1.0-ROADMAP.md`
**Audit:** v1.0 passed with 29/29 requirements, 3/3 phase verifications, and 11/11 integration flows.

v1.0 delivered the mobile-first UI refactor around the current Open Design direction while preserving existing Vue/Supabase behavior. The app now has a debt-first public home, role-aware bottom navigation, responsive member/session surfaces, a task-focused session detail cockpit, QR/manual payment modal polish, DB-backed bank settings, and source/build/browser evidence for no-regression coverage.

The implementation remains a UI layer over Supabase. Cost calculation, session creation, payment grouping, payment snapshots, manual cash recording, auth/RLS, and realtime-backed state remain backend-owned through existing tables, views, and RPCs.

## Next Milestone Goals

No active next milestone is defined yet. Start with `/gsd-new-milestone` to gather requirements before editing ROADMAP.md or creating implementation phases.

Good candidate themes for v1.1:

- Safe authenticated admin mutation smoke and a stable dev/test dataset.
- Payment polling consolidation between `check_qr_status` and direct snapshot polling.
- Optional financial-row accessibility hardening with non-color state cues.
- Optional activity/audit history, offline-friendly attendance, or richer debt filters if backend support exists.

## Requirements

### Validated

- ✓ Guests can view debt summaries and member debt details without logging in — v1.0.
- ✓ Guests and members can create QR payment flows for single or grouped unpaid items without frontend fee allocation — v1.0.
- ✓ Authenticated admins can view sessions, create sessions through `create_session_with_bookings`, and open session detail pages — v1.0.
- ✓ Session detail supports interval attendance, adding/removing registered members, absent marking through `interval_presence`, live cost summaries from `calculate_session_costs`, realtime updates, session editing, cancellation, finalization, QR payments, group payments, and manual cash payments — v1.0.
- ✓ Admins can add, edit, and delete members using current member schema fields (`display_name`, `role`, `is_active`) — v1.0.
- ✓ Bank configuration is DB-backed and used by QR generation — v1.0.
- ✓ The app supports Vietnamese and English labels through the language store and `src/locales/messages.ts` — v1.0.
- ✓ Browser-harness smoke, Open Design review, security audit, and milestone audit evidence exist for v1.0 closeout — v1.0.

### Active

- None. Requirements for the next milestone should be created through `/gsd-new-milestone`.

### Out of Scope

- Backend business logic rewrites unless a future milestone explicitly changes the Supabase contract.
- Frontend fee allocation or shared-cost recalculation.
- Native mobile app work.
- Blindly copying Open Design prototype markup or prototype-only JavaScript.
- Removing Vietnamese/English i18n coverage.

## Context

- Tech stack: Vue 3, TypeScript, Vite, Pinia, Vue Router, TailwindCSS, Supabase.
- Business logic boundary: the frontend displays Supabase RPC/view/snapshot results and must not recalculate shared fees.
- Current create-session RPC is `create_session_with_bookings`.
- Current session edit writes `price_per_hour`, `court_fee_addon`, and `shuttle_fee_total`; `court_fee_total` is read-model/view data only.
- Current member CRUD does not use retired `members.is_permanent`.
- Current absent-state behavior uses `interval_presence`; the retired `session_registrations.is_registered_not_attended` field must not be referenced in active source.
- Browser-harness smoke evidence and Open Design review artifacts are stored in session state paths recorded in `.planning/STATE.md` and `.planning/HANDOFF.json`.
- Follow-up PR/MR automation is blocked in this environment by missing GitHub auth; use `.planning/mr-summary-v1-audit-gaps.md` and the compare URL recorded there if manual PR creation is needed.

## Constraints

- **Feature preservation:** No route or current user-visible capability may disappear during UI work.
- **Backend boundary:** The frontend must not recalculate shared costs or replace Postgres RPC business logic.
- **Mobile-first:** Designs should work well at 360-430px widths with 44px+ tap targets and thumb-zone CTAs.
- **Access model:** Guest read/payment flows stay available without login; admin-only create/edit/manage actions stay protected by auth/role checks.
- **Localization:** All new user-facing strings need Vietnamese and English coverage through the existing locale pattern.
- **Type safety:** Preserve strict TypeScript compatibility and avoid widening with `any`.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use Open Design as a reference, not a source of truth | The prototype captures desired mobile direction, but it does not cover every live Vue/Supabase behavior | Good; preserved through v1.0 |
| Keep a 3-phase coarse roadmap for v1.0 | User requested coarse mode and exactly 3 phases | Completed |
| Refactor UI before changing backend contracts | Current backend owns business logic; UI risk was losing flows during redesign | Good; audit later aligned frontend to current contracts |
| Prioritize guest debt/payment path | User identified guest no-login debt payment as the most important use case | Validated in Phase 1 and preserved through v1.0 |
| Hide login UI and make `/sessions` public read-only | Only admins need login; sessions list can be read-only for guests while admin actions remain protected | Good; preserved through v1.0 |
| Skip human visual UAT for v1.0 | User explicitly deferred manual visual/browser UAT; source/build/browser evidence substituted | Accepted risk; documented |
| Treat `interval_presence` as absent source of truth | Backend removed `session_registrations.is_registered_not_attended` | Good; fixed and validated after PR #2 merge |
| Run milestone audit before archival | Cross-phase audit found backend-contract gaps that phase verification had missed | Good; all blockers closed before archive |

## Evolution

This document evolves at milestone boundaries.

After each future milestone:

1. Move shipped active requirements to Validated.
2. Add new Active requirements only after discussion/research.
3. Re-check constraints and out-of-scope assumptions.
4. Update backend contract notes if Supabase schema/RPCs change.
5. Update key decisions with outcomes.

---

*Last updated: 2026-06-02 after v1.0 milestone archive*
