# Phase 1 Validation — Mobile Shell + Debt/Payment Foundation

**Plan:** `01-05`  
**Date:** 2026-05-25  
**Scope:** Automated no-regression checks, source/access review, i18n parity, payment contract review, and source-based mobile/accessibility sweep for Phase 1.

> Human visual UAT was explicitly skipped/deferred by user instruction for this execution. The original blocking human verification checkpoint was not sent to the user. Evidence below is limited to automated commands plus source/build/access/mobile-layer checks feasible without interactive UAT.

## Automated Commands

| Command | Result | Evidence |
|---|---:|---|
| `pnpm type-check` | PASS | `vue-tsc --build` exited `0` before and after the admin-gate fix. |
| `pnpm build` | PASS | Vite production build exited `0`; final build transformed 2608 modules and emitted `dist/` assets. |
| Locale parity source check | PASS | `viMissing=[]`, `enMissing=[]` for `src/locales/messages.ts`. |
| Targeted route/access source assertions | PASS | Bottom nav destinations are exactly `['/', '/members', '/sessions']`; no `/login` shell link; `/create-session` has `requiresAuth` + `requiresAdmin`; no remaining session mutation guard pattern using `isAuthenticated`. |
| Payment/Supabase contract grep | PASS | Existing contracts remain referenced: `view_member_debt_summary`, `view_member_session_details`, `session_costs_snapshot`, `create_group_payment`, `add_manual_payment`. |
| Mobile/accessibility source grep | PASS | Safe-area padding, fixed group-bar offset, toast offset, `max-h-[88dvh]`, sticky sheet footers, dialog semantics, focus rings, and 44px targets are present in changed shell/payment/debt files. |

## User-Skipped Human UAT

| Item | Status | Note |
|---|---|---|
| Manual guest/admin sweep | SKIPPED/DEFERRED BY USER | User explicitly requested autonomous execution and no human UAT. |
| Manual 360/390/430 visual overlap confirmation | SKIPPED/DEFERRED BY USER | Replaced with source/build evidence for safe-area offsets, fixed layers, sheet caps, and focus/tap target classes. |
| Manual keyboard traversal | SKIPPED/DEFERRED BY USER | Replaced with source evidence for semantic links/buttons, labels/text, `focus-visible`/`focus:ring`, and dialog attributes. |

## Locked Decisions D-01 through D-19

| Decision | Result | Evidence |
|---|---:|---|
| D-01 bottom nav exactly Home/Debt, Members, Sessions | PASS | `BottomNav.vue` only links to `/`, `/members`, `/sessions`. |
| D-02 `/sessions` public read-only; create/admin mutations admin-only | PASS | `/sessions` route has no auth meta; `DashboardView.vue` create link uses `authStore.isAdmin`; `/create-session` requires auth + admin. |
| D-03 login hidden; `/login` manually addressable | PASS | Shell has no `/login` link/copy for guests; router keeps `/login` route. |
| D-04 header owns language/profile/logout/admin actions | PASS | `AppHeader.vue` always shows language switcher; auth menu/debt badge render only when authenticated. |
| D-05 members public read-only; CRUD admin-only | PASS | `/members` route ungated; add/edit/delete UI and handlers use `authStore.isAdmin`. |
| D-06 debt search member-name-only and total-debt sorting | PASS | `HomePage.vue` filters `display_name` and orders by `total_debt` descending. |
| D-07 mobile debt card body toggles selection; Details navigates | PASS | `HomeDebtTable.vue` card body handles selection; explicit Details router-link owns navigation. |
| D-08 debt cards show required summary fields and no per-session rows | PASS | Cards render name, total debt, unpaid count, selected state, QR action, Details link. |
| D-09 group payment selected state and sticky bar above bottom nav | PASS | Group bar appears when selected, uses `bottom: calc(92px + env(safe-area-inset-bottom))`; bottom nav is at bottom. |
| D-10 skeleton/empty/load-more preserved | PASS | Loading skeleton cards, debt-free empty state, and load-more button remain. |
| D-11 cash payment admin-only; guests QR-only | PASS | `ManualPaymentModal` is opened through `authStore.isAdmin` cash control; QR actions remain public payment actions. |
| D-12 payment/cash sheets responsive with capped height and sticky footer | PASS | QR and manual sheets use `max-h-[88dvh]`, scrollable body, sticky safe-area footer. |
| D-13 QR order amount → QR → transfer/copy → breakdown → status/actions | PASS | `PaymentQRModal.vue` renders amount before QR image, transfer content/copy, optional group breakdown, status note, footer action. |
| D-14 polling cleanup and no auto-close on payment success | PASS | Payment success stops polling and emits refresh; `HomePage.vue` refreshes without closing; close/Done owns reset. |
| D-15 cash double confirmation before `add_manual_payment` | PASS | `ManualPaymentModal.vue` has `entry` → `review`; `add_manual_payment` only runs in `handleConfirm` when `currentStep === 'review'`. |
| D-16 preservation matrix baseline retained | PASS | Validation compared against `01-PRESERVATION-MATRIX.md`. |
| D-17 guest route verification and admin-only mutations | PASS | Source route table below confirms public read-only routes; session-detail admin mutation gate was tightened in commit `f9de930`. |
| D-18 VI/EN locale coverage and mobile width checks | PASS/SOURCE-BASED | Locale key parity passed; viewport checks are source-based because human UAT was user-skipped. |
| D-19 type/build plus guest/admin sweep | PASS WITH DEFERRED HUMAN UAT | Type/build and source guest/admin checks passed; manual sweep deferred by user instruction. |

