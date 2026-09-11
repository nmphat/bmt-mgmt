# Review consolidation — branch `fix/phase0-security`, range 3efe1a4..9f4a3c7
Date: 2026-09-11. Four reviews: `db-review.md`, `ui-review.md`, `frontend-review.md`, `controller-findings.md`.

## Baseline is green, and that is the problem

`pnpm type-check` clean. `pnpm vitest run` 29/29. `./db-tests/run.sh` 10/10. `pnpm i18n:audit` MISSING 0, both languages in sync. Production money parity: 0 mismatched rows across all 266 snapshots, 0 VND drift. Export and production agree exactly, including the three migrations already applied.

Every gate this branch built passes. The defects below all sit in the gaps between those gates.

## Blocks merge — money is lost silently

### B1. Editing a session's time zeroes all court money
`06_functions.sql:887` (`recreate_session_intervals`) and `:912-920` (`refresh_interval_courts`).

Reproduced by the controller in the container:

    session 11:00-12:00, one court @120000/h
    BEFORE: intervals=2  sum(court_cost)=120000
    recreate_session_intervals(sid, 12:00, 13:00)
    AFTER : intervals=2  sum(court_cost)=0
    bookings untouched: 1, still at 11:00

No error. Everyone is billed 0 for the court. `refresh_interval_courts` credits only bookings that overlap the *current* window, and the time edit does not move the bookings.

This is a regression introduced by this branch. Before it, court money lived in `sessions.court_fee_addon`, which survives a time edit. Moving the money into `session_court_bookings` made it dependent on a window the admin can change from the UI — `SessionDetailView.vue:492` and `:514` are two separate transactions.

### B2. A session created with the shipped defaults bills everyone 0
`CreateSessionView.vue:98` hardcodes `p_price_per_hour: 0`; `:219` passes `:default-price="0"`; `:23` defaults the addon to 0. Nothing requires a non-zero price: not the column (`02_tables.sql:104`), not `set_session_court_bookings` (`:657`), not `create_session_with_bookings` (`:598`), not `CourtBookingEditor`'s `isValid`.

Reproduced by the controller with exactly the payload the UI sends:

    engine says: member A total=0, member B total=0
    finalize_session -> snapshot rows written: 0
    session status now: waiting_for_payment

`finalize_session:752` skips members whose `final_total = 0`, so the session reports as finalized with nobody owing anything and no QR minted. That is the default shape of every new session unless the admin remembers to type a price into each slot.

### B3. Mixed pricing runs two money models in one session
`06_functions.sql:287-288` picks the per-interval branch on `court_cost > 0`, which cannot distinguish "this court is free" from "nobody entered a price". Session 10:00-12:00, `price_per_hour=100000`, court 1 @120000 for the first hour, court 2 @0 for the second: real spend 120000, engine charges 220000. With `price_per_hour=0` the same shape undercharges to 0 for the second hour.

### B4. `saveSession` is three writes with no rollback
`SessionDetailView.vue:467-536`: `recreate_session_intervals`, then `sessions.update`, then `set_session_court_bookings`, sequentially, uncoordinated. A failure in the middle leaves attendance already destroyed and the rest abandoned. The catch at `:528-532` throws away the real error and shows a generic toast, so the admin cannot tell what happened. `:518-519` builds both booking timestamps from `startDate`, which guarantees step 3 fails for any cross-midnight session — the cross-midnight fix in 9f4a3c7 reached `:479-480` and not this mapping.

## Important

### Server-side validation missing where the client is the only guard
- **`set_session_court_bookings(sid, NULL)` or `'[]'` deletes every booking and zeroes the session.** All four guards at `:641-658` pass vacuously and the `DELETE` at `:649` still runs. The sibling `set_session_shuttle_usage(sid, NULL)` fails loudly; the money-bearing one is the permissive one.
- **Overlapping bookings double-charge.** Two identical bookings on one court bill 240000 for one hour. Overlap is checked only in `src/utils/courtCost.ts`. No server check, and test 12 never sends an overlapping payload.
- **Negative `tube_price` accepted** by `set_session_shuttle_usage`: `shuttle_fee_total = -78750` and members' shuttle fee goes negative.
- **Constraint violations reach the user raw.** The new `end_time > start_time` CHECK and the blank-`court_name` CHECK have no matching RPC validation, so `CreateSessionView.vue:113` prints English SQLSTATE 23514 text. `create_session_with_bookings` has neither guard; `COALESCE` at `:595` only catches NULL, so an empty string from `renameCourt` reaches the CHECK.

