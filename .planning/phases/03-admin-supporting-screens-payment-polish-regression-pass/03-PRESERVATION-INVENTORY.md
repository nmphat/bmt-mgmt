# Phase 3 Preservation Inventory

**Phase:** 03-admin-supporting-screens-payment-polish-regression-pass  
**Plan:** 01  
**Purpose:** Lock route/access, Supabase/backend contracts, payment semantics, locale parity, fixed-layer requirements, and forbidden scope before any Phase 3 UI edits.

## Requirement Mapping

| Requirement | Coverage | Preservation Evidence |
|---|---|---|
| ADMIN-01 | Full | `/sessions` remains public read-only; `DashboardView.vue` reads `view_session_summary`, renders title/status/date/interval count/registration count/detail navigation, and shows create only through `authStore.isAdmin`. |
| ADMIN-02 | Full | `/create-session` remains `requiresAuth` + `requiresAdmin`; `CreateSessionView.vue` preserves title/date/start/end/court fee/shuttle fee validation, loading, toast feedback, and `create_session_with_intervals`. |
| ADMIN-03 | Full | `/members` remains public read-only; `MemberView.vue` preserves member CRUD through `members.insert`, `members.update`, `members.delete`, role/active/permanent/create-another, loading, toast, and admin guards. |
| ADMIN-05 | Full | `PaymentQRModal.vue` and `ManualPaymentModal.vue` preserve dialog semantics, close/Done actions, QR alt text, polling/cleanup, two-step manual cash, `create_group_payment`, and `add_manual_payment`. |
| ADMIN-06 | Full | `MemberDetailView.vue` preserves additive mobile cards plus desktop table for financial fields, status fields, route/payment actions, and history from `view_member_session_details`. |

## Route Access

| Route | Required Access | Full Coverage Evidence |
|---|---|---|
| `/` | Public debt home | Route has no auth/admin meta and continues to use Supabase-backed debt views from Phase 1. |
| `/sessions` | Public read-only per D-01 | `src/router/index.ts` route has no auth/admin meta; `DashboardView.vue` uses `view_session_summary`; mutation/create affordance is admin-only. |
| `/session/:id` | Public read-only unless admin mutations apply | Route has no auth/admin meta; Phase 2 guards mutation handlers and controls with admin/status checks. |
| `/members` | Public read-only per D-05 | Route has no auth/admin meta; `MemberView.vue` lets users view members/details while add/edit/delete controls and handlers use `authStore.isAdmin`. |
| `/member/:id` | Public member detail/debt history | Route has no auth/admin meta; `MemberDetailView.vue` reads debt/session history and supports QR payment entry. |
| `/login` | Direct-addressable hidden login | Route remains available without adding guest-facing login labels or public shell affordances. |
| `/create-session` | Admin-only per D-03 | `src/router/index.ts` keeps `meta: { requiresAuth: true, requiresAdmin: true }`. |

## Supabase Contracts

Frontend Phase 3 work must preserve these backend-owned names, payloads, and semantics:

| Contract | Surface | Full Coverage Rule |
|---|---|---|
| `create_session_with_intervals` | Create session | Preserve RPC and payload keys `p_title`, `p_start_time`, `p_end_time`, `p_court_fee`, `p_shuttle_fee`, `p_created_by`. |
| `members.insert` | Member create | Preserve display name, role, active, permanent, create-another behavior, loading, and toast feedback. |
| `members.update` | Member edit | Preserve display name, role, active, permanent, updated_at, loading, and toast feedback. |
| `members.delete` | Member delete | Preserve named irreversible confirmation and admin-only handler. |
| `view_member_debt_summary` | Debt/member detail | Preserve debt summary as backend-owned source of member debt. |
| `view_member_session_details` | Member detail | Preserve session history, financial fields, status fields, interval display, and QR action data. |
| `view_session_summary` | Sessions/session detail | Preserve sessions list cards and session detail summary source. |
| `calculate_session_costs` | Session detail costs | Preserve live cost summary authority; do not recalculate fees in frontend. |
| `finalize_session` | Session detail finalization | Preserve backend-owned finalization. |
| `add_member_to_session_full_presence` | Session registration | Preserve registration/presence creation authority. |
| `create_group_payment` | Home/member/session group QR | Preserve backend-owned group amount/code/member breakdown. |
| `add_manual_payment` | Admin manual cash | Preserve cash recording RPC and two-step confirmation. |
| `session_costs_snapshot` | Payment snapshots/polling | Preserve finalized payment snapshot authority and polling checks. |
| `session_registrations` | Session detail registrations | Preserve registration state and removal/update behavior. |
| `interval_presence` | Attendance/member interval display | Preserve attendance state and member detail interval-time evidence. |
| `sessions.update` | Session edit/cancel | Preserve existing update calls and admin/status locks. |

## UI Field Parity

| Surface | Fields/Actions That Must Remain | Full Coverage Evidence |
|---|---|---|
| Sessions list cards | Title, status, date, interval count, registration count, details navigation | `DashboardView.vue` renders all fields from `view_session_summary` and links to `/session/:id`. |
| Create session form | Title, date, start time, end time, court fee, shuttle fee, validation, loading, success/error toast | `CreateSessionView.vue` owns form and RPC payload; no recurrence/court/default-member/fee-splitting additions. |
| Members list | Display name, role, active state, permanent state, Details navigation, admin edit/delete | `MemberView.vue` desktop table preserves fields; Phase 3 card polish must be additive or equivalent. |
| Member detail | Debt summary, session history, interval time display, final amount, court fee, shuttle fee, paid, remaining, status, QR action, pay-all/group QR | `MemberDetailView.vue` already has additive mobile cards and desktop table with required financial/status/action fields. |

