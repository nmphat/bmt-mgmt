# Phase 1: Mobile Shell + Debt/Payment Foundation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.  
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-21  
**Phase:** 01-mobile-shell-debt-payment-foundation  
**Areas discussed:** Mobile shell & role-aware navigation, Debt discovery & selection, QR payment sheet/dialog behavior, Feature-preservation guardrails

---

## Mobile shell & role-aware navigation

| Option | Description | Selected |
|--------|-------------|----------|
| Role-aware bottom nav with Home/Members/Login for guest and admin-only Sessions/Create | Preserved original router assumptions | |
| Prototype-like guest Sessions nav with login/permission message | Would expose Sessions but keep route blocked | |
| Public 3-tab bottom nav | Home/Debt, Members, Sessions are visible public tabs | yes |

**User's choice:** Mobile bottom nav shows Home/Debt, Members, Sessions. Login is hidden; only admin needs login.

**Notes:** The source showed `/sessions` was guarded admin-only even though `DashboardView` has read-only behavior. The route guard was removed and Create Session was changed to `isAdmin`.

---

## Hidden admin login

| Option | Description | Selected |
|--------|-------------|----------|
| No visible login UI | Admin opens `/login` manually | yes |
| Small hidden icon | Login behind an unlabeled icon | |
| Desktop-only login button | Hide on mobile only | |

**User's choice:** No visible login UI. Admin manually opens `/login`; after login, profile/logout/admin actions appear.

---

## Header and language switcher

| Option | Description | Selected |
|--------|-------------|----------|
| Compact header actions | Header owns language switcher and admin/profile/logout actions | yes |
| Admin bottom nav tab | Add an Admin tab for logged-in admins | |
| Profile/settings sheet only | Hide secondary actions behind a sheet | |

**User's choice:** Header compact/top bar; bottom nav remains only Home, Members, Sessions. Language switcher is top-right, compact, and always visible.

---

## Members access

| Option | Description | Selected |
|--------|-------------|----------|
| Guest read-only; admin CRUD | Guests can view member list/detail; admins can add/edit/delete | yes |
| Guest list names only | No member detail for guest | |
| Members admin-only | Tab visible but gated | |

**User's choice:** Guest sees member list and member detail, including sessions attended and payment status. Admin after login can add/edit/delete.

---

## Debt discovery and filters

| Option | Description | Selected |
|--------|-------------|----------|
| Search + total-debt sort | Use current backend-supported data; defer unsupported chips | yes |
| API-supported chips only | Add chips only if current fields support them | |
| Prototype-like heuristic chips | Infer high/late/partial in frontend | |

**User's choice:** Search by member name and sort by total debt; defer overdue/partial/high-debt filter chips.

---

## Debt card selection

| Option | Description | Selected |
|--------|-------------|----------|
| Checkbox + sticky group bar; no long press | Explicit selection and group payment bar | |
| Tap card body selects; Details navigates | Avoid missed checkbox taps causing navigation | yes |
| Card body navigates; checkbox only selects | Highest accidental navigation risk | |

**User's choice:** Tap debt card body toggles selection. Only Details navigates to member detail.

---

## Debt card content

| Option | Description | Selected |
|--------|-------------|----------|
| Name, total debt, unpaid count, selected state, QR action, Details link | No per-session rows on home | yes |
| Include latest unpaid sessions inline | Higher density, more API/data complexity | |
| Name + amount only | Too little context | |

**User's choice:** Home debt cards show name, total debt, unpaid session count, selected state, QR action, and Details link. No per-session rows on home.

**Notes:** User mentioned admin cash. Source scan found cash/manual payment only in `SessionDetailView.vue`, not `/` debt home. User then clarified current logic works fine and does not need change. Context records not to change cash logic in Phase 1.

---

## Debt loading/empty/load-more

| Option | Description | Selected |
|--------|-------------|----------|
| Skeleton cards + debt-free empty + load-more button | Keeps current pagination without infinite scroll | yes |
| Spinner only | Minimal polish | |
| Infinite scroll/pull-to-refresh | New behavior | |

**User's choice:** Use skeleton/card placeholders, empty debt-free state, and keep load-more button. Do not use infinite scroll.