## Phase 1 Requirements

| Requirement | Result | Evidence |
|---|---:|---|
| SHELL-01 | PASS | Public three-tab shell with route access preserved. |
| SHELL-02 | PASS | Local Vue/Tailwind primitives used for cards, sheets, bars, loading, empty, and error states. |
| SHELL-03 | PASS/SOURCE-BASED | Safe-area padding and fixed-layer offsets present for 360–430px risks; manual visual UAT skipped. |
| SHELL-04 | PASS | VI/EN locale parity passed. |
| SHELL-05 | PASS | This validation artifact records route/access, contracts, and no-regression checks. |
| DEBT-01 | PASS | Home reads `view_member_debt_summary` without route auth. |
| DEBT-02 | PASS | Debt cards show member debt, unpaid session count, loading, empty, and load-more states. |
| DEBT-03 | PASS | Member detail reads `view_member_session_details`. |
| DEBT-04 | PASS | Single QR uses snapshot/member debt data; no frontend fee allocation added. |
| DEBT-05 | PASS | Group QR uses `create_group_payment`. |
| DEBT-06 | PASS | QR amount/content/copy/breakdown/status rendered in shared payment sheet. |
| ADMIN-04 | PASS | Hidden login route, authenticated debt badge, profile/logout menu, and logout-to-home behavior preserved. |

## Route / Access Table

| Route | Expected guest access | Expected admin access | Route guard/meta evidence | Component gate evidence | Observed result | Pass/fail |
|---|---|---|---|---|---|---:|
| `/` | Public debt home and QR payments | Same plus authenticated header actions | No auth meta in `src/router/index.ts` | Home has no admin mutation controls; QR flows use payment contracts | Source check confirms public route and backend-owned debt/payment flow | PASS |
| `/members` | Public read-only list and Details | Add/edit/delete members | No auth meta | Add/edit/delete controls and handlers use `authStore.isAdmin` | Guest sees Details-only source path; admin gets CRUD | PASS |
| `/member/:id` | Public debt history and QR/pay-all | Same plus header actions | No auth meta | Payment actions are QR only; no member CRUD controls | Reads debt summary/detail views and uses QR/group RPC | PASS |
| `/sessions` | Public read-only session cards and Details | Create Session visible | No auth meta | `DashboardView.vue` Create Session link uses `authStore.isAdmin` | Guest route is readable; create is admin-only | PASS |
| `/session/:id` | Public read-only detail and QR where exposed | Admin session mutations, attendance, cash | No auth meta | Edit/cancel/finalize/register/remove/attendance/absent now use `authStore.isAdmin`; cash uses `isAdmin` | Source gate fixed in `f9de930`; public read-only behavior preserved | PASS |
| `/login` | Manually addressable hidden admin route | Sign in and reveal auth menu | No auth meta; route exists | No shell login link in `AppHeader.vue`/`BottomNav.vue` | Direct URL remains; public shell hides login affordance | PASS |
| `/create-session` | Redirect/protected | Admin-only create flow | `meta: { requiresAuth: true, requiresAdmin: true }` | Entry from sessions list is `authStore.isAdmin` | Protected route remains admin-only | PASS |

