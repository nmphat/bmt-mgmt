# Phase 3 — UI Review

**Audited:** 2026-05-27  
**Baseline:** Phase 3 UI-SPEC.md  
**Screenshots:** `browser_harness` captured mobile smoke screenshots after the initial source audit; Cloak/Playwright/Open Design MCP remained unavailable.

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 4/4 | VI/EN parity is strong and exact CTA labels are now aligned to UI-SPEC. |
| 2. Visuals | 3/4 | Mobile cards/sheets largely match the contract; browser-only visual assertions need human review. |
| 3. Color | 3/4 | Neutral shell + white cards + semantic statuses are present; accent usage is broad but mostly justified. |
| 4. Typography | 4/4 | Changed Phase 3 surfaces are normalized to allowed sizes and weights 400/700. |
| 5. Spacing | 4/4 | 44px targets and safe-area patterns are present; the arbitrary `calc()` build warning is fixed. |
| 6. Experience Design | 4/4 | Loading/error/empty/admin/payment states are covered and clipboard failure is surfaced. |

**Overall: 22/24**

---

## Top 3 Priority Fix Status

1. **Resolved in `38778c0` — Normalize Phase 3 typography to the contract.** Changed Phase 3 surfaces now avoid `text-xs`, `text-lg`, `text-xl`, `text-2xl`, `text-3xl`, `font-medium`, `font-semibold`, and `font-extrabold` and use explicit Heading/Display sizes plus `font-normal`/`font-bold`.
2. **Resolved in `38778c0` — Fix arbitrary safe-area `calc()` spacing syntax.** Warning-producing safe-area arbitrary Tailwind utilities were replaced with CSS helper classes, and Tailwind source scanning is narrowed to `src` so planning Markdown examples do not generate utilities.
3. **Resolved in `38778c0` — Align exact CTA/copy contract labels.** `dashboard.newSession` EN is now `Create Session`; manual cash entry and review both use `payment.confirmCash`.

---

## Detailed Findings

### Pillar 1: Copywriting (3/4)

**Strengths**

- UI-SPEC requires all new labels in VI/EN; `src/locales/messages.ts` includes Phase 3 keys in both locales:
  - `dashboard.loadError`
  - `dashboard.sessionCardAria`
  - `createSession.createError`
  - `member.emptyState`, statuses, edit/delete labels
- Error and empty states use descriptive, user-recoverable copy:
  - `DashboardView.vue`
  - `MemberView.vue`
  - `HomePage.vue`

**Issues**

- **Resolved — exact CTA drift:** UI-SPEC says sessions primary CTA EN should be `Create Session`; `dashboard.newSession` now matches.
  - Affected: `DashboardView.vue`
  - needs_human_review: false
- **Resolved — manual cash entry CTA:** UI-SPEC specifies `Confirm cash`; entry and review steps now use `payment.confirmCash`.
  - needs_human_review: false

---

### Pillar 2: Visuals (3/4)

**Strengths**

- Sessions list focal point is clear: title/status/date/counts/details in `DashboardView.vue`.
- Members list mobile cards preserve identity, role, active/permanent status, details, and admin actions in `MemberView.vue`.
- Payment QR modal content order matches spec: amount → QR → transfer content/copy → breakdown → status/actions in `PaymentQRModal.vue`.
- Session detail uses mobile sticky section nav and card conversions in `SessionDetailView.vue`.

**Issues**

- **Human review required:** `browser_harness` follow-up covered route smoke, mobile screenshots, and global overflow checks, but detailed 360/390/430px overlap, sheet reachability, and visual rhythm still need human review.
  - needs_human_review: true
- **Minor — remaining dense legacy areas:** desktop tables are preserved correctly, but several table-era styles remain visually dense and use smaller headers/medium weights.
  - Affected: `SessionDetailView.vue`, `MemberView.vue`
  - needs_human_review: true

---

### Pillar 3: Color (3/4)

**Evidence**

- Major color utility count includes broad use of:
  - `text-indigo-600`
  - `bg-indigo-600`
  - `ring-indigo-500`
  - `text-gray-500`
  - `text-gray-900`
