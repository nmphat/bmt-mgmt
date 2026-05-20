# Stack Research — UI Refactor Milestone

**Project:** Badminton Session Manager  
**Scope:** Stack decisions for UI refactor using current Open Design as reference  
**Researched:** 2026-05-20

## Summary

Keep the current Vue/Supabase/Tailwind stack intact. This milestone is a UI refactor with a strict no-regression goal, so new runtime dependencies would add migration risk without solving the core problem. The safest approach is to add local UI primitives, centralize tokens/utilities, and optionally add a minimal dev-only test setup if phase budget allows.

Business logic must remain in Supabase views/RPCs. The frontend should continue displaying `view_member_debt_summary`, `view_member_session_details`, `view_session_summary`, `calculate_session_costs`, `create_session_with_intervals`, `create_group_payment`, `finalize_session`, and `add_manual_payment` results instead of recalculating business rules.

## Current Stack

| Area | Current Tool |
|------|--------------|
| Framework | Vue 3 `^3.5.27` |
| Language | TypeScript `~5.9.3`, strict |
| Build | Vite `^7.3.1` |
| Styling | TailwindCSS v4 via `@tailwindcss/vite` |
| State | Pinia |
| Routing | Vue Router |
| Backend | `@supabase/supabase-js` |
| Icons | `lucide-vue-next` |
| Toasts | `vue-toastification` |
| Dates | `date-fns` |
| Validation commands | `pnpm type-check`, `pnpm build`, `pnpm format` |

## Recommended Stack Decisions

### Keep runtime dependencies unchanged

Do not add a UI framework, form framework, animation library, or data-fetching abstraction. Current Vue + Tailwind + local components are enough for the Open Design direction.

### Use Tailwind v4 CSS-first tokens

Extend `src/assets/main.css` instead of introducing a design-system package. Align the app with `brand-spec.md` and `mobile-prototypes/styles.css`:

- neutral app background
- white surfaces/cards
- indigo primary action color
- status colors for open/waiting/done/paid/due
- compact Vietnamese-friendly type scale
- large tap targets
- safe-area helpers for bottom navs, sheets, floating CTAs, and toasts

### Add local UI primitives

Use app-owned primitives under `src/components/ui/`:

- app shell and bottom navigation
- page headers/cards/buttons/badges/tabs
- bottom sheet/modal foundation
- floating action bar
- loading/empty/error states
- currency/status display helpers

This matches the app’s domain-specific needs better than a third-party component library.

### Extract route-scoped composables

Composables should wrap existing Supabase contracts without changing semantics:

- session detail data loading
- attendance mutations
- session registration
- session payments
- realtime/polling refresh
- debt group payment creation
- payment status polling
- currency formatting

### Keep current i18n pattern

Continue using `src/locales/messages.ts` + `useLangStore`. Every new label must be added in both Vietnamese and English.

### Optional dev-only tests

If time allows, add only dev dependencies for high-risk preservation tests:

```bash
pnpm add -D vitest @vue/test-utils happy-dom
```

Initial tests should cover emitted events and rendering for debt table, payment modal, and session panels. Do not attempt full Supabase integration testing in this UI milestone.

## Avoid / Defer

| Avoid/defer | Reason |
|-------------|--------|
| Headless UI, Radix/Reka, DaisyUI, Flowbite, Vuetify, Quasar, Ionic | Adds conventions and scope while current Tailwind setup can implement needed UI |
| TanStack Query or other data layer migrations | Existing Supabase calls/realtime are already wired and should not be migrated during visual refactor |
| Zod/Valibot/VeeValidate | Useful later, but form-stack migration is not needed for no-regression UI work |
| Playwright/E2E | Valuable later, but needs stable Supabase test data; use manual checklist and optional component tests first |
| Frontend fee allocation logic | Business logic belongs in Supabase RPCs/views |

## Validation Commands

Required after implementation phases:

```bash
pnpm type-check
pnpm build
```

Formatting:

```bash
pnpm format
```

If scripts are added:

```bash
pnpm test:run
pnpm format:check
```

## Risks

- `SessionDetailView.vue` is monolithic; extract logic before redesigning UI.
- Frontend mobile cards may tempt cost recalculation; display RPC/snapshot values only.
- Current global type scale can make dense forms/tables too large; use local density classes.
- Bottom bars need consistent safe-area and z-index rules.
- Realtime + polling are fragile; preserve behavior first, then improve with one refresh owner.
- Adding tests can expand scope; keep tests small and preservation-focused.
