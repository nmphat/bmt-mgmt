---
phase: 01
reviewers: [hermes, gemini]
failed_reviewers: [claude]
reviewed_at: 2026-05-21T16:46:47+07:00
plans_reviewed:
  - 01-01-PLAN.md
  - 01-02-PLAN.md
  - 01-03-PLAN.md
  - 01-04-PLAN.md
  - 01-05-PLAN.md
---

# Cross-AI Plan Review - Phase 01

## Hermes Review

# Review: Phase 1 plan set

## Summary
The plan set is strong and mostly coherent. It correctly treats this milestone as a preservation-first UI refactor, with clear guardrails around route access, Supabase contracts, i18n, and mobile ergonomics. The main risk is execution complexity across many coupled files: the plans are detailed, but several steps still overlap in a way that could cause churn, regressions, or hidden dependency failures.

## Strengths
- Clear phase boundary: UI refactor only, no backend logic rewrite.
- Good preservation strategy: matrix, route/access checks, and validation gate are explicit.
- Strong mobile-first decisions: bottom nav, safe-area padding, sheet cap, tap targets.
- Good contract preservation: QR/payment flows stay backend-owned.
- Hidden-login requirement is handled consistently.
- Clear separation of guest vs admin behavior.
- Validation includes both automated checks and human sweeps at target widths.

## Concerns
- **HIGH**: Plan 01 and Plan 02 both touch access rules and header/navigation behavior. This creates ordering and merge-risk if route guards, visible actions, and locale keys are changed in different passes.
- **HIGH**: `MemberView.vue` is not in Plan 01's file list, but the task text requires changes there. That mismatch can cause incomplete implementation or review confusion.
- **HIGH**: `HomePage.vue` payment-complete behavior, `PaymentQRModal.vue` refresh semantics, and `MemberDetailView.vue` refresh semantics are split across Plans 03 and 04. These are tightly coupled and easy to break if event contracts drift.
- **MEDIUM**: The validation plan depends on source inspection for many behaviors, but some checks are human-only. That is fine, but the acceptance criteria may be hard to prove consistently without a written checklist template.
- **MEDIUM**: The mobile shell plan says logout should redirect to `/`, but this is a behavior change that may affect current deep-link return behavior. Needs explicit confirmation that it does not conflict with auth flow expectations.
- **MEDIUM**: `BottomNav.vue` and `AppHeader.vue` can easily duplicate navigation logic or route-awareness logic. Without a shared helper, divergence is likely.
- **LOW**: Locale key expansion is broad and could introduce unused keys or duplication unless enforced by a simple key map.
- **LOW**: The plan does not explicitly call out accessibility verification beyond tap size and roles. Focus states, keyboard paths, and aria labels should be checked.

## Suggestions
- Make Plan 01 explicitly include `src/views/MemberView.vue` in `files_modified`, or remove the MemberView mutation requirement from that plan.
- Add a small shared access/navigation spec table so `BottomNav`, `AppHeader`, and route guards all use the same source of truth.
- In Plan 03 and Plan 04, define exact event contracts for `payment-complete`, `close`, and modal state ownership to avoid double-closing or stale selection.
- Add an explicit checklist item for keyboard/focus and aria labels on bottom nav, sheets, search, and details links.
- Require a single "preservation matrix complete" gate before any file edits in later phases.
- Add a brief note that logout redirect to `/` must preserve any auth cleanup and not trigger extra fetch loops.
- In validation, include a small route/access table with guest/admin expectations for each route, not only pass/fail prose.

## Risk Assessment
**Overall risk: MEDIUM-HIGH**

Reason: the scope is well-defined, but the phase has many interdependent UI surfaces and stateful payment flows. The biggest risks are access-control drift, payment modal event regressions, and mobile overlap bugs at small widths. The plan is good, but success depends on disciplined sequencing and exact contract preservation.

---

## Gemini Review

This review covers the implementation plans for **Phase 1: Mobile Shell + Debt/Payment Foundation** (Plans 01-05).

### Summary
The plans provide a rigorous, preservation-first roadmap for refactoring the Badminton Session Manager UI. By prioritizing a preservation matrix and i18n foundation in Wave 1, the strategy ensures that the subsequent visual refactor of the shell (Wave 2), debt experience (Wave 2), and payment sheets (Wave 3) remains anchored to existing Supabase contracts and access rules. The inclusion of multi-resolution visual sweeps and role-based validation in Wave 4 demonstrates a high commitment to mobile ergonomics and security integrity.

