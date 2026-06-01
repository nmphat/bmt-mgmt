---
phase: 01-mobile-shell-debt-payment-foundation
plan: 01
subsystem: mobile-shell-debt-payment-foundation
tags: [preservation, routing, access-control, i18n, members]
dependency_graph:
  requires: []
  provides:
    - Phase 1 preservation matrix for route/component/Supabase contracts
    - Public read-only member navigation with admin-only CRUD gates
    - Vietnamese and English shell/debt/payment locale keys
  affects:
    - src/views/MemberView.vue
    - src/locales/messages.ts
    - .planning/phases/01-mobile-shell-debt-payment-foundation/01-PRESERVATION-MATRIX.md
tech_stack:
  added: []
  patterns:
    - Vue route/component access preservation
    - Pinia authStore.isAdmin mutation gating
    - messages.ts VI/EN locale key parity
key_files:
  created:
    - .planning/phases/01-mobile-shell-debt-payment-foundation/01-PRESERVATION-MATRIX.md
  modified:
    - src/views/MemberView.vue
    - src/locales/messages.ts
decisions:
  - Preserve public read-only access for debt, members, member detail, sessions, and session detail routes.
  - Keep member/session mutations admin-only through component gates and existing backend authority.
  - Add locale keys without adding guest-facing login copy to the public shell.
metrics:
  duration_seconds: 104
  completed_at: 2026-05-25T10:32:50Z
  tasks_completed: 3
---

# Phase 1 Plan 01: Preservation matrix, route access, and i18n foundation Summary

Preservation foundation established for Phase 1 with route/access contracts, admin-only member mutations, and VI/EN locale keys for shell, debt, and payment labels.

## Completed Tasks

| Task | Name | Commit | Files |
|---|---|---|---|
| 1 | Create Phase 1 preservation matrix before refactor | `6e5817c` | `.planning/phases/01-mobile-shell-debt-payment-foundation/01-PRESERVATION-MATRIX.md` |
| 2 | Enforce public read-only routes and admin-only mutations | `907f251` | `src/views/MemberView.vue` |
| 3 | Add complete VI/EN locale foundation for Phase 1 UI | `39c6f7d` | `src/locales/messages.ts` |

## What Changed

- Added the Phase 1 preservation matrix covering `/`, `/members`, `/member/:id`, `/sessions`, `/session/:id`, `/login`, and `/create-session`.
- Documented shared route/header/bottom-nav expectations for `src/router/index.ts`, future `BottomNav.vue`, and `AppHeader.vue`.
- Recorded locked decisions D-01 through D-05 and D-16 through D-19, including no schema/migration changes.
- Changed member add/edit/delete controls and handlers from authenticated-user gates to `authStore.isAdmin`.
- Added a guest-visible Details link from each member row to `/member/:id`.
- Added required Vietnamese and English keys for Phase 1 shell, debt, QR, group QR, and cash-review labels.

## Verification

- `grep -E "/members|/member/:id|/sessions|/create-session|view_member_debt_summary|create_group_payment|BottomNav|AppHeader|route guard|D-16|D-17|D-18|D-19" .planning/phases/01-mobile-shell-debt-payment-foundation/01-PRESERVATION-MATRIX.md`
- `pnpm type-check`
- `grep -n "isAuthenticated\|isAdmin\|/create-session\|path: '/sessions'\|path: '/members'\|path: '/member/:id'\|path: '/session/:id'" src/views/MemberView.vue src/views/DashboardView.vue src/router/index.ts`
- `pnpm build`

All verification commands passed.

## Deviations from Plan

None - plan executed as written.

## Auth Gates

None.

## Known Stubs

None. Stub scan only matched existing/intentional i18n placeholder keys (for input placeholder copy), not hardcoded mock data or unimplemented UI.

## Deferred Issues

None.

## Self-Check: PASSED

- Found `.planning/phases/01-mobile-shell-debt-payment-foundation/01-PRESERVATION-MATRIX.md`
- Found `src/views/MemberView.vue`
- Found `src/locales/messages.ts`
- Found commit `6e5817c`
- Found commit `907f251`
- Found commit `39c6f7d`
