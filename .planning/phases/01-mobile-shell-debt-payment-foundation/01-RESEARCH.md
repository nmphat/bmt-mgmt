# Phase 1: Mobile Shell + Debt/Payment Foundation - Research

**Researched:** 2026-05-21  
**Domain:** Vue 3 mobile shell, guest debt discovery, QR payment preservation, route/access/i18n guardrails  
**Confidence:** HIGH

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Mobile shell and navigation

- **D-01:** Mobile bottom navigation has exactly three public tabs: Home/Debt, Members, and Sessions.
- **D-02:** `/sessions` is public read-only. Admin-only actions on that screen, including Create Session, remain gated by `authStore.isAdmin`; `/create-session` remains admin-only.
- **D-03:** Login is a hidden admin feature. The UI must not show a guest login button. Admins open `/login` manually; after login, profile/logout/admin actions become visible.
- **D-04:** The mobile header holds secondary actions. The language switcher is a compact top-right header control, always visible for guest and admin. Admin actions/profile/logout also live in the compact header/menu, not in an Admin bottom-nav tab.
- **D-05:** Members is public read-only for guests. Guests can open the member list and member detail to view sessions attended and payment status. Admins, after login, can add/edit/delete members.

#### Debt discovery and selection

- **D-06:** Home debt uses member-name search and keeps sorting by total debt. Do not add overdue, high-debt, or partial-payment filter chips unless the current backend exposes reliable fields for them.
- **D-07:** On mobile debt cards, tapping the card body toggles selection. Only an explicit Details link/button navigates to member detail, so a missed checkbox tap does not accidentally navigate away.
- **D-08:** Home debt cards show name, total debt, unpaid session count, selected state, QR action, and Details link. Do not show per-session rows on the home card.
- **D-09:** Group payment uses clear selected state plus a sticky group payment bar positioned above the bottom nav. Do not implement prototype long-press selection in v1.
- **D-10:** Loading uses skeleton/card placeholders. Empty debt state clearly communicates debt-free/clean state. Keep the current load-more button behavior; do not switch to infinite scroll or pull-to-refresh in Phase 1.
- **D-11:** Do not change current cash-payment logic during Phase 1. Guests/members see QR payment actions only. Admin cash is visible only where the current snapshot context safely supports it, and never for guests.

#### QR and cash payment sheets

- **D-12:** On mobile, QR/cash payment UI is a bottom sheet capped around `88dvh`, with inner content scrolling and sticky/safe-area-aware footer actions. On desktop, keep a dialog presentation.
- **D-13:** QR sheet content order is: amount first, QR image, transfer content with copy action, member/group breakdown, then status note/actions.
- **D-14:** Payment polling runs only while the sheet is open. When payment is detected, show a success state, emit a refresh, and let the user close with Done/Close instead of auto-closing.
- **D-15:** Admin cash payment requires double confirmation. After entering amount/note, show a second confirmation step in the same sheet with member/session, amount, remaining debt, and note before calling `add_manual_payment`.

#### Feature-preservation guardrails

- **D-16:** Before implementation, create a preservation matrix for touched screens containing route, component, role/access behavior, Supabase contract, and payment entry points.
- **D-17:** Route/access verification must cover guest access to `/`, `/members`, `/member/:id`, `/sessions`, and `/session/:id`; only admin can create/edit/delete/finalize/cash/admin actions.
- **D-18:** Every new label has Vietnamese and English locale keys. Changed mobile screens must be visually swept at 360px, 390px, and 430px to confirm bottom nav, sticky group bar, sheets, and toasts do not cover primary content/actions.
- **D-19:** Phase 1 validation requires type-check/build plus manual guest/admin sweeps for debt, members, sessions list, QR/group QR, hidden login, and admin actions.

### the agent's Discretion

- Exact component names, extraction boundaries, icon choices, skeleton styling, spacing values, and Tailwind class composition are left to the planner/implementer, provided the decisions above and existing codebase conventions are preserved.
- The planner may decide whether shared UI primitives live in `src/components/` directly or a subfolder, as long as the implementation stays consistent and avoids duplicating one-off card/sheet patterns.

### Deferred Ideas (OUT OF SCOPE)

