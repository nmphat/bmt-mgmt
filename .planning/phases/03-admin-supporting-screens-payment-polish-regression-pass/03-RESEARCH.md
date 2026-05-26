# Phase 03: admin-supporting-screens-payment-polish-regression-pass - Research

**Researched:** 2026-05-26  
**Domain:** Vue 3 mobile-first UI refactor, Supabase contract preservation, payment modal regression validation  
**Confidence:** HIGH

<user_constraints>

## User Constraints

### Sessions list and create-session flow

- **D-01:** `/sessions` remains public read-only. Guests and members can view session cards and navigate to `/session/:id`; only admins see create/mutation affordances.
- **D-02:** Sessions list mobile cards must preserve title, status, date, interval count, registration count, and detail navigation. Desktop/tablet may keep or lightly polish the current grid/card layout.
- **D-03:** `/create-session` remains guarded by `requiresAuth` and `requiresAdmin`. The form must keep current validation, toast behavior, loading state, date/time/fee fields, and `create_session_with_intervals` RPC payload.
- **D-04:** Create-session polish should improve mobile form density, labels, safe spacing, and submit affordance without inventing new recurrence, court, fee-splitting, or default-member behavior.

### Members list and member detail support

- **D-05:** `/members` remains public read-only for viewing members and navigating to member detail. Add/edit/delete controls and handlers remain admin-only through `authStore.isAdmin`.
- **D-06:** Members mobile cards must preserve display name, role, active state, permanent state, Details navigation, and admin edit/delete actions. Desktop table information must remain available.
- **D-07:** Member add/edit/delete semantics remain unchanged: `members.insert`, `members.update`, `members.delete`, role field, active/permanent fields, create-another behavior, loading state, toast feedback, and delete confirmation.
- **D-08:** Member detail must preserve debt summary, session history, interval time display, final amount, court fee, shuttle fee, paid/remaining/status fields, single QR, group/pay-all QR, and `view_member_session_details`/`create_group_payment` behavior.

### Payment modal polish

- **D-09:** `PaymentQRModal.vue` remains the single QR/group QR sheet for home, member detail, and session detail. It must preserve QR URL generation, transfer content copy, group breakdown, polling, payment-complete event, explicit close/Done dismissal, and cleanup on close/unmount.
- **D-10:** `ManualPaymentModal.vue` remains the admin manual cash sheet. It must preserve two-step entry/review confirmation and `add_manual_payment`; non-admin access remains prevented by callers.
- **D-11:** Payment sheets use the Phase 1/2 mobile contract: bottom sheet on mobile, dialog on desktop, `max-h-[88dvh]`, internal scroll, sticky safe-area footer, labelled dialog semantics, accessible close controls, QR alt text, and 44px controls.
- **D-12:** Do not add guest "I transferred" confirmation, auto-close-on-paid, frontend payment allocation, aggregate cash splitting, or new payment status authority.

### Final regression and no-regression guardrails

- **D-13:** Final validation must cover all public routes: `/`, `/members`, `/member/:id`, `/sessions`, `/session/:id`, `/login`, and guarded `/create-session`.
- **D-14:** Final validation must re-check Supabase preservation for all milestone contracts, especially `create_session_with_intervals`, member CRUD, `view_member_debt_summary`, `view_member_session_details`, `view_session_summary`, `calculate_session_costs`, `finalize_session`, `add_member_to_session_full_presence`, `create_group_payment`, `add_manual_payment`, `session_costs_snapshot`, `session_registrations`, `interval_presence`, and `sessions.update(...)`.
- **D-15:** Table-to-card conversions must not omit financial, status, or action fields. Desktop tables/grids should remain available where already used; mobile cards are additive unless the plan proves equivalent preservation.
- **D-16:** Human visual UAT remains skipped/deferred per the user's autonomous execution instruction. Use automated/source/build evidence, route/access checks, contract checks, locale parity checks, and fixed-layer source evidence unless a real blocker appears.

