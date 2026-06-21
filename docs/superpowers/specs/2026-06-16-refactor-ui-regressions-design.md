# Design: Fix UI Refactor Regressions

**Date:** 2026-06-16
**Scope:** 4 regressions introduced during v1.0 UI refactor (PR #2)
**Branch:** `fix/refactor-ui-regressions`
**Strategy:** 1 PR, 4 commits (1 per issue)

---

## Issue #1: CreateSession — Court Booking UI Missing

### Problem
`CreateSessionView.vue` hardcodes a single court booking:
```js
p_bookings: [{ court_name: 'Sân 1', start_time: startTime, end_time: endTime }]
```
Docs (`07-ui-ux-design.md`) specify a "Danh sách sân" section with add/remove courts. The `SessionHeader.vue` already has complete court booking edit UI with validation — but only for editing existing sessions.

### Design
Reuse the booking pattern from `SessionHeader.vue` (lines 52-179):
- `bookings` ref array with `court_name`, `start_time`, `end_time`
- Default: 1 court pre-filled with session times
- Add court button: appends new court with session defaults
- Remove court button: disabled when only 1 court remains
- Validation: court time must be within session time window, end > start
- Pass bookings array to `create_session_with_bookings` RPC's `p_bookings` param

### Files Changed
- `src/views/CreateSessionView.vue` — add booking UI + logic

### i18n
Reuse existing keys from SessionHeader:
- `createSession.addCourt`
- `createSession.courtName`
- `createSession.courtEndTimeError`
- `createSession.courtTimeError`
- `createSession.courtAdded`

---

## Issue #2: Navigate to Session Detail After Create

### Problem
After creating a session, `router.push('/')` sends admin to Home. Expected: navigate to the new session's detail page so admin can immediately add members.

### Design
- `create_session_with_bookings` RPC returns the new session UUID
- Change: `const { data: sessionId, error } = await supabase.rpc(...)`
- Navigate: `router.push({ name: 'session-detail', params: { id: sessionId }, query: { register: 'true' } })`
- The `?register=true` query param triggers Issue #3
- Guard: `if (!sessionId) { toast.error(...); return; }` before navigate

### Files Changed
- `src/views/CreateSessionView.vue` — change `router.push('/')` to session detail

---

## Issue #3: Auto-Open Member Registration Dropdown

### Problem
`SessionDetailView.vue` builds the member dropdown inline (line 53: `showMemberDropdown` ref, line 1080: toggle button). There is no component extraction — the `autoOpenMemberDropdown` prop in `SessionAttendanceGrid.vue` is an orphan from a different code path.

### Design
- `SessionDetailView.vue` reads `route.query.register === 'true'` in `onMounted`
- If `register === 'true'` AND session is `open` AND user is admin → set `showMemberDropdown.value = true`
- After data loads, strip query param: `router.replace({ name: route.name, params: route.params })`
- Uses `router.replace()` (not `router.push()`) to avoid adding history entry

### Files Changed
- `src/views/SessionDetailView.vue` — read query param, set inline ref, clean URL

---

## Issue #4: Breadcrumb Back Navigation

### Problem
Both `CreateSessionView.vue` and `SessionHeader.vue` hardcode `<router-link to="/">` for the back button. Should navigate to the previous page.

### Design

**CreateSessionView** (few entry points — query param approach):
- Read `route.query.from` to determine source page
- Label mapping: `sessions` → "Danh sách buổi", `home` → "Trang chủ", default → "Trang chủ"
- Click: `router.push(fromRoute)` if `from` param exists, else `router.back()`
- Update entry points to pass `?from=`:
  - `DashboardView.vue` line 71: `<router-link to="/create-session?from=sessions">`
  - `HomePage.vue`: quick action button (if exists)

**SessionHeader** (many entry points — router.back approach):
- Replace `<router-link to="/">` with `<button @click="goBack">`
- `const goBack = () => router.back()` — Vue Router handles back navigation
- Fallback: if `router.back()` doesn't navigate (no history), Vue Router stays on same page — use `router.push('/sessions')` as fallback after a tick
- Simpler approach: `router.back()` unconditionally; browser handles no-op if no history
- Label: generic `common.back` = "Quay lại" / "Back"

### Files Changed
- `src/views/CreateSessionView.vue` — dynamic back link
- `src/components/session/SessionHeader.vue` — router.back() button
- `src/views/DashboardView.vue` — pass `?from=sessions` to create-session link

### i18n
- `common.backToSessions` = "Quay lại Danh sách buổi" / "Back to Sessions"
- `common.back` = "Quay lại" / "Back"

---

## Commit Strategy

| # | Commit Message | Files |
|---|---------------|-------|
| 1 | `feat(session): restore court booking UI in create form` | CreateSessionView.vue |
| 2 | `feat(session): navigate to session detail + auto-open dropdown after create` | CreateSessionView.vue, SessionDetailView.vue |
| 3 | `fix(nav): breadcrumb back uses history, not hardcoded home` | CreateSessionView.vue, SessionHeader.vue, DashboardView.vue |

Note: Commits 2+3 both touch CreateSessionView.vue — accepted since they modify different sections (RPC call vs breadcrumb). Commit 2 merges original issues #2 and #3 for cleaner separation.

## i18n Files

New keys to add in `src/locales/messages.ts`:
- `common.backToSessions` — "Quay lại Danh sách buổi" / "Back to Sessions"
- `common.back` — "Quay lại" / "Back"

---

## Verification

1. `pnpm type-check` — no type errors
2. `pnpm build` — clean build
3. Manual smoke test:
   - Create session with 2 courts → verify bookings in DB
   - After create → lands on session detail with dropdown open
   - Back button from create-session → goes to dashboard
   - Back button from session detail → goes to previous page