- Overdue/high-debt/partial-payment filter chips are deferred until backend fields reliably support them.
- Long-press debt selection from the prototype is deferred; v1 uses explicit tap/select behavior.
- Aggregate cash payment directly from a member's home debt card is not part of Phase 1 unless a backend-safe snapshot allocation contract exists; do not implement frontend allocation.
- Guest "I transferred" confirmation remains out of scope for this milestone.

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SHELL-01 | Mobile bottom navigation preserves route access and role-appropriate destinations | Current router exposes `/`, `/sessions`, `/member/:id`, `/login`, `/session/:id`, `/create-session`, `/members`; only `/create-session` has `requiresAuth` + `requiresAdmin`. [VERIFIED: `src/router/index.ts`] |
| SHELL-02 | Shared mobile-first primitives | Prototype and context define cards, status chips, bottom sheets, floating bars, loading/empty states. [VERIFIED: `mobile-prototypes/styles.css`, `01-CONTEXT.md`] |
| SHELL-03 | 360-430px usability | Phase validation requires 360/390/430px visual sweeps; prototype uses safe-area bottom nav, bulk bar, and `88dvh` sheet cap. [VERIFIED: `01-CONTEXT.md`, `mobile-prototypes/styles.css`] |
| SHELL-04 | VI/EN labels | Existing i18n lives in `src/locales/messages.ts` and `src/stores/lang.ts`; every new label must be added in both locales. [VERIFIED: codebase] |
| SHELL-05 | Route/access/no-regression checklist | Phase context requires preservation matrix before implementation. [VERIFIED: `01-CONTEXT.md`] |
| DEBT-01 | Guest debt home from `view_member_debt_summary` | `HomePage.vue` fetches `view_member_debt_summary` without auth guard. [VERIFIED: `src/views/HomePage.vue`, `src/router/index.ts`] |
| DEBT-02 | Debt card fields, loading, empty, load-more | `HomeDebtTable.vue` already renders name, total debt, unpaid count, QR action, selected state, empty/loading, and load more. [VERIFIED: `src/components/HomeDebtTable.vue`] |
| DEBT-03 | Member debt details from `view_member_session_details` | `MemberDetailView.vue` queries `view_member_session_details` by member id. [VERIFIED: `src/views/MemberDetailView.vue`] |
| DEBT-04 | Single member/session QR without recalculation | `PaymentQRModal.vue` uses snapshot/group amounts; `MemberDetailView.vue` constructs snapshot-like data from backend view values. [VERIFIED: codebase] |
| DEBT-05 | Group QR through `create_group_payment` | `HomePage.vue` and `MemberDetailView.vue` call `create_group_payment`. [VERIFIED: codebase] |
| DEBT-06 | QR amount/content/copy/breakdown/completion | `PaymentQRModal.vue` has amount, QR URL, transfer code copy, group breakdown, polling, success state. [VERIFIED: `src/components/PaymentQRModal.vue`] |
| ADMIN-04 | Login/logout/profile/auth debt/header actions | `AppHeader.vue` handles language, authenticated debt badge, profile, admin link, logout; `/login` remains route-addressable. [VERIFIED: `src/components/AppHeader.vue`, `src/router/index.ts`] |

</phase_requirements>

## Summary

Phase 1 is a preservation-first mobile UI refactor, not a backend or payment-semantics rewrite. [VERIFIED: `.planning/ROADMAP.md`, `.planning/PROJECT.md`] The planner should decompose work around four tracks: shell/header/bottom navigation, debt home cards/selection/search/load-more, QR payment sheet preservation, and route/access/i18n/regression verification. [VERIFIED: `01-CONTEXT.md`, codebase]

The highest planning risks are QR amount/content drift, route/access drift, guest debt accidentally requiring login, group payment bar/bottom nav overlap, and missing VI/EN keys. [VERIFIED: `.planning/ROADMAP.md`, `01-CONTEXT.md`] Implementation should reuse current Vue/Supabase contracts and components rather than replacing flows wholesale. [VERIFIED: `HomePage.vue`, `HomeDebtTable.vue`, `PaymentQRModal.vue`, `MemberDetailView.vue`]

**Primary recommendation:** Plan Phase 1 as a UI decomposition and guardrail phase: first create preservation matrix + shared primitives, then refactor shell, debt list, QR sheet, and i18n/access validation in small reviewable steps. [VERIFIED: `01-CONTEXT.md`]