### Copy, accessibility, and visual rules

- **D-17:** All new labels must be added to both Vietnamese and English in `src/locales/messages.ts`.
- **D-18:** Use the established app visual language: neutral gray shell, white cards, rounded borders, indigo primary actions, semantic blue/orange/green/red/gray statuses, visible focus rings, and no new UI framework.
- **D-19:** Changed mobile screens must keep 44px tap targets and safe-area-aware spacing so bottom nav, floating bars, toasts, and sheets do not cover primary actions at 360-430px.
- **D-20:** Open Design/local prototypes are directional for hierarchy, cards, status chips, and sheet density only. The current Vue/Supabase behavior remains authoritative.

### Deferred Ideas

- No backend schema, RLS, RPC, or view changes.
- No new payment method, guest transfer confirmation, aggregate cash allocation, or offline mode.
- No realtime health dashboard beyond existing manual refresh/polling evidence.
- No new desktop redesign beyond preservation-safe polish.

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ADMIN-01 | User can view sessions list read-only, see session cards with status/date/interval/registration counts, and navigate to session detail while create/mutation actions remain admin-only. | `DashboardView.vue` already fetches `view_session_summary`, shows title/status/date/intervals/registrations/details, and gates Create Session with `authStore.isAdmin`. |
| ADMIN-02 | Admin can create a session with title, date, start/end time, court fee, shuttle fee through `create_session_with_intervals`, with validation and feedback preserved. | `CreateSessionView.vue` already validates start/end time, uses loading state/toasts, and calls `create_session_with_intervals` with required payload keys. |
| ADMIN-03 | User can view member list on mobile, and authorized users can add/edit/delete members with display name, role, active, permanent, and create-another preserved. | `MemberView.vue` already uses `members.insert/update/delete`, preserves role/active/permanent/create-another, and guards handlers with `authStore.isAdmin`. |
| ADMIN-05 | User can use QR and manual payment modals as responsive mobile sheets or desktop dialogs without losing semantics, close actions, QR alt text, polling/refresh. | `PaymentQRModal.vue` and `ManualPaymentModal.vue` already have `role="dialog"`, `aria-modal`, `max-h-[88dvh]`, internal scroll, sticky safe-area footer, 44px controls, polling cleanup, and explicit close. |
| ADMIN-06 | User can view table-to-card mobile layouts without losing financial fields, status fields, or actions. | `MemberDetailView.vue` already has additive mobile cards plus desktop table and preserves final amount, court fee, shuttle fee, paid/remaining/status/action fields. |

</phase_requirements>

## Summary

Phase 3 should be planned as a preservation-first UI polish and final regression pass, not a feature expansion. The current implementation already contains most required behavior: session cards, guarded create-session form, member CRUD, member-detail mobile cards, and responsive payment sheets exist in source.

The safest plan is additive and source-verifiable: polish mobile density, card structure, labels, safe-area spacing, and accessibility without moving Supabase authority or changing routes.

**Primary recommendation:** split Phase 3 into high-risk-preservation waves: inventory/regression scaffolding -> sessions/create-session polish -> members/mobile CRUD cards -> payment sheet polish -> final no-regression source/build validation.

## Project Constraints