- No hardcoded hex/rgb colors found in Vue/TS/CSS grep.
- Semantic status colors are present:
  - sessions: `DashboardView.vue`
  - member debt/payment: `MemberDetailView.vue`
  - payment status: `SessionDetailView.vue`

**Issues**

- **Minor — accent usage is broad:** Indigo appears on primary CTAs, links, focus rings, selected states, and some status-like chips such as permanent member status in `MemberView.vue`. Mostly acceptable, but keep accent reserved per UI-SPEC.
  - needs_human_review: false

---

### Pillar 4: Typography (2/4)

**Evidence**

- UI-SPEC allows changed Phase 3 UI to use exactly:
  - Body 16/400
  - Label/Meta 14/700
  - Heading 20/700
  - Display/Financial 32/700
- Post-remediation source check over changed Phase 3 surfaces found 0 matches for:
  - `text-xs`
  - `text-lg`
  - `text-xl`
  - `text-2xl`
  - `text-3xl`
  - `font-medium`
  - `font-semibold`
  - `font-extrabold`
- Remaining approved weights are `font-normal` and `font-bold`.
- Global CSS remaps Tailwind sizes upward in `src/assets/main.css`, making class names harder to map directly to the UI-SPEC pixel contract.

**Issues**

- **Resolved — too many type sizes and weights in changed surfaces:** `MemberView.vue`, `MemberDetailView.vue`, `PaymentQRModal.vue`, `ManualPaymentModal.vue`, and `SessionDetailView.vue` now use UI-SPEC-compatible Heading/Display/body/label classes.
  - needs_human_review: false
- **Resolved — non-approved weights:** `font-medium`, `font-semibold`, and `font-extrabold` are absent from changed Phase 3 surfaces.
  - needs_human_review: false

---

### Pillar 5: Spacing (3/4)

**Strengths**

- 44px touch targets are widely implemented with `min-h-11`/`min-w-11`.
- Bottom nav safe-area padding exists in `BottomNav.vue`.
- App-level bottom padding exists in `App.vue`.
- Payment sheets use `max-h-[88dvh]` and sticky safe-area footers:
  - `PaymentQRModal.vue`
  - `ManualPaymentModal.vue`
- Floating/group bars are offset above bottom nav:
  - `HomeDebtTable.vue`
  - `SessionDetailView.vue`

**Issues**

- **Resolved — invalid calc warning in build:** `pnpm build` now passes without the CSS minify warning. Affected examples were moved to CSS helper classes:
  - `App.vue`
  - `SessionDetailView.vue`
  - `PaymentQRModal.vue`
  - `ManualPaymentModal.vue`
  - needs_human_review: false
- **Resolved — arbitrary spacing centralization:** safe-area page padding, sheet footer padding, and the session group-payment bar offset are now centralized in CSS helper classes.
  - needs_human_review: false

---

### Pillar 6: Experience Design (3/4)

**Strengths**

- Route/access contract preserved:
  - `/create-session` has `requiresAuth` + `requiresAdmin` in `src/router/index.ts`
  - public routes remain unguarded in `src/router/index.ts`
- Admin visibility and handler guards are present:
  - `DashboardView.vue`
  - `MemberView.vue`
  - `SessionDetailView.vue`
- Payment lifecycle is preserved:
  - polling/cleanup/payment-complete in `PaymentQRModal.vue`
  - explicit close/Done in `PaymentQRModal.vue`
  - two-step manual cash in `ManualPaymentModal.vue`
- Type-check and production build pass with no CSS minify warning.

**Issues**

- **Moderate — visual UAT deferred:** source evidence is strong, but actual mobile overlap/reachability at 360/390/430px was not browser-verified.
  - needs_human_review: true
- **Resolved — clipboard failure not surfaced:** `PaymentQRModal.vue` now detects unavailable clipboard support, catches denied writes, logs the error, and shows localized toast feedback.
  - needs_human_review: false

---

## Registry Safety