## Project Constraints

- No `copilot-instructions.md` exists in the project root. [VERIFIED: shell check]
- No `.github/skills/` or `.agents/skills/` skill files were found. [VERIFIED: shell check]
- GEMINI guidance says business logic resides in Postgres RPC functions and the frontend must not replicate it. [VERIFIED: `GEMINI.md`]
- Use Vue 3 `<script setup>`, TypeScript strict, Vite, Pinia, Vue Router, TailwindCSS, Supabase JS, lucide-vue-next/Heroicons. [VERIFIED: `GEMINI.md`, `package.json`]
- Use toast notifications for API errors. [VERIFIED: `GEMINI.md`, codebase imports `vue-toastification`]
- Date/currency formatting must remain Vietnamese-friendly, especially VND currency. [VERIFIED: `docs/summary.md`, `GEMINI.md`]

## Standard Stack

### Core

| Library | Project Version | npm Latest Checked | Purpose | Plan Guidance |
|---------|-----------------|--------------------|---------|---------------|
| Vue | `^3.5.27` | `3.5.34`, modified 2026-05-15 | SPA UI framework | Keep; use existing `<script setup lang="ts">`. [VERIFIED: `package.json`, npm registry] |
| Vue Router | `^5.0.1` | `5.0.7`, modified 2026-05-13 | Routes/guards | Keep current route paths and guard semantics. [VERIFIED: `src/router/index.ts`, npm registry] |
| Pinia | `^3.0.4` | `3.0.4`, modified 2025-11-05 | Auth/language stores | Keep auth/lang stores; do not add new global state layer. [VERIFIED: `src/stores/auth.ts`, `src/stores/lang.ts`, npm registry] |
| Supabase JS | `^2.95.2` | `2.106.1`, modified 2026-05-20 | DB/auth/RPC/realtime client | Preserve table/view/RPC names and parameters. [VERIFIED: codebase, npm registry] |
| TailwindCSS + `@tailwindcss/vite` | `^4.1.18` | `4.3.0`, modified 2026-05-20 | Utility styling | Use existing Tailwind/Vite integration; do not introduce UI framework. [VERIFIED: `vite.config.ts`, npm registry] |

### Supporting

| Library | Project Version | npm Latest Checked | Purpose | When to Use |
|---------|-----------------|--------------------|---------|-------------|
| lucide-vue-next | `^0.563.0` | `1.0.0`, modified 2026-05-15 | Icons | Use for shell/debt/payment icons; avoid new icon library. [VERIFIED: imports in codebase, npm registry] |
| date-fns | `^4.1.0` | `4.2.1`, modified 2026-05-18 | Date formatting | Keep for session/member date display. [VERIFIED: codebase, npm registry] |
| vue-toastification | `2.0.0-rc.5` | npm `latest` reports `1.7.14`, modified 2022-05-23 | Toasts | Preserve existing toast use; do not migrate in Phase 1. [VERIFIED: `package.json`, npm registry] |
| vue-tsc | `^3.2.4` | `3.3.1`, modified 2026-05-19 | Type-check | Use `pnpm type-check` as validation. [VERIFIED: `package.json`, npm registry] |

**Installation:** No new runtime packages are recommended for Phase 1. [VERIFIED: `package.json`, `.planning/research/SUMMARY.md`]

## Architecture Patterns

### Recommended Project Structure

```text
src/
├── components/
│   ├── AppHeader.vue              # compact secondary actions/header
│   ├── BottomNav.vue              # new public Home/Members/Sessions mobile nav
│   ├── PaymentQRModal.vue         # refactor into mobile sheet + desktop dialog
│   ├── ManualPaymentModal.vue     # preserve admin cash RPC; double confirm if touched
│   └── ui/                        # optional shared primitives if planner chooses
├── views/
│   ├── HomePage.vue               # debt data ownership + QR creation
│   ├── MemberDetailView.vue       # member debt history + session QR
│   ├── DashboardView.vue          # public sessions list with admin create action
│   └── MemberView.vue             # public read-only list; admin mutation controls
├── router/index.ts                # route/access source of truth
├── stores/auth.ts                 # auth/admin/profile state
├── stores/lang.ts                 # current locale + t()
└── locales/messages.ts            # VI/EN keys
```