- No project-root `copilot-instructions.md` was found by the researcher.
- No `.github/skills/` or `.agents/skills/` project skill directories were found by the researcher.
- Existing untracked Open Design/local prototype artifacts and modified `.planning/config.json` are present and should remain untouched unless explicitly needed.
- `workflow.nyquist_validation` is explicitly `false`, so formal Nyquist validation is skipped. Phase 3 still needs automated/source/build validation because the phase contract requires final regression evidence.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Vue | installed 3.5.34 | SPA component framework | Existing app uses Vue 3 `<script setup>` and Composition API. |
| TypeScript | installed 5.9.3 | static typing | Existing app uses strict TypeScript and `vue-tsc --build`. |
| Vite | installed 7.3.3 | build tooling | Existing app uses Vite with Vue and Tailwind plugins. |
| Tailwind CSS | installed 4.3.0 | utility styling | Existing UI uses Tailwind v4 utilities and `@tailwindcss/vite`. |
| Supabase JS | installed 2.106.1 | PostgREST/RPC/auth client | Existing data access uses `supabase.from(...)` and `supabase.rpc(...)`. |
| Vue Router | installed 5.0.7 | SPA routing/access guards | Route/access source of truth is `src/router/index.ts`. |
| Pinia | installed/latest 3.0.4 | auth/language state stores | Existing app imports auth/lang stores across shell and views. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| lucide-vue-next | installed 0.563.0 | icons | Use existing icon dependency only; do not add another icon library. |
| date-fns | installed 4.3.0 | date formatting/locales | Use existing session/member date display patterns. |
| vue-toastification | installed 2.0.0-rc.5 | toast feedback | Preserve existing toast behavior; do not migrate toast libraries in Phase 3. |
| vue-tsc | installed 3.3.1 | Vue type-checking | Use `pnpm type-check` and `pnpm build` for final regression. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Local Vue/Tailwind primitives | shadcn/Radix/Base UI/third-party registry | Forbidden by Phase 3 UI-SPEC; adding them increases regression risk. |
| Existing `PaymentQRModal.vue` | New QR modal per entry point | Forbidden because one shared QR/group QR surface must remain. |
| Existing Supabase RPC/view values | Frontend recalculation/allocation | Forbidden because backend owns financial/payment authority. |

**Installation:** no package installation is recommended for Phase 3.

## Current Behavior Inventory

### `DashboardView.vue`

- Fetches sessions from `view_session_summary`, ordered by `session_date` descending.
- Renders cards with title, status chip, formatted date, interval count, registration count, and Details action linking to `/session/:id`.
- Shows Create Session CTA only when `authStore.isAdmin` is true.
- Current gap: load errors are logged to console but not surfaced via localized toast/error state.

### `CreateSessionView.vue`

- Form fields are title, date, start time, end time, court fee, and shuttle fee.
- End-time validation compares computed start/end strings before RPC call.
- Calls `create_session_with_intervals` with `p_title`, `p_start_time`, `p_end_time`, `p_court_fee`, `p_shuttle_fee`, and `p_created_by`.
- Uses loading disabled state and success/error toasts.
- Route guard requires both auth and admin.

### `MemberView.vue`

- Fetches `members`, orders by `display_name`, then locale-sorts in client.
- Add member uses `members.insert([newMember]).select()` and preserves display name, role, active, permanent, create-another behavior, loading, and toast feedback.
- Edit member uses `members.update(updates).eq('id', id)` and preserves display name, role, active, permanent, updated_at.
- Delete member uses browser confirmation with member name and `members.delete().eq('id', id)`.
- Visibility and handlers are guarded with `authStore.isAdmin`.
- Current gap: mobile still relies on an overflow table instead of additive mobile cards.

### `MemberDetailView.vue`

- Fetches debt summary from `view_member_debt_summary` and falls back to `members.display_name` if no debt row exists.
- Fetches session history from `view_member_session_details`.
- Fetches attended interval times via `interval_presence` joined to `session_intervals`, then merges time intervals.
- Mobile cards preserve session title/date, status, interval time, final amount, court fee, shuttle fee, paid amount, remaining amount, and QR action.
- Desktop table remains available at `md:block`.
- Pay-all uses `create_group_payment`; single pay passes snapshot-like data into `PaymentQRModal`.

### `PaymentQRModal.vue`

