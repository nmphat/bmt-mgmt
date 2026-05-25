---
phase: 2
slug: session-detail-task-cockpit
status: ready_for_verification
shadcn_initialized: false
preset: not applicable
created: 2026-05-25
---

# Phase 2 — UI Design Contract

> Visual and interaction contract for the session detail task cockpit. Open Design/local prototypes are directional only; the Vue/Supabase implementation remains the behavior source of truth.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none — use app-owned Vue/Tailwind primitives |
| Preset | not applicable |
| Component library | none; create/reuse local Vue components only |
| Icon library | `lucide-vue-next` |
| Font | system sans: `-apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", system-ui, sans-serif` |

Design-system rule: do not introduce shadcn, a third-party UI registry, or a new component framework. Phase 2 inherits the Phase 1 shell, card, sheet, status, and safe-area conventions.

---

## Spacing Scale

Declared values must be multiples of 4:

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | Icon gaps, checkbox/label micro gaps |
| sm | 8px | Compact element spacing, chip/button inner gaps |
| md | 16px | Default card padding, mobile page side padding |
| lg | 24px | Section gaps, sheet header/content spacing |
| xl | 32px | Major card groups |
| 2xl | 48px | Desktop section rhythm only |

Exceptions:

- Minimum interactive target: `44px` height/width for buttons, icon buttons, mini-tabs, checkboxes/toggle rows, sheet close controls, and refresh.
- Mobile sheet cap: `max-height: 88dvh`.
- Fixed bottom nav offset: `16px + env(safe-area-inset-bottom)`.
- Session group payment bar bottom offset: `92px + env(safe-area-inset-bottom)`.
- Session detail pages reserve bottom padding of at least `96px + env(safe-area-inset-bottom)`.
- Session detail pages where the group payment bar can appear reserve bottom padding of at least `148px + env(safe-area-inset-bottom)`.
- Sticky mini-tabs sit below the app header and use a scroll offset that keeps anchored sections visible below sticky controls.

---

## Typography

Use these text sizes for changed Phase 2 mobile UI:

| Role | Size | Weight | Line Height |
|------|------|--------|-------------|
| Body | 16px | 400 | 1.5 |
| Label / Meta | 14px | 700 | 1.35 |
| Section heading | 20px | 700 | 1.2 |
| Financial amount | 24px | 700 | 1.1 |

Rules:

- Currency and interval counts use tabular numerals where practical.
- Vietnamese labels must not be truncated unless the full value is available in nearby visible text.
- Button text uses 14-16px at weight 700.
- Avoid all-caps except short status/meta chips.

---

## Color

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60%) | Tailwind `gray-50` | App background and neutral shell |
| Secondary (30%) | white | Cards, sections, bottom nav, sticky mini-tabs |
| Accent (10%) | Tailwind `indigo-600` | Primary QR/finalize/register actions, active mini-tab, focus ring, selected snapshot/member state |
| Destructive | Tailwind `red-600` | Remove member, cancel session, destructive confirmations |

Semantic status colors:

- Open: blue.
- Waiting/payment pending: orange/yellow.
- Done/paid/debt-free: green.
- Cancelled/read-only/disabled: gray.
- Registered-but-absent: red text/chip only for the absent state, not for ordinary disabled controls.

---

## Copywriting Contract

All new labels must be added to both `vi` and `en` in `src/locales/messages.ts`.

| Element | Vietnamese Copy | English Copy |
|---------|-----------------|--------------|
| Overview tab/section | Tổng quan | Overview |
| Attendance tab/section | Điểm danh | Attendance |
| Costs tab/section | Chi phí | Costs |
| Payments tab/section | Thanh toán | Payments |
| Session cockpit nav label | Điều hướng chi tiết buổi | Session detail navigation |
| Refresh session | Làm mới buổi | Refresh session |
| Read-only hint | Bạn đang xem ở chế độ chỉ xem. | You are viewing in read-only mode. |
| Admin-only hint | Chỉ quản trị viên mới thao tác được. | Only admins can make changes. |
| Locked session hint | Buổi đã chốt hoặc đang thu tiền nên không thể sửa điểm danh. | Attendance is locked after finalizing or payment collection starts. |
| Cancelled session hint | Buổi đã hủy. Tất cả thao tác chỉ còn xem. | This session is cancelled. All actions are read-only. |
| Add members card title | Thêm thành viên vào buổi | Add members to session |
| No registered members | Chưa có thành viên nào trong buổi. | No members are registered for this session. |
| Mark absent | Đánh dấu vắng | Mark absent |
| Present intervals | Ca có mặt | Present intervals |
| Payment snapshots empty | Chưa có công nợ đã chốt cho buổi này. | No finalized payment snapshots for this session yet. |
| Live costs empty | Chưa có chi phí để hiển thị. | No costs to display yet. |
| Group payment bar | Thanh toán {count} người | Pay {count} members |

No guest-facing login copy appears in the session detail cockpit.

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| shadcn official | none | not applicable |
| third-party | none | not applicable |

Registry rule: no third-party UI registry blocks are approved for Phase 2.

---

## Phase Interaction Contract

### Overall Layout

- Route remains `/session/:id` and public read-only.
- Mobile renders four stacked cards/sections in this order:
  1. Overview
  2. Attendance
  3. Costs
  4. Payments