### Pattern 1: Shell Layout Boundary

**What:** `App.vue` should compose `AppHeader`, route outlet, and mobile bottom nav/safe-area spacing. [VERIFIED: `src/App.vue`, `01-CONTEXT.md`]  
**When to use:** For all changed mobile screens so bottom nav and sticky bars have predictable layering. [VERIFIED: `mobile-prototypes/styles.css`]  
**Planning note:** Reserve bottom spacing in page containers when fixed bottom nav or group bar is visible. [VERIFIED: prototype `.wrap`, `.bottomnav`, `.bulkbar` CSS]

### Pattern 2: Contract-Preserving Debt Data

**What:** Home debt stays sourced from `view_member_debt_summary`; member detail stays sourced from `view_member_session_details`; group payment stays through `create_group_payment`. [VERIFIED: codebase, `.planning/ROADMAP.md`]  
**When to use:** Every debt/payment plan task must name which existing contract it preserves. [VERIFIED: `01-CONTEXT.md`]  
**Planning note:** `HomePage.vue` currently fetches unpaid snapshots to build snapshot ids, then calls `create_group_payment`; this is the sensitive boundary to regression-test. [VERIFIED: `src/views/HomePage.vue`]

### Pattern 3: Mobile Sheet, Desktop Dialog

**What:** QR/cash payment UI should be bottom sheet on mobile, capped around `88dvh`, with scrollable content and sticky/safe-area-aware footer; desktop remains dialog. [VERIFIED: `01-CONTEXT.md`, `mobile-prototypes/styles.css`]  
**When to use:** Refactor `PaymentQRModal.vue` first; only touch `ManualPaymentModal.vue` if required by Phase 1/admin preservation scope. [VERIFIED: `01-CONTEXT.md`]  
**Planning note:** Payment polling must start only when open and stop on close/unmount. Current `PaymentQRModal.vue` already has `watch(show)` and `onUnmounted(stopPolling)`. [VERIFIED: `src/components/PaymentQRModal.vue`]

### Anti-Patterns to Avoid

- **Replacing Supabase payment contracts with frontend math:** violates backend boundary and risks incorrect shared cost/payment amounts. [VERIFIED: `docs/summary.md`, `.planning/ROADMAP.md`]
- **Adding prototype filter chips:** deferred because backend fields are not approved for overdue/high/partial filters. [VERIFIED: `01-CONTEXT.md`]
- **Putting Admin in bottom nav:** locked decision says bottom nav has exactly Home/Debt, Members, Sessions. [VERIFIED: `01-CONTEXT.md`]
- **Making card body navigate:** locked decision says card body toggles selection; Details link navigates. [VERIFIED: `01-CONTEXT.md`]
- **Auto-closing QR on payment:** locked decision says show success and let user close. [VERIFIED: `01-CONTEXT.md`]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Debt calculation | Frontend debt allocator | `view_member_debt_summary`, `view_member_session_details`, `session_costs_snapshot` | Existing backend owns debt/snapshot amounts. [VERIFIED: codebase/docs] |
| Group payment totals | Custom grouped amount calculator | `create_group_payment` RPC result | RPC returns `group_code` and `total_amount`. [VERIFIED: `HomePage.vue`, `MemberDetailView.vue`] |
| Manual cash semantics | New client-side payment state | `add_manual_payment` RPC | Existing modal already calls RPC. [VERIFIED: `ManualPaymentModal.vue`] |
| Global i18n system | New i18n library | Existing `messages.ts` + `lang.ts` | Existing app already uses computed `t`. [VERIFIED: `src/stores/lang.ts`] |
| Route authorization | Per-component route blocking only | `router/index.ts` route meta + component role gates | Route guard owns protected route access; components must still hide admin actions. [VERIFIED: `src/router/index.ts`, codebase] |
| Toast system | Custom floating notifications | `vue-toastification` | Existing app already uses it. [VERIFIED: codebase imports] |