Registry audit skipped: `components.json` not present; UI-SPEC marks shadcn/third-party registries as none.

---

## Browser Harness Follow-up — 2026-05-27

`browser_harness` connected to Chrome via CDP at `http://127.0.0.1:9242` and verified the running Vite app at `http://localhost:5173`.

| Viewport | Route | Result | Evidence |
|----------|-------|--------|----------|
| 390x844 mobile | `/` | PASS | App rendered debt homepage, no visible error text, no global horizontal overflow, screenshot captured. |
| 390x844 mobile | `/sessions` | PASS | Public sessions list rendered session cards/counts/details links, no visible error text, no global overflow, screenshot captured. |
| 390x844 mobile | `/members` | PASS | Public member list rendered mobile cards/status/details links, no visible error text, no global overflow, screenshot captured. |
| 390x844 mobile | `/login` | PASS | Login form rendered with bottom navigation, no visible error text, no global overflow, screenshot captured. |
| 390x844 mobile | `/create-session` | PASS | Guard redirected unauthenticated user to `/login`. |
| 1280x900 desktop | `/sessions` | PASS | Sessions list rendered, no visible error text, no global overflow. |
| 1280x900 desktop | `/members` | PASS | Desktop member table rendered, no visible error text, no global overflow. |

Captured screenshots are session artifacts only and were not committed:

- `/home/phatngo/.copilot/session-state/07dceea9-e423-4717-900e-03af338018ed/files/browser-harness-20260527/mobile-home.png`
- `/home/phatngo/.copilot/session-state/07dceea9-e423-4717-900e-03af338018ed/files/browser-harness-20260527/mobile-sessions.png`
- `/home/phatngo/.copilot/session-state/07dceea9-e423-4717-900e-03af338018ed/files/browser-harness-20260527/mobile-members.png`
- `/home/phatngo/.copilot/session-state/07dceea9-e423-4717-900e-03af338018ed/files/browser-harness-20260527/mobile-login.png`

No console/runtime error events were surfaced by `drain_events()` during the smoke pass.

### Full Screen Screenshot Sweep — 2026-05-27

The follow-up screenshot sweep captured every current browser-harness test case in grouped folders:

`/home/phatngo/.copilot/session-state/07dceea9-e423-4717-900e-03af338018ed/files/browser-harness-20260527-full-screens`

| Group | Screenshots |
|-------|-------------|
| `01-home-debt/` | `mobile-390x844.png`, `desktop-1280x900.png` |
| `02-sessions-list/` | `mobile-390x844.png`, `desktop-1280x900.png` |
| `03-session-detail-readonly/` | `mobile-390x844.png`, `desktop-1280x900.png` |
| `04-members-list/` | `mobile-390x844.png`, `desktop-1280x900.png` |
| `05-member-detail/` | `mobile-390x844.png`, `desktop-1280x900.png` |
| `06-login/` | `mobile-390x844.png`, `desktop-1280x900.png` |
| `07-create-session-guard/` | `mobile-390x844.png`, `desktop-1280x900.png` |

**Sweep result:** 12/14 passed, 2/14 flagged, 0 console/runtime error events.

Flagged finding:

- `03-session-detail-readonly` at both mobile and desktop rendered the first public session detail route successfully with no global horizontal overflow, but displayed `Tiền sân NaN ₫`. The text scanner also matched the legitimate readonly message `không thể sửa điểm danh`, so the true actionable issue was the `NaN` court-fee display.

Resolution:

- Fixed in `bad7cc0` by normalizing `view_session_summary.total_court_cost` into the existing `court_fee_total` display field and guarding currency formatting against non-finite values.
- Retested with `browser_harness` at 390x844 and 1280x900; both pass with `Tiền sân 0 ₫`, no `NaN`, and no global overflow.
- Retest screenshots:
  - `/home/phatngo/.copilot/session-state/07dceea9-e423-4717-900e-03af338018ed/files/browser-harness-20260527-nan-fix/03-session-detail-readonly/mobile-390x844.png`
  - `/home/phatngo/.copilot/session-state/07dceea9-e423-4717-900e-03af338018ed/files/browser-harness-20260527-nan-fix/03-session-detail-readonly/desktop-1280x900.png`