- A sticky mini-tab/anchor row appears near the top of mobile session detail and links to the four sections.
- Default active/highlighted section is status-aware:
  - `open` -> Attendance
  - `waiting_for_payment` -> Payments
  - `done` -> Payments
  - `cancelled` -> Overview
- Desktop/tablet can keep table-oriented structure, but the financial/status/action fields from current tables must remain available.

### Overview Section

Overview shows:

- Back/navigation and manual refresh.
- Session title.
- Date/time.
- Status chip.
- Court fee.
- Shuttle fee.
- Total collected when status is `waiting_for_payment` or `done`.
- Cancelled/read-only messaging when applicable.
- Admin edit/cancel/finalize controls when `authStore.isAdmin && session.status === 'open'`.

Overview does not duplicate deep attendance rows, cost member rows, or payment snapshot rows.

### Attendance Section

Attendance shows:

- Registered member name.
- Registered-but-absent state separate from removal.
- Interval presence controls for every interval.
- Admin remove registration action.
- Admin mark absent action.
- Add active members control when the session is editable.
- Read-only/locked hints for guests, non-admin authenticated users, waiting/done sessions, cancelled sessions, and absent members.

Mobile attendance may use member cards or accordions. Desktop may preserve the sticky-column matrix. Both must preserve:

- `add_member_to_session_full_presence`
- `session_registrations.delete`
- `interval_presence.upsert`
- `session_registrations.update({ is_registered_not_attended })`

Mutation controls and handlers must use `authStore.isAdmin` plus status locks, not only `authStore.isAuthenticated`.

### Costs Section

Costs displays live `calculate_session_costs` results for non-finalized sessions:

- Member display name.
- Final total.
- Interval count.
- Court fee.
- Shuttle fee.
- Surplus fund.

The frontend may sum/display returned values for presentation, but it must not allocate shared fees or replace `calculate_session_costs`.

### Payments Section

Payments displays finalized `session_costs_snapshot` results for `waiting_for_payment` and `done` sessions:

- Member display name.
- Must-pay/final amount.
- Paid amount.
- Payment status.
- Interval count.
- Court fee.
- Shuttle fee.
- Surplus fund.
- Single QR action for unpaid snapshots.
- Group QR selection/action for unpaid selected snapshots available to authenticated users as currently supported.
- Manual cash action for admins only.

Payment UI must reuse Phase 1 sheet semantics:

- QR/cash sheets cap at `88dvh`, use inner scroll, and have sticky safe-area footers.
- QR success emits refresh and remains open until the user closes/done.
- Manual cash requires review confirmation before `add_manual_payment`.

### Session Group Payment Bar

- Appears only when one or more unpaid snapshots are selected.
- Sits above the Phase 1 bottom nav using `bottom: calc(92px + env(safe-area-inset-bottom))` or equivalent Tailwind arbitrary value.
- Displays selected count and selected total.
- Primary action uses indigo accent and creates group QR through `create_group_payment`.
- Must not overlap bottom nav, payment sheet triggers, toasts, or section content at 360px, 390px, or 430px.

### Realtime / Polling Visible States

- Manual refresh remains available.
- Realtime subscriptions to `interval_presence`, `session_registrations`, and `session_costs_snapshot` remain active while the view is mounted.
- Polling remains a fallback and must not duplicate timers.
- Refresh/payment-complete updates visible attendance/cost/payment state without stale selected modal payloads after close.

---

## Accessibility Contract

- Mini-tabs use semantic buttons or links with `aria-label`, visible text, focus rings, and `aria-current`/active state where practical.
- Section headings are real headings and have stable anchor IDs.
- Refresh, edit, cancel, finalize, remove, absent, QR, cash, group QR, close, and confirm actions are native buttons or links with visible labels or accessible names.
- Disabled controls expose visible reasons near the section, not only disabled styling.
- Checkboxes/toggles remain keyboard reachable.
- Status is communicated with text plus color/icon, not color alone.

---

## Fixed-Layer and Viewport Contract

At 360px, 390px, and 430px:

- Bottom nav remains reachable.
- Sticky mini-tabs do not cover section headings after anchor navigation.
- Session group payment bar sits above bottom nav.
- Payment sheets stay within `88dvh`, scroll internally, and keep footer actions reachable.
- Toasts do not cover group payment actions.
- Page bottom padding reserves fixed layers.

Source-verifiable constants:

- `calc(92px + env(safe-area-inset-bottom))` for the session group payment bar.
- `calc(148px + env(safe-area-inset-bottom))` for pages where the group payment bar can appear.
- `max-h-[88dvh]` or equivalent for sheets.

---

## No-Regression Checklist

Phase 2 is not complete unless source/build verification confirms:

- `/session/:id` remains public read-only.
- Admin-only controls and handlers use `authStore.isAdmin`.
- Open/waiting/done/cancelled states remain distinct.
- `view_session_summary`, `calculate_session_costs`, `finalize_session`, `add_member_to_session_full_presence`, `create_group_payment`, `add_manual_payment`, `session_costs_snapshot`, `session_registrations`, `interval_presence`, and `sessions.update` remain referenced with existing semantics.
- Attendance toggle, absent toggle, add registration, remove registration, edit, cancel, finalize, single QR, group QR, manual cash, refresh, realtime, and polling remain available in their allowed states.
- No frontend shared-fee allocation is introduced.
- New labels exist in both Vietnamese and English.
- Type-check and build pass.
- Human visual UAT remains documented as user-skipped/deferred unless the user later requests it.