## Runtime State Inventory

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | Supabase stores members, sessions, snapshots, payments; Phase 1 does not rename data keys or migrate values. [VERIFIED: `docs/api.yaml`, codebase] | No data migration; preserve view/RPC contracts. |
| Live service config | Supabase URL/API config exists in app integration, but no Phase 1 runtime config change is required. [VERIFIED: codebase references] | None for Phase 1 unless manual env validation fails. |
| OS-registered state | No OS-level registrations are involved in this SPA UI refactor. [VERIFIED: project files/context] | None. |
| Secrets/env vars | Supabase credentials are external env/config concern; Phase 1 should not add or rename env vars. [ASSUMED] | Verify local `.env` manually before running live Supabase flows. |
| Build artifacts | `dist/` and `node_modules/` exist; UI refactor changes source only. [VERIFIED: directory snapshot] | Run clean build/type-check; no artifact migration. |

## Common Pitfalls

### Pitfall 1: Route/access drift

**What goes wrong:** Guests lose `/`, `/members`, `/member/:id`, `/sessions`, or `/session/:id`, or admin-only actions leak. [VERIFIED: `.planning/ROADMAP.md`]  
**How to avoid:** Plan a preservation matrix before code changes and a manual route sweep after. [VERIFIED: `01-CONTEXT.md`]  
**Warning signs:** New route meta added casually, `authStore.isAuthenticated` used where `isAdmin` is required, hidden login button reappears. [VERIFIED: codebase]

### Pitfall 2: QR amount/content regression

**What goes wrong:** QR amount, QR addInfo, copied transfer code, or group breakdown no longer matches backend payment contract. [VERIFIED: `.planning/ROADMAP.md`]  
**How to avoid:** Keep `PaymentQRModal.vue` amount and code derived from `snapshot` or `groupData`, not UI totals. [VERIFIED: `PaymentQRModal.vue`]  
**Warning signs:** Planner tasks mention recalculating debt totals beyond display summaries. [VERIFIED: docs boundary]

### Pitfall 3: Fixed bars cover primary actions

**What goes wrong:** Bottom nav, bulk group bar, toast, or sheet footer covers QR/payment actions at 360-430px. [VERIFIED: `01-CONTEXT.md`]  
**How to avoid:** Plan explicit viewport checks at 360, 390, 430px and bottom padding for nav + group bar states. [VERIFIED: `mobile-prototypes/styles.css`]  
**Warning signs:** Group bar uses `bottom:0` while bottom nav is also fixed. Current `HomeDebtTable.vue` has a fixed bottom group bar that needs refactor. [VERIFIED: `HomeDebtTable.vue`]

### Pitfall 4: Missing locale keys

**What goes wrong:** New labels render raw keys or only one language. [VERIFIED: `src/stores/lang.ts`, `src/locales/messages.ts`]  
**How to avoid:** Every new label task must include VI and EN message keys. [VERIFIED: `01-CONTEXT.md`]  
**Warning signs:** Literal Vietnamese/English strings inside templates instead of `t(...)`. [VERIFIED: current i18n pattern]

### Pitfall 5: Polling leaks or premature close

**What goes wrong:** Payment polling continues after close/navigation, or sheet closes before user sees success. [VERIFIED: `PaymentQRModal.vue`, `01-CONTEXT.md`]  
**How to avoid:** Preserve `watch(show)` + `onUnmounted(stopPolling)` behavior and success state. [VERIFIED: `PaymentQRModal.vue`]  
**Warning signs:** `setInterval` appears without cleanup or payment completion immediately emits close. [VERIFIED: codebase]

## Code Examples

### Current public route pattern

```ts
// Source: src/router/index.ts [VERIFIED: codebase]
{
  path: '/sessions',
  name: 'dashboard',
  component: () => import('../views/DashboardView.vue'),
}

{
  path: '/create-session',
  name: 'create-session',
  component: () => import('../views/CreateSessionView.vue'),
  meta: { requiresAuth: true, requiresAdmin: true },
}
```

### Existing admin action gate pattern

```vue
<!-- Source: src/views/DashboardView.vue [VERIFIED: codebase] -->
<router-link
  v-if="authStore.isAdmin"
  to="/create-session"
>
  {{ t('dashboard.newSession') }}
</router-link>
```

### Existing payment polling cleanup pattern

```ts
// Source: src/components/PaymentQRModal.vue [VERIFIED: codebase]
watch(
  () => props.show,
  (newShow) => {
    if (newShow && !props.isPaid) startPolling()
    else stopPolling()
  },
)

onUnmounted(() => {
  stopPolling()
})
```