- Computes QR URL from `BANK_INFO`, backend/RPC-owned remaining amount, and payment content/group code.
- Supports single snapshot and group payment data.
- Copies transfer content with `navigator.clipboard.writeText`.
- Polls payment status every 5 seconds only while open and stops polling on paid, close, hidden state, and unmount.
- Emits `payment-complete` and does not auto-close when paid.
- Has `role="dialog"`, `aria-modal="true"`, labelled title, QR alt text, `max-h-[88dvh]`, internal scroll, sticky safe-area footer, and 44px controls.

### `ManualPaymentModal.vue`

- Provides two-step `entry` then `review` flow.
- Validates amount > 0 before review/confirm.
- Calls `add_manual_payment` with `p_snapshot_id`, `p_amount`, and `p_note`.
- Emits success and close after RPC success, and close is disabled while submitting.
- Has dialog semantics, `max-h-[88dvh]`, internal scroll, safe-area sticky footer, and 44px controls.
- Non-admin access is caller-side, not modal-owned.

## Architecture Patterns

### Recommended Project Structure

```text
src/
├── views/
│   ├── DashboardView.vue          # sessions list card polish, no contract changes
│   ├── CreateSessionView.vue      # mobile form polish, preserve RPC payload
│   ├── MemberView.vue             # additive mobile cards + preserved desktop table
│   └── MemberDetailView.vue       # verify/polish only unless ADMIN-06 gaps found
├── components/
│   ├── PaymentQRModal.vue         # shared QR/group QR responsive sheet/dialog
│   ├── ManualPaymentModal.vue     # admin cash responsive sheet/dialog
│   ├── BottomNav.vue              # fixed nav baseline; avoid changes unless necessary
│   └── AppHeader.vue              # preserve hidden login behavior
└── locales/messages.ts            # every new label in vi and en
```

### Pattern 1: Additive Mobile Cards

**What:** Add `md:hidden` mobile card layouts while preserving existing desktop table/grid at `hidden md:block` or equivalent.

**When to use:** Use for `MemberView.vue` and any table-to-card work where desktop table information must remain available.

```vue
<div class="md:hidden divide-y divide-gray-100">
  <article class="space-y-4 p-4">
    <!-- mobile-preserved fields/actions -->
  </article>
</div>
<div class="hidden overflow-x-auto md:block">
  <!-- existing desktop table -->
</div>
```

### Pattern 2: Visibility Guard + Handler Guard

**What:** Admin actions need both `v-if="authStore.isAdmin"` and an early return inside mutation handlers.

**When to use:** Use for member add/edit/delete, create session affordances, and manual cash entry points.

```ts
async function deleteMember(id: string, name: string) {
  if (!authStore.isAdmin) return
  if (!confirm(t.value('member.deleteConfirm', { name }))) return
  await supabase.from('members').delete().eq('id', id)
}
```

### Pattern 3: Shared Responsive Payment Surface

**What:** Keep `PaymentQRModal.vue` as the single QR/group QR surface and `ManualPaymentModal.vue` as the cash surface.

**When to use:** Any payment polish must be validated against home, member detail, and session detail callers.

### Anti-Patterns to Avoid

- Replacing shared payment modal per screen.
- Removing desktop tables while adding cards.
- Frontend financial allocation.
- Route meta drift.
- Adding UI frameworks/registries.

## Safe Implementation Seams and Risks