### Strengths
* **Preservation-First Methodology:** Starting with a preservation matrix (Plan 01) is an excellent guardrail against route drift and accidental loss of Supabase API contracts during the UI refactor.
* **Access Control Alignment:** Plan 01 proactively corrects the `MemberView.vue` CRUD gates from `isAuthenticated` to `isAdmin`, aligning the codebase with the stricter security requirements of the milestone.
* **Mobile Ergonomic Precision:** The plans specifically address safe-area insets, 44px tap targets, and vertical stacking (Group Bar above Bottom Nav) which are critical for one-handed mobile use.
* **UX Integrity:** Plan 04 correctly implements the "no auto-close on success" requirement for QR payments, ensuring users have clear confirmation before the UI refreshes.
* **Robust Validation:** Plan 05's requirement for 360px, 390px, and 430px sweeps ensures the complex layering of fixed bars, sheets, and toasts is verified across standard mobile viewports.

### Concerns
* **Toast Overlap (MEDIUM):** While Plan 05 verifies that toasts do not cover actions, the current configuration of `vue-toastification` usually defaults to the bottom. With a Bottom Nav **and** a Sticky Group Bar, the default toast position will likely obscure primary navigation or the payment CTA.
* **Z-Index Layering (LOW):** With the Bottom Nav (`z-40` in Plan 02), Sticky Group Bar, Bottom Sheets, and Toasts, there is a risk of "z-index soup" if not managed centrally.
* **Pagination vs. Selection (LOW):** Plan 03 preserves the "Load More" button. If a user selects members on page 1, clicks "Load More", and selects members on page 2, the plan must ensure the selection state is maintained across the fetched array. (Note: Existing `HomeDebtTable.vue` logic likely handles this, but it's worth a manual check during implementation).

### Suggestions
* **Toast Re-positioning:** In Plan 02 or 04, consider adjusting the `vue-toastification` global container position to `top-center` or adding a bottom offset in `App.vue` to clear the 96px+ bottom navigation area.
* **Dynamic Bottom Padding:** In `App.vue` (Plan 02), instead of a static `pb-24`, use a reactive class or CSS variable that increases the bottom padding when the Sticky Group Bar is active, preventing the last item in the debt list from being permanently obscured by the bar.
* **Locale Key Centralization:** Ensure that the `messages.ts` foundation in Plan 01 includes a `common` or `actions` section for shared labels like "Done", "Close", or "Loading" to avoid duplication across feature-specific keys.

### Risk Assessment: LOW
The overall risk is low because the plans strictly adhere to the "no business logic rewrite" constraint and utilize existing Supabase RPCs. The dependency chain is logical, and the validation wave (Plan 05) is exhaustive enough to catch UI regressions before they reach production. The most sensitive area--QR amount derivation--is protected by explicit instructions to use backend-owned snapshot data.

---

## Claude Review

Claude review failed:

```text
error: unknown option '--no-input'
```

---

## Consensus Summary

Both successful reviewers approve the preservation-first structure and agree the plans are directionally strong. Hermes rates risk higher because of cross-file coupling and stateful payment interactions; Gemini rates risk lower because the dependency chain and validation wave are explicit. The actionable review output is to tighten execution details around fixed mobile layers, payment event contracts, accessibility/focus checks, and validation evidence.

### Agreed Strengths

- Preservation-first sequencing is strong: Plan 01's matrix and route/access guardrails reduce the chance of dropping existing features.
- Supabase/Postgres business logic boundaries are respected; QR and debt amounts remain backend-owned.
- Mobile ergonomics are well represented through safe-area padding, bottom-nav placement, sheet height caps, and 360/390/430px sweeps.
- Guest/admin access separation and hidden-login behavior are covered explicitly.
- Final validation combines automated checks with targeted human sweeps.

### Agreed Concerns

- Fixed mobile layers need extra care: bottom nav, group bar, sheets, and toasts can overlap or create unclear z-index ordering.
- Payment modal event/state contracts are sensitive: `payment-complete`, `close`, polling cleanup, and stale selection behavior should be explicit during execution.
- Validation should leave concrete evidence, not just broad pass/fail prose, especially for route/access and mobile-width sweeps.

### Divergent Views

- Hermes flagged Plan 01 missing `MemberView.vue` in `files_modified`, but the current plan already lists `src/views/MemberView.vue`; no plan change is needed for that specific concern.
- Hermes considers the plan set medium-high risk due to coupling; Gemini considers it low risk because the plans keep backend contracts intact and include a strong validation wave.

### Incorporation Recommendation

Before executing Phase 1, either replan with `/gsd-plan-phase 1 --reviews` or manually fold these targeted improvements into the existing plans:

1. Add explicit toast/z-index validation or implementation guidance.
2. Add exact `payment-complete` and `close` event ownership notes to Plans 03-04.
3. Add accessibility/focus/aria checks to Plan 05.
4. Expand Plan 05's validation report template to include route/access and viewport sweep tables.
