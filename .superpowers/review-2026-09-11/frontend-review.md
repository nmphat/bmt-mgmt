# Frontend correctness review — fix/phase0-security (3efe1a4..9f4a3c7)

Scope: state, data flow, timezones, arithmetic, error handling, race conditions, RPC/DB contract match. Styling/visual/spacing excluded (covered elsewhere).

## Critical

### 1. `saveSession()` is a non-transactional 3-step write with no rollback, and its own catch block hides the reason it failed
`src/views/SessionDetailView.vue:467-536`

`saveSession()` performs, sequentially: (a) conditionally `supabase.rpc('recreate_session_intervals', ...)` (line 492-497) — which deletes and rebuilds every `session_intervals` row and cascades a delete of all `interval_presence` (attendance) for the session server-side — then (b) `supabase.from('sessions').update(...)` (line 500-509), then (c) `supabase.rpc('set_session_court_bookings', ...)` (line 514-522). If (a) succeeds and (b) or (c) fails, the intervals have already been rebuilt and attendance already wiped, but the session's other fields and the court booking edits are never persisted — a half-applied write with no compensating action.

Worse, the catch block (line 528-532) discards the real error and always shows the generic `t('session.updateError')` toast:
```
} catch (error: any) {
    console.error('Error updating session:', error)
    const message = t.value('session.updateError')
    actionError.value = message
    toast.error(message)
}
```
Concrete repro: open "Edit Session" on an `open` session with existing registrations/attendance. Change the session end time (so `timesChanged` is true) and also clear one court's name field to blank (no `required` on that input, see finding 5). Click Save. `recreate_session_intervals` runs and wipes attendance; `set_session_court_bookings` then rejects with `Thiếu tên sân (court_name) trong dữ liệu đặt sân` (docs/sql-export/06_functions.sql:642-647); the admin sees only a generic "update failed" toast with no indication attendance was already destroyed and nothing else saved.

### 2. `fetchData()` unconditionally clobbers the open "Edit Session" form, and three independent triggers can fire it while that form is open
`src/views/SessionDetailView.vue:233-242`, raced by `838-858` (realtime) and `1655-1660` (ShuttleUsageEditor)

`fetchData()` — including the `refreshCostsOnly = true` path — always does:
```
if (normalizedSession) {
  sessionForm.value = {
    title: normalizedSession.title,
    status: normalizedSession.status,
    price_per_hour: normalizedSession.price_per_hour,
    court_fee_addon: normalizedSession.court_fee_addon,
    session_start: '',
    session_end: '',
  }
}
```
This runs with no guard on `isEditingSession`. Three things call `fetchData()`/`fetchData(true)` independently of the edit form: the realtime `postgres_changes` listeners on `interval_presence` and `session_registrations` (line 838-858, `() => fetchData(true)`), and `ShuttleUsageEditor`'s `@saved="fetchData()"` (line 1659) — and `ShuttleUsageEditor` is rendered whenever `session.status === 'open' && authStore.isAdmin` (line 1656), independent of `isEditingSession`, i.e. it's visible at the same time as the session edit panel.

Concrete repro: admin clicks the edit pencil (`startEditing()`), types a new title or price (unsaved), then — without clicking Save — toggles a member's attendance checkbox further down the same page (an ordinary workflow, and it doesn't even require a second user). That `interval_presence` write fires the realtime listener → `fetchData(true)` → `sessionForm.value` is reassigned from server data: the admin's typed title/price/court_fee_addon edits are silently discarded, and `session_start`/`session_end` are blanked to `''` while the edit panel stays open (`isEditingSession` isn't touched by `fetchData`). If the admin then hits Save without noticing, `` `${startDate}T${sessionForm.value.session_start}:00+07:00` `` becomes a malformed string, `new Date(...)` is `Invalid Date`, and `newEndUTC.toISOString()` throws inside the try block — caught by the same generic-message catch as finding 1.

### 3. `recreate_session_intervals` has no admin check, and RLS grants full write access to any authenticated user
`docs/sql-export/06_functions.sql:846-889`, `docs/sql-export/08_rls.sql:29-31,49-51`

