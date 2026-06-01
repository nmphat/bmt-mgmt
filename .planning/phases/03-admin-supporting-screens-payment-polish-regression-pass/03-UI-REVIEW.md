# Phase 03 — UI Review

**Audited:** 2026-05-27  
**Baseline:** Phase 3 `03-UI-SPEC.md`  
**Screenshots:** Prior `browser_harness` retest artifacts are available in session storage; the fresh auditor did not capture new screenshots.

---

## Pillar Scores

| Pillar | Score | Key Finding |
|---|---:|---|
| 1. Copywriting | 4/4 | Phase 3 CTA, error, empty, QR, and manual cash copy now match the contract with VI/EN parity. |
| 2. Visuals | 3/4 | Core card/dialog hierarchy is strong; a few icon/compact controls still need accessible labels or 44px treatment. |
| 3. Color | 3/4 | Color system is mostly consistent; indigo accent is broad but generally within allowed action/focus/navigation roles. |
| 4. Typography | 2/4 | Remaining type-scale drift: global Tailwind text tokens redefine `text-base` to 18px and code still contains extra sizes/weights outside changed Phase 3 surfaces. |
| 5. Spacing | 4/4 | Safe-area remediation is resolved and the manual payment footer style has been moved to top-level scoped CSS. |
| 6. Experience Design | 3/4 | Clipboard failure and NaN fixes are resolved; some session-detail fetch/mutation failures still lack user-facing feedback. |

**Overall: 19/24**

---

## Top 3 Priority Fixes

1. **Fix typography token drift** — `src/assets/main.css` redefines Tailwind text sizes, making `text-base` 18px instead of the spec's 16px body size. Restore spec-aligned tokens or replace Phase 3 UI with explicit `[16px]`, `[20px]`, and `[32px]` classes only.
2. **Add user-facing error feedback in `SessionDetailView.vue`** — `fetchData` currently logs failed detail loads without toast/visible error state, and presence-update errors also console-log only.
3. **Close remaining accessibility/tap-target gaps** — add `aria-label` and `min-h-11/min-w-11` where missing, such as the member-detail back icon button, the session edit close button, and the member-detail Pay All CTA.

---

## Detailed Findings

### Pillar 1: Copywriting (4/4)

Resolved items verified:

- Sessions CTA uses contract copy via `dashboard.newSession` in `DashboardView.vue`; locale values are present in VI and EN.
- Sessions empty/load error copy matches spec and is rendered by `DashboardView.vue`.
- Create-session fallback error copy is implemented in `CreateSessionView.vue` with locale values.
- Manual cash CTA/review copy exists in both locales as `payment.confirmCash` and is rendered by `ManualPaymentModal.vue`.
- Clipboard failure copy exists in both locales and is used by `PaymentQRModal.vue`.

Generic `Save`/`Cancel` matches are localized common actions, not hardcoded English UI drift.

### Pillar 2: Visuals (3/4)

Strengths:

- Sessions cards have clear title/status/date/count/details hierarchy in `DashboardView.vue`.
- Payment sheet focal order matches spec: amount, QR, transfer content, breakdown, status/actions in `PaymentQRModal.vue`.
- Member cards preserve identity/status/actions in `MemberView.vue`.

Remaining issues:

- `MemberDetailView.vue` has an icon-only back button without an `aria-label`.
- `SessionDetailView.vue` edit-mode close button lacks an accessible label and 44px treatment.
- `MemberDetailView.vue` Pay All CTA does not use `min-h-11`.

### Pillar 3: Color (3/4)

Evidence:

- No hardcoded hex/rgb colors found in audited source/CSS.
- Semantic colors are mostly correct: blue/open, orange or yellow/waiting, green/paid/done, red/destructive/debt, gray/neutral.
- Indigo is used for primary actions, navigation, selected states, links, and focus rings.

Minor concern: indigo is used heavily across navigation, status-adjacent chips, payment amounts, and controls. Most uses are permitted by the spec, but future decorative/non-action elements should stay neutral to preserve the 60/30/10 balance.

### Pillar 4: Typography (2/4)

Source evidence:

- Changed Phase 3 surfaces were previously normalized to remove prohibited `text-xs`, `text-lg`, `text-xl`, `text-2xl`, `text-3xl`, `font-medium`, `font-semibold`, and `font-extrabold`.
- Repo-wide source still contains those classes in legacy/other-phase surfaces, including `LoginView.vue`, `AppHeader.vue`, `HomePage.vue`, `HomeDebtTable.vue`, and `BottomNav.vue`.
- `src/assets/main.css` redefines Tailwind sizes:
  - `text-sm` = 16px
  - `text-base` = 18px
  - `text-xl` = 24px

Contract gap:

- Phase 3 spec allows body 16px, label/meta 14px, heading 20px, display 32px, and weights 400/700 only.
- Phase 3 files still use `text-base` heavily for buttons/inputs, so the rendered size is likely 18px unless replaced with explicit `text-[16px]` or the global token override is corrected.

### Pillar 5: Spacing (4/4)

Resolved:

- Safe-area `calc()` build warning is remediated by moving calculations to CSS helper classes instead of arbitrary Tailwind calc classes.
- `pnpm build` passes with no CSS minify warning after remediation.
- Payment sheets keep `max-h-[88dvh]`.
- Core mobile controls generally use `min-h-11`.
- The manual payment footer style was moved to a top-level `<style scoped>` block in `16608b0`.

### Pillar 6: Experience Design (3/4)

Resolved prior findings:

- Clipboard failure is handled in `PaymentQRModal.vue`.
- NaN session-detail display is fixed through session-summary normalization.
- Manual cash remains caller-admin-gated from `SessionDetailView.vue`.
- Payment polling cleanup remains intact.

Remaining gaps:

- Session-detail fetch errors are logged but not surfaced as a toast or visible error state.
- Some mutation failures only console-log, including presence toggle errors.
- No `components.json`; registry audit skipped. UI-SPEC lists no approved third-party registries.

---

## Verification Notes

- `pnpm type-check`: PASS after the style cleanup.
- `pnpm build`: PASS after the style cleanup with no CSS minify warning.
- Prior `browser_harness` remediation pass: PASS 8/8 affected route+viewport checks for `/sessions`, `/members`, first `/member/:id`, and first `/session/:id` at 390x844 and 1280x900; no global overflow, no `NaN`, no runtime exception text.
- Retest screenshots are session artifacts only:
  - `/home/phatngo/.copilot/session-state/07dceea9-e423-4717-900e-03af338018ed/files/browser-harness-20260527-ui-review-fixes`

---

## Files Audited

- `.planning/phases/03-admin-supporting-screens-payment-polish-regression-pass/03-UI-SPEC.md`
- `.planning/phases/03-admin-supporting-screens-payment-polish-regression-pass/03-CONTEXT.md`
- `.planning/phases/03-admin-supporting-screens-payment-polish-regression-pass/03-VERIFICATION.md`
- `.planning/phases/03-admin-supporting-screens-payment-polish-regression-pass/03-PRESERVATION-INVENTORY.md`
- `.planning/phases/03-admin-supporting-screens-payment-polish-regression-pass/03-REGRESSION-SOURCE-CHECKS.md`
- Phase 03 plans/summaries `03-01` through `03-05`
- `src/App.vue`
- `src/assets/main.css`
- `src/router/index.ts`
- `src/locales/messages.ts`
- `src/views/DashboardView.vue`
- `src/views/CreateSessionView.vue`
- `src/views/MemberView.vue`
- `src/views/MemberDetailView.vue`
- `src/views/SessionDetailView.vue`
- `src/components/AppHeader.vue`
- `src/components/BottomNav.vue`
- `src/components/HomeDebtTable.vue`
- `src/components/PaymentQRModal.vue`
- `src/components/ManualPaymentModal.vue`

---

## UI REVIEW COMPLETE

**Phase:** 03 — admin-supporting-screens-payment-polish-regression-pass  
**Overall Score:** 19/24  
**Output Path:** `.planning/phases/03-admin-supporting-screens-payment-polish-regression-pass/03-UI-REVIEW.md`

| Pillar | Score |
|---|---:|
| Copywriting | 4/4 |
| Visuals | 3/4 |
| Color | 3/4 |
| Typography | 2/4 |
| Spacing | 4/4 |
| Experience Design | 3/4 |

### Top Fixes

1. Align typography tokens/classes with the Phase 3 14/16/20/32px contract.
2. Add user-facing `SessionDetailView` fetch/mutation error states.
3. Fix remaining icon-only/compact controls.