### Six mutations that leave all ten db-test files green
Each of these is a silent hole in the suite, not a bug in the code:
1. `ALTER COLUMN court_name DROP NOT NULL` — and the CHECK cannot cover it, because `court_name ~ '\S'` is NULL for NULL and therefore passes.
2. `create_session_with_bookings` discarding every submitted `price_per_hour` — it is the only creation path and has no test at all.
3. Deleting `PERFORM refresh_interval_courts` from `recreate_session_intervals:887`.
4. Reverting `view_session_summary.total_court_cost` to the pre-branch expression — the session list would show 0 for every per-court-priced session.
5. `RESET search_path` on the three new RPCs.
6. `SECURITY INVOKER` on the three new RPCs.

`drift-check.sql` would catch 5 and 6 — it reads the raw `proacl` correctly — but it is not wired into `run.sh`, and `db-tests/drift/prod.txt` is a stale pre-branch 119-line snapshot against 217 local rows.

### Privilege gaps (defence-in-depth, not exploitable today)
`create_session_with_bookings` (8-arg) and `recreate_session_intervals` are still `SECURITY INVOKER` with `anon` EXECUTE, while the three RPCs this branch created got `SECURITY DEFINER` + `SET search_path` + `REVOKE ... FROM PUBLIC, anon`. `recreate_session_intervals` also has no admin check, and `session_intervals` / `interval_presence` RLS grants full write to any authenticated user — so any signed-in member, not just an admin, can rebuild a session's intervals and wipe attendance.

Probed on production as the real `anon` role, inside a rolled-back transaction: session created 0, intervals deleted 0, courts repriced 0, shuttle totals zeroed 0, shuttle types repriced 0. RLS holds. But that is one layer, and it is the layer Phase 0 just rewrote. Same family as Phase 0's finding I1, same fix: revokes only, no body change.

### UI
- **Both "add shuttle type" buttons render the wrong label.** `ShuttleUsageEditor.vue:184` and `SettingsView.vue:346` call `t('shuttle.type')` ("Loại cầu") where the correct key `shuttle.addType` ("Thêm loại cầu") exists, was added in the same commit, and is unused.
- **Four hardcoded strings bypass `t()`** and are therefore invisible to `i18n:audit`, which only compares the catalogue: `SettingsView.vue:411` (`'Active'/'Inactive'`), `ShuttleUsageEditor.vue:92` and `SettingsView.vue:145` (English toast fallbacks), `CreateSessionView.vue:200` (literal `(VND)`, shown in the Vietnamese UI).
- **The two new editors disagree on their persistence model.** `CourtBookingEditor` is a pure `v-model` child the parent saves; `ShuttleUsageEditor` calls its own RPC, raises its own toast, and offers no cancel. They sit on the same screen. They also diverge on heading level, running-total layout, remove-icon language (`Trash2` versus `&times;`), and disabled-state handling.
- **`fetchData()` blows away an open edit form.** `SessionDetailView.vue:233-242` resets the form unconditionally, and three independent triggers can fire it while the admin is typing: realtime listeners on `interval_presence` and `session_registrations` (`:838-858`) and `ShuttleUsageEditor`'s `@saved="fetchData()"` (`:1659`).
- **No confirmation before the attendance-destroying interval rebuild.** There is a warning banner (`session.intervalsResetWarning`), but the destructive step runs on Save with no second gate.
- Smaller: the shuttle quantity input has no NaN guard where its price sibling does (`JSON.stringify({used: NaN})` yields `{"used": null}`); the toggle-active button has no `min-h-11`, `aria-label` or focus outline; new time inputs at `:1031-1046` copy the old `rounded-md` style next to the new editor; `SettingsView.vue:341` copies a stale `rounded-lg` neighbour.

## Confirmed non-issues — do not re-open
- **`shuttle_types` has no anon policy, and that is correct.** `/session/:id` has no route guard, so guests reach it, but `ShuttleUsageEditor` renders under `v-if="status === 'open' && isAdmin"` and nothing else reads the table. Guests read the frozen `shuttle_usage` and `shuttle_fee_total` on `sessions`.
- **Export and migrations agree exactly.** A second container built from the pre-branch export plus the three migrations diffed 0 lines against the branch-export container across every function body, column, constraint, policy, ACL, view, index and trigger.
- **The six deleted components were already dead** at the base commit — verified by `git grep` at 3efe1a4. No capability was lost.
- **`rounded-lg` at `SettingsView.vue:197` and `:316` predates the branch** (`git blame` against 3efe1a4). Only `:341` is new.

## Recommended order

1. B1 and B2 first — they lose money with no error and B2 is the default path.
2. B4, then the missing server-side validation (NULL/empty payload, overlap, negative tube price, Vietnamese messages for both CHECKs).
3. The two wrong i18n labels and four hardcoded strings — minutes of work, visible on every screen.
4. The six green mutations: add the covering tests, and wire `drift-check.sql` into `run.sh` with a refreshed `prod.txt`.
5. B3's ambiguity needs a product decision before it can be coded: is `price_per_hour = 0` on a slot a free court or an unfilled field? Everything else follows from the answer.
6. The privilege gaps and the editor-consistency work.