Unlike every sibling RPC touched by this branch — `set_session_court_bookings` (06_functions.sql:621-625), `set_session_shuttle_usage` (673-677), `remove_member_from_session`, `finalize_session` — which all `RAISE EXCEPTION 'Chỉ admin được thực hiện thao tác này'` for a non-admin caller, `recreate_session_intervals` is `SECURITY INVOKER` with no role check at all. `session_intervals` and `interval_presence` both carry `"Auth users full access ..." FOR ALL TO authenticated USING (true)` policies (08_rls.sql:29-31, 49-51). Any authenticated club member (not just an admin) can call `supabase.rpc('recreate_session_intervals', {...})` directly — e.g. from the browser console while logged in as a regular member — and delete + rebuild any session's intervals, wiping all attendance for it, completely bypassing the client's `authStore.isAdmin` / `isSessionEditable` gate (SessionDetailView.vue:179, 468). This branch reactivates the client call site for this RPC (line 492, previously only reachable through the now-deleted `SessionHeader.vue`), so the gap is live again in a fresh feature.

## Important

### 4. Cross-midnight sessions/bookings are not actually supported, contrary to the branch's own comment
- `src/views/CreateSessionView.vue:62-73`: `startDateTime`/`endDateTime` both use the SAME `form.value.date`, so `startDateTime.value >= endDateTime.value` rejects any session whose end clock-time is earlier than its start (e.g. 22:00 → 00:30) — there is no way to create an overnight session at all.
- `src/components/session/CourtBookingEditor.vue:56-62` (`isEndBeforeStart`, `isOutOfBounds`) compare raw `"HH:mm"` strings with no day-rollover awareness: any booking row that itself spans midnight is always flagged invalid, and a booking entirely after local midnight but within a (hypothetically) cross-midnight session's bounds (session 22:00→01:00, booking 00:00→00:30) is wrongly flagged "out of bounds" since `"00:00" < "22:00"` lexicographically.
- `src/views/SessionDetailView.vue:518-519` stamps BOTH `start_time` and `end_time` of every court booking with `startDate` only, never `endDate` — inconsistent with the session-level computation four lines above (479-480) which correctly differentiates `startDate`/`endDate`. This is a latent day-attribution bug for any booking that would legitimately fall on the session's end-side calendar date.
- `src/utils/courtCost.ts:10-15` `courtTotal()` silently contributes $0 for any booking whose HH:mm-only `hours` computes to ≤ 0 — exactly what a cross-midnight booking produces — so even if one were ever persisted, the client preview would silently undercount it. Confirmed uncoverered: removing the `hours > 0` guard entirely (`return sum + b.price_per_hour * hours`) still passes all 12 `courtTotal`/`findOverlaps` tests unmodified.

None of this currently corrupts data — every entry point independently blocks the scenario before persistence — but the inline comment at SessionDetailView.vue:474 ("Compute UTC start/end from VN HH:mm — use separate dates so cross-midnight works") is misleading: the two-date computation it introduces only changes behavior for a state (a session whose start/end already sit on two different VN calendar dates) that no code path in the app can ever create.

### 5. `saveSession()`'s generic error swallows genuinely actionable RPC messages, and nothing stops the blank input that triggers them
`src/views/SessionDetailView.vue:528-532` vs. `src/views/CreateSessionView.vue:113-115` and `src/components/session/ShuttleUsageEditor.vue:91-92`

`CreateSessionView.createSession()` and `ShuttleUsageEditor.handleSave()` both surface `error.message` in their toast. `SessionDetailView.saveSession()` does not — it always shows `t('session.updateError')` (see finding 1). This matters because `CourtBookingEditor.vue`'s court-name `<input>` (lines 144-151) has no `required` attribute, and `isValid` (lines 71-75) never checks for a blank `court_name`, so a user can clear a court name and still have the Save button enabled. The server correctly rejects it with a clear Vietnamese message (`Thiếu tên sân (court_name) trong dữ liệu đặt sân`, 06_functions.sql:646), but `saveSession()` throws that message away.