| Surface | Safe Seam | Main Risk | Required Guard |
|---------|-----------|-----------|----------------|
| Sessions list | Card spacing, status chip styling, empty/error copy, 44px Details CTA | Leaking Create Session to guests/non-admins | Keep `v-if="authStore.isAdmin"` and route unchanged. |
| Create session | Form layout, input min-height, submit placement, labels | Changing RPC payload or redirect/feedback behavior | Preserve `create_session_with_intervals` payload and validation. |
| Members list | Add mobile cards while keeping desktop table | Dropping role/active/permanent/details/edit/delete/create-another | Field/action parity checklist per card. |
| Member detail | Verify existing mobile card parity; polish only if needed | Removing financial/status/action fields | Keep mobile card + desktop table parity. |
| Payment QR modal | Text density, footer order, copy button affordance | Timer leaks, auto-close, wrong amount/code | Preserve polling watch/cleanup and explicit close. |
| Manual payment modal | Review copy/layout and footer clarity | Bypassing two-step flow or admin caller gate | Preserve entry/review states and caller admin guards. |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Session creation/interval generation | Client-side interval creation | `create_session_with_intervals` | RPC contract already defines required payload and backend behavior. |
| Debt/payment amount calculation | Frontend fee/debt allocation | `view_member_debt_summary`, `view_member_session_details`, `session_costs_snapshot`, `create_group_payment` | Backend-owned amounts are preservation constraints. |
| Cash payment allocation | Aggregate cash splitting | `add_manual_payment` | Phase explicitly forbids aggregate cash allocation. |
| Route authorization framework | New auth/ACL layer | Existing Vue Router meta + `authStore.isAdmin` guards | Current route/access behavior is locked. |
| UI framework migration | shadcn/Radix/Base UI | Local Vue/Tailwind primitives | Phase 3 UI-SPEC forbids new UI framework/registries. |

**Key insight:** Phase 3 complexity is not new UI construction; it is avoiding contract drift while making remaining screens match the already-approved mobile shell/payment patterns.

## Common Pitfalls

### Pitfall 1: Admin affordance hidden but handler unguarded

**What goes wrong:** Non-admin users may trigger mutations through stale UI, direct devtools invocation, or reused handler paths.

**How to avoid:** Require both `v-if="authStore.isAdmin"` and handler-level `if (!authStore.isAdmin) return`.

### Pitfall 2: Mobile cards omit desktop table fields

**What goes wrong:** ADMIN-06 fails because card conversion drops financial/status/action data.

**How to avoid:** Use a field parity checklist for every table-to-card conversion.

### Pitfall 3: Payment modal timer leaks

**What goes wrong:** Polling continues after close/unmount/navigation or duplicate timers start.

**How to avoid:** Preserve `pollTimer` guard, `stopPolling()` on close/hidden/unmount, and one polling owner.

### Pitfall 4: Safe-area/fixed-layer overlap

**What goes wrong:** bottom nav, sheet footer, toast, or floating payment bar blocks primary actions at 360-430px.

**How to avoid:** Keep page bottom padding, `max-h-[88dvh]`, internal modal scroll, sticky safe-area footers, and toast offset.

### Pitfall 5: Locale drift

**What goes wrong:** new labels exist in only VI or EN.

**How to avoid:** Require locale parity source check for every new key.

## Recommended Plan Breakdown

1. **P01 - Phase 3 inventory + regression source-check scaffold.** Establish exact source grep/checklist commands before UI edits; verify route meta, contract names, current admin guards, locale keys, payment modal invariants.
2. **P02 - Sessions list + create-session mobile polish.** Polish `DashboardView.vue` cards/error/empty/CTA density and `CreateSessionView.vue` mobile form/tap targets while preserving `view_session_summary`, route access, and `create_session_with_intervals` payload.
3. **P03 - Members list mobile cards + CRUD preservation.** Add mobile card layout to `MemberView.vue`; keep desktop table; preserve add/edit/delete/create-another and admin handler guards.
4. **P04 - Payment modal polish across all entry points.** Polish `PaymentQRModal.vue` and `ManualPaymentModal.vue`; validate home, member detail, and session detail callers; do not change polling, close, cleanup, or payment semantics.
5. **P05 - Final milestone no-regression pass.** Run type-check/build and source checks for all Phase 1-3 guardrails; document human visual UAT skipped/deferred and preserve untracked Open Design artifacts.

**High-risk ordering:** do payment modal polish after source-check scaffolding and before final validation, because one modal change affects home, member detail, and session detail payment entry points.

## Exact Source Checks for Planner/Executors