---

## Payment sheet overflow

| Option | Description | Selected |
|--------|-------------|----------|
| Mobile bottom sheet capped around 88dvh | Inner scroll, sticky/safe-area footer, desktop dialog | yes |
| Full-screen mobile payment page/sheet | Larger behavior change | |
| Current modal + max-height/overflow | Smaller fix but less aligned with Open Design | |

**User's choice:** Mobile bottom sheet max-height around 88dvh, inner content scroll, sticky/safe-area footer; desktop remains dialog.

---

## QR sheet content order

| Option | Description | Selected |
|--------|-------------|----------|
| Amount -> QR -> transfer content/copy -> breakdown -> status/actions | Prioritizes amount/code clarity | yes |
| QR first | Similar to current modal | |
| Compact summary with expandable QR/details | More complex | |

**User's choice:** Amount first, then QR, transfer content/copy, member/group breakdown, status note/actions.

---

## Payment polling and success

| Option | Description | Selected |
|--------|-------------|----------|
| Poll only while sheet open; success state; user closes | Preserves refresh and avoids surprise close | yes |
| Auto-close when paid | Faster but surprising | |
| Manual refresh only | Less helpful | |

**User's choice:** Poll only while sheet is open. When paid, show success, emit refresh, and user closes with Done/Close.

---

## Admin cash double confirmation

| Option | Description | Selected |
|--------|-------------|----------|
| Second confirm step in same sheet | Review member/session/amount/remaining/note, then confirm | yes |
| Browser confirm() | Quick but poor UX | |
| Required checkbox before submit | Lower-friction but weaker confirmation | |

**User's choice:** Admin cash requires a second confirmation step in the same sheet.

---

## Payment visibility

| Option | Description | Selected |
|--------|-------------|----------|
| Guest/member QR only; admin QR + cash where snapshot context supports it | Preserves role safety and backend boundary | yes |
| QR only for everyone in Phase 1 | Would risk dropping admin cash | |
| Admin cash on aggregate home cards | Requires backend-safe allocation contract | |

**User's choice:** Guest/member see QR only. Admin sees QR + cash where current snapshot context supports it. Cash never appears to guest.

---

## Preservation inventory

| Option | Description | Selected |
|--------|-------------|----------|
| Route + component + role/access + Supabase contract + payment entry matrix | Detailed enough for touched screens | yes |
| Short requirement checklist | Faster but weaker | |
| Full app inventory | Too broad for Phase 1 | |

**User's choice:** Create a preservation matrix for all touched screens.

---

## Route/access guardrail

| Option | Description | Selected |
|--------|-------------|----------|
| Verify guest public routes and admin-only mutations/actions | `/`, `/members`, `/member/:id`, `/sessions`, `/session/:id`; admin-only create/edit/delete/finalize/cash | yes |
| Only verify bottom nav rendering | Too shallow | |
| Rely on router guard + visual review | Too implicit | |

**User's choice:** Verify guest route access and admin-only actions explicitly.

---

## Mobile/i18n guardrail

| Option | Description | Selected |
|--------|-------------|----------|
| VI+EN keys plus 360/390/430 visual sweep | Checks overlap of bottom nav, bulk bar, sheets, toasts | yes |
| VI first, EN later | Not acceptable | |
| Best-effort i18n/responsiveness | Too weak | |

**User's choice:** Every new label has VI+EN; run 360/390/430 visual sweeps.

---

## Validation checklist

| Option | Description | Selected |
|--------|-------------|----------|
| Type-check/build + manual guest/admin sweeps | Debt, members, sessions list, QR/group QR, hidden login, admin actions | yes |
| Type-check/build only | Not enough for UI preservation | |
| Add automated tests before refactor | Too much setup for Phase 1 | |

**User's choice:** Run type-check/build and manual guest/admin sweeps before commit/ship.

---

## the agent's Discretion

- Exact component structure, naming, icons, skeleton styling, spacing, and extraction strategy.

## Deferred Ideas

- Unsupported debt filter chips: overdue, high debt, partial payment.
- Prototype long-press debt selection.
- Aggregate member cash payment from home debt cards unless backend-safe allocation exists.
- Guest "I transferred" confirmation.