## State of the Art

| Old Approach | Current Phase Approach | Impact |
|--------------|------------------------|--------|
| Desktop-first header/nav | Compact header + 3-tab mobile bottom nav | Better one-handed guest navigation. [VERIFIED: Open Design prototype/context] |
| Modal panel on mobile | Bottom sheet capped around `88dvh` | Prevents hidden payment/cash content. [VERIFIED: `01-CONTEXT.md`, prototype CSS] |
| Card expansion for details | Card body selects; explicit Details navigates | Reduces accidental navigation during group payment selection. [VERIFIED: `01-CONTEXT.md`] |
| Infinite/gesture-heavy prototype ideas | Keep load-more and tap selection | Lower risk; preserves current behavior. [VERIFIED: `01-CONTEXT.md`] |

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Node.js | Vite/type-check/build | yes | v22.22.0 | Meets package `engines` range. [VERIFIED: shell, `package.json`] |
| pnpm | Install/build scripts | yes | 8.15.9 | npm possible but project lockfile is pnpm. [VERIFIED: shell, `pnpm-lock.yaml`] |
| npm | Registry/version checks | yes | 11.12.0 | pnpm for project commands. [VERIFIED: shell] |
| git | Commit/inspection | yes | 2.43.0 | — [VERIFIED: shell] |

**Environment warning:** npm commands emitted `NODE_TLS_REJECT_UNAUTHORIZED=0` warnings, meaning the shell environment disables TLS certificate verification for Node processes. [VERIFIED: npm command output] This should be fixed outside the phase if live package installation or secure remote calls are required. [ASSUMED]

## Validation Architecture

Skipped because `.planning/config.json` has `"workflow": { "nyquist_validation": false }`. [VERIFIED: `.planning/config.json`]

Manual validation is still required by phase context: type-check/build plus guest/admin sweeps for debt, members, sessions list, QR/group QR, hidden login, and admin actions. [VERIFIED: `01-CONTEXT.md`]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | yes | Supabase auth via existing `authStore.initialize()` / `signOut()`. [VERIFIED: `src/stores/auth.ts`] |
| V3 Session Management | yes | Supabase auth session; preserve route guard behavior. [VERIFIED: `src/router/index.ts`, `src/stores/auth.ts`] |
| V4 Access Control | yes | Route meta for protected routes + `authStore.isAdmin` component gates for admin actions. [VERIFIED: codebase] |
| V5 Input Validation | limited | Do not add new payment inputs for guests; existing manual cash amount validates `> 0`. [VERIFIED: `ManualPaymentModal.vue`] |
| V6 Cryptography | no direct implementation | Do not hand-roll crypto; no crypto work in Phase 1. [ASSUMED] |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Admin action leakage to guests | Elevation of privilege | Use `authStore.isAdmin` for Create Session/admin/cash actions; verify guest sweeps. [VERIFIED: `DashboardView.vue`, `01-CONTEXT.md`] |
| Payment tampering via client-side totals | Tampering | Use backend views/RPCs/snapshots for amounts; do not compute authoritative debt in UI. [VERIFIED: docs/codebase] |
| Stale payment status | Repudiation/Integrity | Poll only while sheet open and refresh data on completion. [VERIFIED: `PaymentQRModal.vue`] |
| Accidental hidden login exposure | Information disclosure/product access drift | No guest login button; `/login` remains manually addressable. [VERIFIED: `01-CONTEXT.md`, `AppHeader.vue`] |

## Recommended Plan Decomposition

1. **Wave 0: Preservation matrix and shell inventory**  
   Map each touched route/component to guest/admin access, Supabase contract, payment entry points, i18n keys, and mobile overlap risks. [VERIFIED: `01-CONTEXT.md`]

2. **Wave 1: App shell/header/bottom nav**  
   Refactor `App.vue`/`AppHeader.vue`, add bottom nav, keep language always visible, keep guest login hidden, preserve profile/logout/auth debt badge after login. [VERIFIED: codebase/context]

3. **Wave 2: Debt home UI foundation**  
   Refactor `HomeDebtTable.vue` cards: search, skeletons, empty state, load more, tap-to-select, Details link, QR action, sticky group bar above nav. [VERIFIED: `HomeDebtTable.vue`, context]

