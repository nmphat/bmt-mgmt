# UI review — fix/phase0-security, 3efe1a4..9f4a3c7

Scope note: `git blame -L <line> 3efe1a4..HEAD` was used throughout to separate
branch-introduced issues from pre-existing ones. `3efe1a4` is the merge-base
(parent of the range), so any line still blamed to it predates this branch.

## Critical

- **Both "add a shuttle" buttons show the wrong label — a noun, not an action.**
  `src/components/session/ShuttleUsageEditor.vue:184` and
  `src/views/SettingsView.vue:346` both render `t('shuttle.type')`, which is
  "Loại cầu" / "Shuttle type". The button that should say "Add shuttle type"
  ("Thêm loại cầu") exists as `shuttle.addType` in
  `src/locales/messages.ts:352` (vi) and `:738` (en) — added in the same
  commit (822e8c2) — but is referenced nowhere (`grep -rn "shuttle.addType" src/`
  returns nothing; `pnpm i18n:audit`'s unused-key list confirms it). The user
  sees a `+` icon next to the word "Shuttle type" with no verb at all, on the
  two places in the app where you add a new shuttle line or catalogue entry.
  Fix: use `t('shuttle.addType')` in both places.

- **Untranslated, hardcoded English strings ship to every user regardless of
  language** — these bypass `t()` entirely, so `pnpm i18n:audit` (which only
  checks the `messages.ts` catalogue) cannot see them:
  - `src/views/SettingsView.vue:411` — `:title="st.is_active ? 'Active' : 'Inactive'"`
    on the shuttle-type toggle button. Introduced by this branch (d820a3c).
    Every other status label in the app goes through `common.*` keys (e.g.
    `common.open`, `common.done`); this one doesn't.
  - `src/components/session/ShuttleUsageEditor.vue:92` —
    `toast.error(err.message || 'Error saving shuttle usage')`.
  - `src/views/SettingsView.vue:145` —
    `toast.error(error.message || 'Error adding shuttle type')`.
  - `src/views/CreateSessionView.vue:200` —
    `>{{ t('session.courtFeeAddon') }} (VND)</label>`. The `(VND)` is a raw
    literal appended outside `t()`; it renders in English even when the whole
    page is in Vietnamese. `session.courtFeeAddon` itself doesn't include a
    currency unit ("Tiền sân thêm"/"Court fee add-on"), and no other numeric
    input label in the app appends a currency hint like this, so it's also a
    one-off pattern, not an established convention being followed.
    Introduced by a07ccc0.

## Important

- **The two new editors don't read as the same design system**, even though
  they sit on the same screen (`SessionDetailView.vue`, edit mode +
  shuttle section):
  - Heading tag: `CourtBookingEditor.vue:131` uses `<h2>`;
    `ShuttleUsageEditor.vue:101` uses `<h3>`. Same visual style
    (`text-[20px] font-bold leading-[1.2]`), different semantic level.
  - Running total: `CourtBookingEditor.vue:262-264` renders
    `"Tổng tiền sân: 500.000₫"` as one bold line. `ShuttleUsageEditor.vue:186-191`
    splits it into a small gray label (`text-sm text-gray-500`) plus a
    separate large bold value (`text-lg font-bold`). Same concept ("running
    total on this editor"), two different visual treatments right next to
    each other on the page.
  - Remove control: `CourtBookingEditor.vue:218-228` uses a `Trash2` icon,
    `hover:text-red-600`, and is always rendered (disabled + grayed via
    `disabled:opacity-30` when it can't be used).
    `ShuttleUsageEditor.vue:164-171` uses a literal `&times;` glyph,
    `hover:text-red-500`, and is removed from the DOM entirely
    (`v-if="!disabled"`) rather than disabled. Two different icon languages
    and two different ways of expressing "you can't remove this right now."
  - Add control: `CourtBookingEditor.vue`'s add buttons (`addCourt`/`addSlot`)
    bind `:disabled="disabled"` and show `disabled:opacity-50`.
    `ShuttleUsageEditor.vue:176-185`'s add-row button has no `:disabled`
    binding at all — it's just hidden via `v-if="!disabled"`, and is missing
    the `justify-center` its sibling buttons have.
  - Persistence model: `CourtBookingEditor` is a pure `v-model` child with no
    save button of its own — the parent page's single Save action commits it
    (`SessionDetailView.vue:1078-1084`, then Save at `:1093-1102`).
    `ShuttleUsageEditor` does its own Supabase RPC call
    (`handleSave`, `ShuttleUsageEditor.vue:81-96`) with its own Save button,
    its own spinner, and its own toast — and no Cancel/discard control. On
    the session detail page, editing a court and editing shuttle usage are
    two structurally different save flows, not one consistent pattern. A user
    who edits both and clicks the session's "Save" button will not save the
    shuttle changes; they have to notice and click ShuttleUsageEditor's own
    Save separately.

- **`ShuttleUsageEditor` doesn't behave like a page section next to its
  siblings.** Every other block on `SessionDetailView.vue` — overview,
  attendance, costs, payments — is a `<section id="...-section" class="...
  rounded-2xl border border-gray-100 ...">` with a `px-6 py-4 border-b
  border-gray-100 bg-gray-50` header bar, and all four are wired into the
  mobile section-tabs ribbon (`sectionTabs`, `SessionDetailView.vue:108-113`,
  rendered at `:2011-2035`). `ShuttleUsageEditor` is dropped in as a bare
  sibling (`:1655-1660`) with its own self-contained card
  (`border-gray-200`, no header bar, `<h3>` not the section `<h2>` pattern)
  and is not one of the four tabs — on a phone there's no way to jump
  straight to it, only scroll past it between Attendance and Payments.
  It also disappears completely once `session.status !== 'open'`
  (`v-if="session.status === 'open' && authStore.isAdmin"`), with no
  locked-state messaging, unlike Attendance which shows an explicit
  lock chip and hint text (`attendanceLockMessage`) when it becomes
  read-only. After finalization there is no way to see what shuttle usage
  was recorded for the session.

- **New session-edit time inputs copy the old, non-compliant field style
  instead of the new design system, in the same panel as the new editor.**
  `SessionDetailView.vue:1031-1035` and `:1041-1046` (the `session_start`/
  `session_end` `<input type="time">` fields) were added by this branch
  (07b73ae) and use
  `class="mt-1 block w-full rounded-md border-gray-300 shadow-sm ... sm:text-sm border px-3 py-2"`
  — `rounded-md` (smaller than even the banned `rounded-lg`) and no
  `min-h-11`, i.e. below the declared minimum touch target. This matches
  the pre-existing title/status/court-fee/price inputs in the same form
  (blamed to `3efe1a4`), but it sits two lines above the brand-new
  `CourtBookingEditor` (`:1078`) which correctly uses `rounded-xl` and
  `min-h-11` throughout. The seam between old and new UI is visible inside
  a single edit panel.

- **`SettingsView.vue:341` "Add shuttle type" button copies the stale
  `rounded-lg` class from the pre-existing "Add bank" button** (`:197`,
  predates the branch) instead of `rounded-xl`, which every other new
  element this branch added in the same file uses (e.g. the shuttle-form
  inputs at `:361`, `:374`, `:386`, the submit button at `:393`). This is a
  new violation of the "rounded-lg must not appear" rule, introduced by
  d820a3c, produced by matching a stale neighbour rather than the new system.
  (`SettingsView.vue:316`'s `rounded-lg` delete-bank button is pre-existing,
  blamed to `3efe1a4`, and out of this branch's scope.)

- **New shuttle-type "toggle active" button is an undersized, unlabeled
  touch target.** `SettingsView.vue:408-420` (new, d820a3c) is
  `class="shrink-0 transition hover:scale-110"` wrapping a bare 20px icon
  (`h-5 w-5`) — no `min-h-11`/`min-w-11`, no `focus-visible:outline`, no
  `:aria-label`. It was modeled on the pre-existing bank "set default" button
  (`:278-297`), which has the same missing touch-target sizing but at least
  keeps the `focus-visible:outline`. The new button is worse than the stale
  pattern it copied, and violates "every touch target has `min-h-11`" — this
  one is a repeatedly-tapped control in a list, at a court, on a phone.

- **Shuttle quantity field has no visible label; `CourtBookingEditor`'s
  fields all do.** `ShuttleUsageEditor.vue:130-160` (the stepper block —
  decrement, `used` input, increment) has no `<label>` anywhere in it, even
  though a `shuttle.used` key ("Số quả đã dùng"/"Shuttles used") exists in
  `messages.ts:355`/`:741` (added in 822e8c2, also unused, confirmed via
  `pnpm i18n:audit`). Every field in `CourtBookingEditor` — start time, end
  time, price — has a `<label class="mb-1 block text-xs text-gray-500">`.
  The shuttle stepper's only accessible name comes from `:data-testid`, which
  is not exposed to assistive tech or sighted users.

## Minor

- `SettingsView.vue:197` and `:316` `rounded-lg` occurrences predate the
  branch (`git blame` → `3efe1a4`, the base commit). Flagged only for
  completeness since they were the ones pointed at; this branch did not
  introduce either.
- The six deleted components (`SessionHeader.vue`, `SessionAttendanceGrid.vue`,
  `SessionCostSummary.vue`, `SessionPaymentTable.vue`,
  `SessionGroupPaymentBar.vue`, `MemberUnpaidSessionsModal.vue`) were already
  unreferenced dead code before this branch touched them —
  `git grep -n "<ComponentName>" 3efe1a4 -- src/` returns zero hits for all
  six at the base commit. `SessionDetailView.vue` already had its own inline
  reimplementation of attendance/cost/payment UI predating this branch. No
  reachable capability (including `MemberUnpaidSessionsModal`'s batch
  cash-payment flow) was lost by deleting them; they were unreachable
  already.
- `CourtBookingEditor.vue:218-228` remove-slot hover color
  (`hover:text-red-600`) vs. `ShuttleUsageEditor.vue:167`
  (`hover:text-red-500`) — same destructive-hover intent, different shade.
- `CourtBookingEditor` renders no "no courts yet" empty state (unlike
  `ShuttleUsageEditor.vue:107-109`'s `t('shuttle.empty')`), but this is
  currently unreachable in practice: `removeSlot` refuses to go below one
  booking (`CourtBookingEditor.vue:120-126`) and both call sites seed a
  default court when the list is empty (`CreateSessionView.vue:26-33`,
  `SessionDetailView.vue:449-456`). Noted because the two editors handle the
  same conceptual "zero rows" case with different code paths, not because
  it's currently visible to a user.
- `CreateSessionView.vue:135` page `<h1>` uses `leading-tight` instead of the
  declared `leading-[1.2]` used by every section heading elsewhere in the
  app (e.g. `CourtBookingEditor.vue:131`, `SessionDetailView.vue:992/1111/
  1206/1485/1679`). Predates the branch (`git blame` → `3efe1a4`); this is
  the top-level title of the page this branch rewrote, so it was a missed
  opportunity to fix rather than something introduced.
- No court slot shows a per-slot cost the way `ShuttleUsageEditor.vue:161-163`
  shows a per-row total (`shuttleTotal([row])`); `CourtBookingEditor` only
  totals at the whole-editor level. Minor asymmetry between the two "running
  total" treatments beyond what's already listed as Important.