## Payment Contract Preservation

| Flow | Result | Evidence |
|---|---:|---|
| Home debt summary | PASS | `HomePage.vue` reads `view_member_debt_summary` and sorts by `total_debt`. |
| Member debt detail | PASS | `MemberDetailView.vue` reads `view_member_debt_summary` and `view_member_session_details`. |
| Home/member/session group QR | PASS | Group QR flows call `create_group_payment`; QR sheet consumes returned code/amount. |
| QR amount/content | PASS | `PaymentQRModal.vue` derives QR from `snapshot` or `groupData`; no shared-cost recalculation added. |
| Payment polling cleanup | PASS | `PaymentQRModal.vue` stops interval on paid, close, hide, and unmount. |
| Payment success ownership | PASS | `payment-complete` refreshes data; close/Done owns sheet dismissal and payload reset. |
| Manual cash | PASS | `ManualPaymentModal.vue` calls `add_manual_payment` only after review confirmation. |

## Accessibility / Focus / ARIA Evidence

| Surface | Result | Evidence |
|---|---:|---|
| Bottom nav | PASS | Native links with visible text, `aria-label`, `aria-current`, 44px targets, `focus-visible` outline. |
| QR sheet | PASS | `role="dialog"`, `aria-modal="true"`, labelled title, `aria-live`, QR alt text, 44px close/Done/copy controls. |
| Cash sheet | PASS | `role="dialog"`, `aria-modal="true"`, labelled title, 44px close/back/confirm controls, focus rings. |
| Search | PASS | `label.sr-only` for `#debt-search`, 48px min height, focus ring. |
| Details action | PASS | Explicit visible Details router-link; card body selection does not navigate. |
| Status/success | PASS | Payment success includes icon plus text and `aria-live`, not color alone. |

## Viewport Sweep Table

| Width | Role | Route/surface | Bottom nav clear | Group bar clear | Sheet footer clear | Toast clear | Primary action reachable | Keyboard/focus visible | Pass/fail | Notes |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 360px | guest | `/` debt cards/search/load-more | PASS | PASS | PASS | PASS | PASS | PASS | Source-based: bottom padding `96px`, group bar `92px`, toast `148px`, sheet footer sticky. |
| 360px | guest | QR/group QR sheet | PASS | PASS | PASS | PASS | PASS | PASS | Source-based: `max-h-[88dvh]`, internal scroll, safe-area footer. |
| 360px | admin | `/members`, `/sessions`, `/session/:id` controls | PASS | PASS | PASS | PASS | PASS | PASS | Source-based: admin gates are role-checked; primary buttons are native links/buttons. |
| 390px | guest | `/`, `/members`, `/member/:id`, `/sessions` | PASS | PASS | PASS | PASS | PASS | PASS | Source-based: same fixed-layer offsets; no route auth on public read-only routes. |
| 390px | admin | QR/cash sheets and session/member admin controls | PASS | PASS | PASS | PASS | PASS | PASS | Source-based: cash and QR sheets have sticky footers and 44px controls. |
| 430px | guest | max-width/mobile shell transition | PASS | PASS | PASS | PASS | PASS | PASS | Source-based: bottom nav max-width and md hidden behavior; page content padding reserves nav space. |
| 430px | admin | authenticated header/menu/debt badge/logout | PASS | N/A | N/A | PASS | PASS | PASS | Source-based: language switcher and user menu controls have labels/focus-visible styles. |

## Deviations / Fixes Applied

| Type | Result | Files | Commit |
|---|---|---|---|
| Rule 2 - Missing critical authorization gate | Session detail mutation controls and handlers were tightened from authenticated-only to admin-only to satisfy Phase 1 public-read-only/admin-gate preservation. Payment QR contracts were left unchanged. | `src/views/SessionDetailView.vue` | `f9de930` |

## Remaining Observations

- Manual visual confirmation remains intentionally deferred/skipped by the user; do not treat the lack of human UAT as an implementation blocker for this run.
- No Supabase schema changes, migrations, or duplicated database business logic were added.
- Existing untracked Open Design artifacts and `.planning/config.json` runtime state were not included in this validation evidence or committed.
