---
phase: 3
slug: admin-supporting-screens-payment-polish-regression-pass
status: draft
shadcn_initialized: false
preset: not applicable
created: 2026-05-26
---

# Phase 3 — UI Design Contract

> Visual and interaction contract for admin/supporting screens, payment polish, and final regression. Open Design/local prototypes are directional only; current Vue/Supabase behavior remains authoritative.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none — use app-owned Vue/Tailwind primitives |
| Preset | not applicable |
| Component library | none; create/reuse local Vue components only |
| Icon library | `lucide-vue-next` |
| Font | system sans: `-apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", system-ui, sans-serif` |

Sources: Phase 1 UI-SPEC, Phase 2 UI-SPEC, `package.json`, Phase 3 CONTEXT, source scout.

Design-system rule: do not introduce shadcn, third-party UI registries, Radix, Base UI, or any new UI framework. This Vue/Vite app already uses Tailwind v4 utilities, local components, Pinia, Vue Router, Supabase JS, and `vue-toastification`.

---

## Spacing Scale

Declared values must be multiples of 4:

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | Icon gaps, checkbox/label micro gaps |
| sm | 8px | Compact element spacing, chip/button inner gaps |
| md | 16px | Default card padding, mobile page side padding |
| lg | 24px | Section gaps, sheet header/content spacing |
| xl | 32px | Major card groups, page blocks |
| 2xl | 48px | Desktop section rhythm only |
| 3xl | 64px | Desktop page-level spacing only |

Exceptions:

- Minimum interactive target: `44px` height/width for buttons, icon buttons, member row/card actions, sheet close controls, payment copy controls, checkboxes/toggle rows, and form submit actions.
- Mobile sheet cap: `max-height: 88dvh`.
- Sheet footer padding: include `env(safe-area-inset-bottom)`.
- Pages with bottom nav reserve bottom padding of at least `96px + env(safe-area-inset-bottom)`.
- Pages where a floating/group payment bar can appear reserve bottom padding of at least `148px + env(safe-area-inset-bottom)`.
- Fixed bottom nav offset remains `16px + env(safe-area-inset-bottom)`.
- Payment/floating bars must sit above bottom nav using the Phase 1/2 offset pattern, not `bottom: 0`.

---

## Typography

Use exactly these four text sizes for changed Phase 3 UI:

| Role | Size | Weight | Line Height |
|------|------|--------|-------------|
| Body | 16px | 400 | 1.5 |
| Label / Meta | 14px | 700 | 1.35 |
| Heading | 20px | 700 | 1.2 |
| Display / Financial amount | 32px | 700 | 1.05 |

Allowed weights: `400` and `700` only.

Rules:

- Currency, counts, and QR/payment codes use tabular numerals or monospace where practical.
- Vietnamese labels must not be truncated unless full value remains visible nearby.
- Button text uses 14–16px at weight `700`.
- Avoid all-caps except compact status/meta chips.
- Desktop tables may retain smaller table header text, but changed mobile cards must follow this density.

---

## Color

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60%) | Tailwind `gray-50` / neutral shell | App background, page shell |
| Secondary (30%) | white | Cards, sheets, forms, bottom nav, desktop dialog surfaces |
| Accent (10%) | Tailwind `indigo-600` | Primary create/session/payment CTAs, Details links, active nav state, selected payment/member state, focus rings |
| Destructive | Tailwind `red-600` | Delete member, cancel destructive confirmation, destructive error emphasis only |

Accent reserved for:

- `Tạo Buổi tập` / `Create Session`
- `Tạo QR thanh toán` / `Create payment QR`
- `Tạo QR gộp` / `Create group QR`
- `Chi tiết` / `Details` route actions
- selected card/checkbox/focus states
- primary form submit buttons
- active bottom nav/header focus rings

Semantic status colors:

- Open: blue.
- Waiting/payment pending/partial: orange or yellow.
- Done/paid/debt-free: green.
- Cancelled/read-only/disabled/neutral: gray.
- Destructive delete/cancel: red only when action is destructive.

---

## Copywriting Contract

All new labels must be added to both `vi` and `en` in `src/locales/messages.ts`.