## Payment Semantics

| Decision Range | Full Coverage Rule |
|---|---|
| D-09 | `PaymentQRModal.vue` remains the single QR/group QR sheet for home, member detail, and session detail; preserve QR URL generation, transfer content copy, group breakdown, polling, `payment-complete`, explicit close/Done, and close/unmount cleanup. |
| D-10 | `ManualPaymentModal.vue` remains the admin cash sheet; preserve entry/review confirmation and `add_manual_payment`; callers prevent non-admin access. |
| D-11 | Payment sheets keep bottom sheet on mobile, desktop dialog, `role="dialog"`, `aria-modal="true"`, labelled title, QR alt text, `max-h-[88dvh]`, internal scroll, sticky safe-area footer, and 44px controls. |
| D-12 | Do not add guest "I transferred" confirmation, auto-close-on-paid, frontend payment allocation, aggregate cash splitting, or new payment status authority. |

## Locale Parity

| Area | Required Rule |
|---|---|
| Sessions | Phase 3 dashboard copy must exist in VI and EN, including load error and card aria/detail copy. |
| Create session | Create error copy must exist in VI and EN. |
| Members | Empty/load/status/action copy must exist in VI and EN. |
| Payments | Existing QR/manual cash copy must stay paired in VI and EN. |
| Forbidden copy | Do not add guest-facing login copy, transfer-confirmation copy, aggregate cash allocation copy, offline-mode copy, or new payment-method copy. |

## Fixed Layers

| Surface | Full Coverage Rule |
|---|---|
| Bottom navigation pages | Preserve page bottom padding so cards/actions are not hidden by fixed nav at 360-430px. |
| Floating/group payment bars | Preserve safe-area-aware offsets above bottom nav where bars appear. |
| Payment sheets | Preserve `max-h-[88dvh]`, internal scroll, sticky footer, and `env(safe-area-inset-bottom)`. |
| Toasts | Preserve source-evident offsets from prior shell work so primary payment/create/member actions remain reachable. |
| Controls | Preserve 44px touch targets through `min-h-11`, `min-w-11`, or equivalent. |

## Deferred/Forbidden Items

These are explicitly excluded from Phase 3:

- No schema, migration, RLS, RPC, or view changes.
- No frontend fee allocation, shared-cost recalculation, aggregate cash splitting, or new payment authority.
- No guest transfer confirmation or guest "I transferred" flow.
- No offline mode or realtime health dashboard expansion.
- No new UI framework, shadcn/Radix/Base UI migration, third-party UI registry, or icon library change.
- No guest-facing login label or public login CTA.
- No new payment methods.

## Decision Coverage Matrix

| Decision | Coverage | Evidence |
|---|---|---|
| D-01 | Full | `/sessions` is public read-only; only admins see create affordance. |
| D-02 | Full | Sessions cards preserve title/status/date/intervals/registrations/details. |
| D-03 | Full | `/create-session` requires `requiresAuth` and `requiresAdmin`. |
| D-04 | Full | Create-session polish scope is density/labels/spacing only; no new recurrence/court/default-member/fee-splitting. |
| D-05 | Full | `/members` is public read-only; member mutations are admin-only. |
| D-06 | Full | Members cards/table must preserve display name/role/active/permanent/details/admin edit/delete. |
| D-07 | Full | Member CRUD remains `members.insert`, `members.update`, `members.delete` with create-another/loading/toasts/confirmation. |
| D-08 | Full | Member detail preserves debt summary/history/financial/status/QR fields and `view_member_session_details`/`create_group_payment`. |
| D-09 | Full | Shared `PaymentQRModal.vue` preserves QR/group QR generation, copy, polling, events, and cleanup. |
| D-10 | Full | `ManualPaymentModal.vue` preserves two-step `add_manual_payment`; caller admin gates remain required. |
| D-11 | Full | Payment sheets preserve dialog ARIA, `max-h-[88dvh]`, internal scroll, safe-area sticky footer, QR alt, and 44px controls. |
| D-12 | Full | Forbidden payment expansions remain excluded. |
| D-13 | Full | Regression source checks cover `/`, `/members`, `/member/:id`, `/sessions`, `/session/:id`, `/login`, `/create-session`. |
| D-14 | Full | Regression source checks cover all listed Supabase contracts. |
| D-15 | Full | Table-to-card work must preserve financial/status/action fields and desktop tables/grids where used. |
| D-16 | Full | Human visual UAT is skipped/deferred; source/build/route/contract/locale/fixed-layer evidence is required. |
| D-17 | Full | All new labels must be added to both VI and EN locale blocks. |
| D-18 | Full | Visual language remains neutral shell, white cards, indigo actions, semantic statuses, visible focus rings, and local Vue/Tailwind primitives. |
| D-19 | Full | Changed mobile screens must keep 44px tap targets and safe-area-aware spacing. |
| D-20 | Full | Open Design/local prototypes remain directional only; current Vue/Supabase source is authoritative. |