### UI Review Fix Pass — 2026-05-27

Priority findings were fixed in `38778c0`:

- Typography: normalized changed Phase 3 surfaces in `MemberView.vue`, `MemberDetailView.vue`, `SessionDetailView.vue`, `PaymentQRModal.vue`, and `ManualPaymentModal.vue`.
- Spacing/build: replaced warning-producing safe-area arbitrary Tailwind `calc()` utilities with CSS helpers and constrained Tailwind source scanning to `src`.
- Copy: aligned `Create Session` and manual cash confirmation labels.
- Experience: added localized clipboard failure feedback for QR transfer-content copy.

Verification:

- `pnpm type-check`: PASS
- `pnpm build`: PASS with no CSS minify warning
- Source grep: no prohibited typography classes in changed Phase 3 surfaces
- `browser_harness`: PASS 8/8 affected route+viewport checks for `/sessions`, `/members`, first `/member/:id`, and first `/session/:id` at 390x844 and 1280x900; no global overflow, no `NaN`, no runtime exception text.

Retest screenshots:

- `/home/phatngo/.copilot/session-state/07dceea9-e423-4717-900e-03af338018ed/files/browser-harness-20260527-ui-review-fixes`

---

## Build / Verification Notes

- `pnpm type-check`: PASS
- `pnpm build`: PASS with no CSS minify warning after `38778c0`
- Dev server detection:
  - `localhost:3000`: 200
  - `localhost:5173`: 200
  - `localhost:8080`: 000
- Screenshots: initial auditor could not capture screenshots, but the follow-up `browser_harness` pass captured mobile screenshots listed above.
- Local Open Design artifacts were treated as directional only:
  - `brand-spec.md`
  - `badminton-mobile-preview.html`
  - `badminton-mobile-prototypes.html`
  - `mobile-screen-audit.html`
  - `mobile-screen-audit-2.html`
  - `mobile-prototypes/`
  - PNG metadata reviewed only; binary content not embedded.

---

## Files Audited

- `.planning/phases/03-admin-supporting-screens-payment-polish-regression-pass/03-UI-SPEC.md`
- `.planning/phases/03-admin-supporting-screens-payment-polish-regression-pass/03-CONTEXT.md`
- `.planning/phases/03-admin-supporting-screens-payment-polish-regression-pass/03-RESEARCH.md`
- `.planning/phases/03-admin-supporting-screens-payment-polish-regression-pass/03-PRESERVATION-INVENTORY.md`
- `.planning/phases/03-admin-supporting-screens-payment-polish-regression-pass/03-REGRESSION-SOURCE-CHECKS.md`
- `.planning/phases/03-admin-supporting-screens-payment-polish-regression-pass/03-01-PLAN.md` through `03-05-PLAN.md`
- `.planning/phases/03-admin-supporting-screens-payment-polish-regression-pass/03-01-SUMMARY.md` through `03-05-SUMMARY.md`
- `.planning/phases/03-admin-supporting-screens-payment-polish-regression-pass/03-VERIFICATION.md`
- `src/router/index.ts`
- `src/App.vue`
- `src/assets/main.css`
- `src/views/DashboardView.vue`
- `src/views/CreateSessionView.vue`
- `src/views/HomePage.vue`
- `src/views/MemberView.vue`
- `src/views/MemberDetailView.vue`
- `src/views/SessionDetailView.vue`
- `src/components/AppHeader.vue`
- `src/components/BottomNav.vue`
- `src/components/HomeDebtTable.vue`
- `src/components/PaymentQRModal.vue`
- `src/components/ManualPaymentModal.vue`
- `src/locales/messages.ts`
- `brand-spec.md`
- `badminton-mobile-preview.html`
- `badminton-mobile-prototypes.html`
- `mobile-screen-audit.html`
- `mobile-screen-audit-2.html`
- `mobile-prototypes/`