4. **Wave 3: QR payment sheet preservation**  
   Refactor `PaymentQRModal.vue` into responsive sheet/dialog while preserving amount, QR URL, copy code, group breakdown, polling cleanup, success state. [VERIFIED: `PaymentQRModal.vue`, context]

5. **Wave 4: Member debt entry points + i18n/access sweep**  
   Polish `MemberDetailView.vue` enough for single-session/pay-all QR consistency; add all locale keys; verify routes and admin gates. [VERIFIED: `MemberDetailView.vue`, `messages.ts`]

## Open Questions

1. **Should MemberView mutations use `isAdmin` instead of `isAuthenticated`?**
   - What we know: Phase decision says admins can add/edit/delete members. [VERIFIED: `01-CONTEXT.md`]
   - Current code gates member CRUD with `authStore.isAuthenticated`, not `isAdmin`. [VERIFIED: `MemberView.vue`]
   - Recommendation: Planner should include an explicit access-control task to align UI gates to `isAdmin` unless user confirms authenticated non-admin members may manage members.

2. **Should `ManualPaymentModal.vue` be completed in Phase 1 or deferred to Phase 3?**
   - What we know: Phase context includes cash sheet decisions and double confirmation, but Phase 3 owns ADMIN-05 payment modal polish. [VERIFIED: `01-CONTEXT.md`, `.planning/REQUIREMENTS.md`]
   - Recommendation: In Phase 1, only change manual cash if touched by shared sheet primitive or admin preservation; otherwise record as Phase 3 follow-up.

3. **Can automated tests be added despite nyquist disabled?**
   - What we know: No test framework is configured and nyquist validation is disabled. [VERIFIED: shell check, `.planning/config.json`]
   - Recommendation: Plan manual validation plus `pnpm type-check` and `pnpm build`; optional Vitest setup should not block Phase 1.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Supabase env vars should not be added/renamed in Phase 1. | Runtime State Inventory | Low; if env config is actually changing, planner must add env validation. |
| A2 | Node TLS warning should be fixed outside Phase 1 unless installs are needed. | Environment Availability | Medium; insecure TLS env could affect package/install security. |
| A3 | No direct cryptography controls are needed in Phase 1. | Security Domain | Low; payment QR uses existing URL/code flow, not crypto. |

## Sources

### Primary (HIGH confidence)

- `.planning/phases/01-mobile-shell-debt-payment-foundation/01-CONTEXT.md` — locked Phase 1 decisions, scope, deferred ideas.
- `.planning/REQUIREMENTS.md` — requirement IDs and milestone scope.
- `.planning/ROADMAP.md` — Phase 1 goal, success criteria, validation notes, no-regression guardrails.
- `.planning/PROJECT.md` — milestone constraints and validated capabilities.
- `docs/summary.md` — Vue/Supabase architecture and backend-boundary rules.
- `docs/api.yaml` — Supabase/PostgREST table/RPC reference present in exported API doc.
- `mobile-prototypes/index.html`, `mobile-prototypes/screens/home.html`, `mobile-prototypes/styles.css` — directional Open Design patterns.
- `src/router/index.ts`, `src/App.vue`, `src/components/AppHeader.vue`, `src/views/HomePage.vue`, `src/components/HomeDebtTable.vue`, `src/components/PaymentQRModal.vue`, `src/components/ManualPaymentModal.vue`, `src/views/MemberDetailView.vue`, `src/views/MemberView.vue`, `src/stores/auth.ts`, `src/stores/lang.ts`, `src/locales/messages.ts` — current implementation source of truth.

### Secondary (MEDIUM confidence)

- npm registry `npm view` results for package latest versions and modified timestamps. Commands emitted TLS warning in this environment.

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH for project stack, MEDIUM for npm latest due TLS warning.
- Architecture: HIGH because based on current code and locked phase context.
- Pitfalls: HIGH because derived from roadmap stop-ship criteria and current code hotspots.
- Security: MEDIUM because ASVS mapping is codebase-derived and not from a formal security review.

**Research date:** 2026-05-21  
**Valid until:** 2026-06-20 for codebase constraints; 2026-05-28 for npm latest-version data.