```bash
# Route/access preservation
grep -n "path: '/sessions'\|path: '/members'\|path: '/member/:id'\|path: '/session/:id'\|path: '/login'\|path: '/create-session'\|requiresAuth\|requiresAdmin" src/router/index.ts

# Admin visibility + handler guards
grep -R "authStore.isAdmin" -n src/views src/components

# Supabase contract preservation
grep -R "create_session_with_intervals\|from('members')\\.insert\|from('members')\\.update\|from('members')\\.delete\|view_member_debt_summary\|view_member_session_details\|view_session_summary\|calculate_session_costs\|finalize_session\|add_member_to_session_full_presence\|create_group_payment\|add_manual_payment\|session_costs_snapshot\|session_registrations\|interval_presence\|from('sessions').update" -n src

# Payment sheet/fixed-layer/accessibility evidence
grep -R "role=\"dialog\"\|aria-modal=\"true\"\|max-h-\\[88dvh\\]\|env(safe-area-inset-bottom)\|min-h-11\|min-w-11\|payment-complete\|onUnmounted\|stopPolling" -n src/components src/views src/App.vue

# Locale parity starting point
grep -n "dashboard:\|member:\|createSession:\|payment:\|debt:" src/locales/messages.ts

# Build/type-check final gate
pnpm type-check
pnpm build
```

## Code Examples

### Preserve create-session RPC payload

```ts
await supabase.rpc('create_session_with_intervals', {
  p_title: form.value.title,
  p_start_time: new Date(startDateTime.value).toISOString(),
  p_end_time: new Date(endDateTime.value).toISOString(),
  p_court_fee: form.value.courtFee,
  p_shuttle_fee: form.value.shuttleFee,
  p_created_by: authStore.user.id,
})
```

### Preserve payment polling cleanup

```ts
function startPolling() {
  if (!props.show) return
  if (pollTimer.value) return
  if (props.isPaid || isPaymentComplete.value) return
  pollTimer.value = window.setInterval(async () => {
    const isPaid = await checkPaymentStatus()
    if (isPaid) {
      isPaymentComplete.value = true
      stopPolling()
      emit('payment-complete')
    }
  }, 5000)
}

onUnmounted(() => {
  stopPolling()
})
```

## Automated Validation Architecture

Formal Nyquist validation is skipped because `workflow.nyquist_validation` is `false`.

### Test/Validation Framework

| Property | Value |
|----------|-------|
| Automated tests | No test files/configs detected. |
| Type check | `pnpm type-check` runs `vue-tsc --build`. |
| Build | `pnpm build` runs type-check and Vite build. |
| Manual UAT | Skipped/deferred by user instruction. |
| Recommended final gate | Source checks + `pnpm type-check` + `pnpm build`. |

### Requirement to Validation Map

| Req ID | Behavior | Validation Type | Command / Evidence |
|--------|----------|-----------------|--------------------|
| ADMIN-01 | Public `/sessions`, cards, details nav, admin-only create | source + build | Route grep, `DashboardView.vue` grep, `pnpm build`. |
| ADMIN-02 | Guarded create session + validation/RPC/toasts/loading | source + build | Route grep, `CreateSessionView.vue` RPC payload grep, `pnpm build`. |
| ADMIN-03 | Member list + CRUD + admin gates | source + build | `MemberView.vue` CRUD/admin grep, `pnpm build`. |
| ADMIN-05 | QR/manual responsive dialogs + polling/cleanup | source + build | modal fixed-layer/ARIA/polling grep, caller grep, `pnpm build`. |
| ADMIN-06 | Table-to-card field/action preservation | source review + build | parity checklist on `MemberView.vue`/`MemberDetailView.vue`, `pnpm build`. |

### Validation Gaps