| Element | Vietnamese Copy | English Copy |
|---------|-----------------|--------------|
| Sessions primary CTA | Tạo Buổi tập | Create Session |
| Sessions empty state | Không có buổi tập | No sessions found. |
| Sessions load error | Không tải được danh sách buổi. Hãy thử lại hoặc báo quản trị viên nếu lỗi tiếp tục. | Could not load sessions. Try again or contact an admin if it continues. |
| Session card details | Xem chi tiết | View details |
| Create-session primary CTA | Tạo buổi tập | Create Session |
| Create-session loading CTA | Đang tạo... | Creating... |
| Create-session validation error | Giờ kết thúc phải sau giờ bắt đầu | End time must be after start time |
| Create-session error | Không tạo được buổi. Kiểm tra thông tin và thử lại. | Could not create the session. Check the details and try again. |
| Members primary CTA | Thêm Thành viên | New Member |
| Members empty state | Chưa có thành viên nào. | No members yet. |
| Members load error | Không tải được danh sách thành viên. Hãy thử lại hoặc báo quản trị viên nếu lỗi tiếp tục. | Could not load members. Try again or contact an admin if it continues. |
| Member create CTA | Thêm thành viên | Add member |
| Member update CTA | Cập nhật thành viên | Update member |
| Member delete confirmation | Xóa "{name}"? Không thể hoàn tác. | Delete "{name}"? This cannot be undone. |
| QR amount label | Cần thanh toán | Amount to pay |
| QR transfer content | Nội dung | Transfer details |
| QR status note | Tự động cập nhật khi nhận tiền. | Status updates automatically once payment is received. |
| QR success | Đã nhận thanh toán. Bạn có thể đóng cửa sổ này. | Payment received. You can close this sheet. |
| Manual cash review title | Kiểm tra lại tiền mặt | Review cash payment |
| Manual cash confirm CTA | Xác nhận tiền mặt | Confirm cash |

Destructive actions in this phase:

- Delete member: browser/native confirmation or equivalent modal must include member name and irreversible warning.
- Cancel session remains governed by Phase 2 session detail contract if surfaced in final validation.
- No destructive payment action is added.

No guest-facing login affordance is introduced. `/login` remains directly addressable.

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| shadcn official | none | not applicable — shadcn not initialized |
| third-party | none | not applicable |

Registry rule: no third-party UI registry blocks are approved for Phase 3.

---

## Phase Interaction Contract

### Focal Points

- Sessions list focal point: next playable/most recent session identity first, then status/date, then compact participation counts and Details navigation.
- Create-session focal point: required session timing and fee inputs first, with the create action visually anchored after validation-critical fields.
- Members list focal point: member identity and status chips first, then Details navigation, with admin edit/delete actions secondary and clearly separated.
- Payment sheets focal point: amount and transfer content first, QR/action controls second, breakdown/status supporting the payment decision below.

### Route and Access Contract

Preserve exactly:

- `/` public debt home.
- `/sessions` public read-only.
- `/members` public read-only.
- `/member/:id` public.
- `/session/:id` public read-only unless admin-gated operations apply.
- `/login` directly addressable.
- `/create-session` guarded by `requiresAuth` and `requiresAdmin`.

Admin affordances must use `authStore.isAdmin` for visibility and handler guards.

### Sessions List

`/sessions` mobile cards must show:

- Session title.
- Status chip.
- Date.
- Interval count.
- Registration count.
- Explicit Details/View details action or full-card link to `/session/:id`.

Behavior:

- Guests and non-admins can view and navigate only.
- Create Session CTA appears only for admins.
- Data source remains `view_session_summary`.
- Loading state may use spinner or skeleton, but must not show stale admin controls.
- Empty state uses the copy contract.
- Desktop/tablet may keep the existing responsive card grid.

### Create Session

`/create-session` remains guarded and must preserve:

- Title.
- Date.
- Start time.
- End time.
- Court fee.
- Shuttle fee.
- End-time-after-start-time validation.
- Loading disabled state.
- Success toast.
- Error toast.
- RPC: `create_session_with_intervals`.
- Payload keys: `p_title`, `p_start_time`, `p_end_time`, `p_court_fee`, `p_shuttle_fee`, `p_created_by`.

Mobile form contract:

- Single-column stacked fields at 360–430px.
- Date/time pair may be two columns only if labels and controls remain readable.
- Inputs min-height `44px`.
- Submit button full-width and sticky only if it does not overlap bottom nav.
- Do not add recurrence, court selection, default members, fee splitting, or new defaults.

### Members List and CRUD

`/members` mobile cards must show:

- Display name.
- Role.
- Active state.
- Permanent state.
- Details navigation.
- Admin edit/delete actions only for admins.

Desktop table information must remain available.

Add/edit/delete must preserve:

- `members.insert`.
- `members.update`.
- `members.delete`.
- Display name.
- Role.
- Active.
- Permanent.
- Create-another behavior.
- Loading state.
- Toast feedback.
- Delete confirmation.

Mobile member form contract:

- Add form may stay inline, but must fit 360px without horizontal scroll.
- Checkboxes have 44px label/tap rows.
- Save/cancel/delete controls have visible labels or accessible names.
- Editing one member must remain visually distinct from read-only cards/rows.

### Member Detail / Table-to-Card Preservation

Member detail must preserve:

- Debt summary.
- Session history.
- Interval time display.
- Final amount.
- Court fee.
- Shuttle fee.
- Paid amount.
- Remaining amount.
- Status.
- Single QR action.
- Group/pay-all QR action.
- `view_member_debt_summary`.
- `view_member_session_details`.
- `create_group_payment`.

Mobile card layouts must not omit fields from desktop tables. Additive mobile cards are preferred over risky table removal.

### Payment QR Modal

`PaymentQRModal.vue` remains the single QR/group QR surface for home, member detail, and session detail.

Must preserve:

- QR URL generation using backend/RPC-owned amount and code.
- Transfer content copy.
- Group breakdown.
- Polling only while open.
- Polling cleanup on close/unmount.
- `payment-complete` event.
- Explicit close/Done dismissal.
- No auto-close-on-paid.
- Payload cleanup after close by callers.
- QR alt text.
- `role="dialog"` and `aria-modal="true"`.

Responsive presentation:

- Mobile: bottom sheet.
- Desktop: centered dialog.
- `max-h-[88dvh]`.
- Internal scroll body.
- Sticky safe-area footer.
- 44px close/copy/done controls.

Pending QR content order:

1. Amount.
2. QR image.
3. Transfer content + copy action.
4. Member/group breakdown.
5. Status note/actions.

### Manual Payment Modal

`ManualPaymentModal.vue` remains the admin manual cash sheet.

Must preserve:

- Caller-side admin-only access.
- Two-step flow: entry then review.
- Amount > 0 validation.
- Member name.
- Remaining debt display.
- Note.
- `add_manual_payment`.
- Success toast.
- Close disabled while submitting.
- No cash allocation or aggregate splitting added.

Manual cash CTA may use green semantic success color, but focus rings remain indigo.

---

## Accessibility Contract

- All changed buttons and links are native `button`/`a`/`router-link` equivalents.
- Icon-only actions require `aria-label` or visible text.
- Sheet/dialog roots use `role="dialog"` and `aria-modal="true"`.
- Dialog titles have stable labelled-by IDs.
- QR image has meaningful alt text.
- Payment success/status uses `aria-live="polite"` where practical.
- Status chips include text, not color alone.
- Disabled states include visible reason when the action is blocked by role/status.
- Focus rings use indigo and remain visible on keyboard navigation.
- Touch targets are at least 44px.

---

## Fixed-Layer and Viewport Contract

At 360px, 390px, and 430px:

- Bottom nav remains reachable.
- Session/member cards are not hidden behind bottom nav.
- Payment sheets stay within `88dvh`.
- Sheet footer actions remain reachable.
- Toasts must not cover primary payment/create/member actions.
- Any floating bar sits above the bottom nav.
- Page bottom padding reserves fixed layers.

Source-verifiable constants:

- `max-h-[88dvh]` or equivalent for payment sheets.
- `pb-[calc(...+env(safe-area-inset-bottom))]` or equivalent for sheet footers.
- At least `96px + env(safe-area-inset-bottom)` bottom padding for bottom-nav pages.
- At least `148px + env(safe-area-inset-bottom)` where a group/floating payment bar can appear.

Human visual UAT remains skipped/deferred per user instruction. Use source, route/access, build/type-check, and fixed-layer evidence.

---

## Source-of-Truth Preservation

Do not change these behavior contracts:

| Area | Source |
|------|--------|
| Route access | `src/router/index.ts` |
| Sessions list | `view_session_summary` |
| Create session | `create_session_with_intervals` |
| Member CRUD | `members.insert`, `members.update`, `members.delete` |
| Debt summary | `view_member_debt_summary` |
| Member detail | `view_member_session_details` |
| Session detail | `view_session_summary`, `calculate_session_costs`, `session_costs_snapshot` |
| Finalize session | `finalize_session` |
| Session registration | `add_member_to_session_full_presence`, `session_registrations` |
| Attendance | `interval_presence` |
| Session update | `sessions.update(...)` |
| Group QR | `create_group_payment` |
| Manual cash | `add_manual_payment` |
| Language | `src/locales/messages.ts`, `src/stores/lang.ts` |
| Auth/admin state | `src/stores/auth.ts` |

Frontend must not recalculate shared costs, split fees, allocate cash payments, rewrite payment authority, or introduce schema/RLS/RPC changes.

---

## Final No-Regression Checklist

Phase 3 is not complete unless automated/source/build evidence confirms:

- `/sessions` remains public read-only.
- `/members` remains public read-only.
- `/member/:id` remains public.
- `/session/:id` remains public read-only with admin-only mutations.
- `/login` remains directly addressable.
- `/create-session` remains `requiresAuth + requiresAdmin`.
- Guests do not see admin create/edit/delete/manual-cash actions.
- Admin handlers also guard with `authStore.isAdmin`.
- Sessions list cards preserve title/status/date/intervals/registrations/details.
- Create-session preserves validation, loading, toast, and RPC payload.
- Members list preserves role/active/permanent/details/admin edit/delete/create-another.
- Payment modals preserve QR URL, copy, group breakdown, polling, payment-complete, Done/close, cleanup, and two-step manual cash.
- New labels exist in both Vietnamese and English.
- Table-to-card conversions do not omit financial/status/action fields.
- Bottom nav, floating bars, toasts, and sheets do not block primary actions by source evidence.
- `npm run build` or equivalent type-check/build passes.
- Human visual UAT is documented as skipped/deferred.

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS
- [ ] Dimension 2 Visuals: PASS
- [ ] Dimension 3 Color: PASS
- [ ] Dimension 4 Typography: PASS
- [ ] Dimension 5 Spacing: PASS
- [ ] Dimension 6 Registry Safety: PASS

**Approval:** pending