The same gap exists in `CreateSessionView.vue` in the opposite direction: `create_session_with_bookings` (06_functions.sql:589-604) only `COALESCE`s a `NULL` `court_name` to `'Sân 1'`, not an empty string, so a blank name reaches the `session_court_bookings_court_name_not_blank` CHECK constraint (`docs/sql-export/03_constraints.sql:34`) and surfaces as a raw Postgres constraint-violation string via `toast.error(error.message || ...)` (CreateSessionView.vue:115) — the opposite failure mode (too raw, not too generic), but the same root cause: no client-side check for a blank court name before submit.

### 6. `ShuttleUsageEditor`'s "used" input has no NaN guard, unlike the analogous price input
`src/components/session/ShuttleUsageEditor.vue:147-149` vs. `src/components/session/CourtBookingEditor.vue:211-215`

```
@change="
  rows[i]!.used = Math.max(0, Number(($event.target as HTMLInputElement).value))
"
```
has no `|| 0` fallback, while the court price input does: `Math.max(0, Number(...) || 0)`. Entering/pasting a non-numeric value into a "used" field sets `row.used = NaN`. `shuttleTotal()` (`src/utils/courtCost.ts:46-52`) reduces over the array, so one `NaN` term contaminates the running sum for every subsequent entry; `formatCurrency` (src/utils/formatters.ts:12-14) masks `NaN` as `0`, so the grand total silently displays `0 ₫` even when other rows carry real non-zero usage. On Save, `JSON.stringify({used: NaN})` serializes to `{"used": null}` (verified: `Math.max(0, Number('abc'))` → `NaN` → `JSON.stringify` → `null`), which the server does reject with a specific message (06_functions.sql:693-695) — so no bad data is written, but the on-screen total is wrong before the user ever gets that far, and the `courtCost.test.ts`/`ShuttleUsageEditor.test.ts` suites never exercise a non-numeric "used" input.

### 7. No confirmation before the attendance-destroying interval rebuild
`src/views/SessionDetailView.vue:344-349` (warning banner), `459-465` (`timesChanged`), `487-498` (unconditional `recreate_session_intervals` call)

`timesChanged` only renders a static red banner ("session.intervalsResetWarning") while the edit form is open; it does not block or require a second confirmation before Save actually calls `recreate_session_intervals`, which deletes all `interval_presence` for the session (docs/sql-export/06_functions.sql:855-859). Combined with finding 2 (a background `fetchData()` can blank the time fields while the form is open) and the fact that `timesChanged` compares against `toVNHHmm(session.value.start_time)` — a value that can itself go stale if a realtime refresh lands mid-edit — a single Save click is enough to irreversibly destroy attendance with only a passive, easy-to-miss banner as warning.

## Minor

### 8. Adding a shuttle row when the catalogue is empty silently does nothing
`src/components/session/ShuttleUsageEditor.vue:44-46`
```
function addRow() {
  const first = activeTypes.value[0]
  if (!first) return
  ...
}
```
If `activeTypes` is empty (no shuttle types configured yet, or all inactive), clicking "add" gives no feedback at all — no toast, no disabled state on the button.

### 9. Two new i18n keys ship unused
`pnpm i18n:audit` reports `shuttle.addType` and `shuttle.used` (both added by this branch, confirmed via `git log -p -S"addType" -- src/locales/messages.ts`) as unused. `shuttle.used` in particular looks like it was meant to label the quantity input in `ShuttleUsageEditor.vue` (~line 140-150), which currently has no visible `<label>` for that field at all.

### 10. `formatTime` (pre-existing, untouched by this branch) is not timezone-safe, and now coexists with a correct sibling
`src/views/SessionDetailView.vue:701-703`
```
const formatTime = (isoString: string) => {
  return format(new Date(isoString), 'HH:mm')
}
```
uses `date-fns`'s `format`, which renders in the browser's local timezone, not Vietnam. This branch adds a correct alternative, `toVNHHmm()` (line 430-434, hardcoded UTC+7), for the edit-form conversions, but `formatTime` is still used for the interval grid and session time range display (lines 752, 1362, 1370, 1406). If an admin's browser isn't set to `Asia/Ho_Chi_Minh`, the displayed court/interval times would be wrong while the edit-form's own times would not — the branch's timezone fix commit (9f4a3c7) didn't reach this site.