- No automated unit/component/E2E test framework is configured.
- Human visual UAT remains intentionally skipped/deferred.
- Final validation should therefore be explicit source-based evidence plus type-check/build, mirroring Phase 1 and Phase 2 verification style.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Node.js | Vite/Vue build | yes | v22.22.0 | none needed |
| npm | npm registry/version checks | yes | 11.12.0 | pnpm for project scripts |
| pnpm | project scripts | yes | 8.15.9 | npm can inspect but planner should use pnpm because lockfile is pnpm |
| git | status/source verification | yes | 2.43.0 | none |
| vue-tsc | type-check | yes via node_modules | project local | `pnpm build` includes type-check |
| Vite | build | yes via node_modules | 7.3.3 | none |
| Supabase runtime | live app/API behavior | not probed | - | source/build validation only per user instruction |

**Missing dependencies with no fallback:** none for source/build validation.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Preserve Supabase auth and Vue Router guards; do not change `/create-session` auth/admin meta. |
| V3 Session Management | yes | Preserve existing auth store behavior; Phase 3 should not alter session handling. |
| V4 Access Control | yes | Preserve `authStore.isAdmin` visibility and handler guards. |
| V5 Input Validation | yes | Preserve end-time validation and manual payment amount > 0 validation. |
| V6 Cryptography | no new crypto | Do not add crypto/payment signing logic in frontend. |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Non-admin mutation via UI path | Elevation of Privilege | Visibility guard plus handler guard with `authStore.isAdmin`. |
| Payment amount tampering in UI | Tampering | Display backend/RPC-owned amounts; do not recalculate or allocate frontend payments. |
| Route access drift | Elevation of Privilege / Information Disclosure | Keep route meta unchanged for public/read-only and guarded admin routes. |
| Timer/resource leak after modal close | Denial of Service / reliability | Preserve polling cleanup on close/hide/unmount. |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Human visual UAT as required gate | Automated/source/build evidence with human UAT skipped/deferred | Phase 1 and Phase 2 verification | Phase 3 should produce source/build evidence rather than requiring manual screenshots. |
| Session-detail table-heavy UI | Task-focused mobile cockpit with additive cards/tabs | Phase 2 | Phase 3 should match this mobile language for supporting/admin screens. |
| Hidden login omitted from shell | `/login` direct-addressable with no guest-facing login affordance | Phase 1 | Phase 3 must not add public login links. |

## Open Questions

1. **Should Phase 3 add a lightweight automated test framework?**  
   Recommendation: Do not add test framework in Phase 3; use source/build validation unless user explicitly requests tests.

2. **Should `MemberDetailView.vue` be modified or only validated?**  
   Recommendation: Treat as validation-only unless final source parity checklist finds a concrete gap.

## Sources

### Primary

- `.planning/phases/03-admin-supporting-screens-payment-polish-regression-pass/03-CONTEXT.md`
- `.planning/phases/03-admin-supporting-screens-payment-polish-regression-pass/03-UI-SPEC.md`
- `.planning/REQUIREMENTS.md`
- `.planning/ROADMAP.md`
- `.planning/STATE.md`
- `src/router/index.ts`
- `src/views/DashboardView.vue`
- `src/views/CreateSessionView.vue`
- `src/views/MemberView.vue`
- `src/views/MemberDetailView.vue`
- `src/components/PaymentQRModal.vue`
- `src/components/ManualPaymentModal.vue`
- `src/App.vue`
- `src/components/BottomNav.vue`
- `src/components/AppHeader.vue`
- `src/locales/messages.ts`
- `docs/api.yaml`
- `docs/summary.md`

### Secondary

- `.planning/phases/01-mobile-shell-debt-payment-foundation/01-VERIFICATION.md`
- `.planning/phases/02-session-detail-task-cockpit/02-VERIFICATION.md`

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH.
- Architecture: HIGH.
- Pitfalls: HIGH.
- Validation: HIGH.

**Research date:** 2026-05-26  
**Valid until:** 2026-06-02 for npm-version currency; project-source findings remain valid until files change.

