# DB review — `fix/phase0-security` @ 9f4a3c7 (range 3efe1a4..9f4a3c7)

Method: every finding below was reproduced in the local `bmt-test` Postgres 17 container built
by `db-tests/up.sh` from `docs/sql-export/*.sql`. Test claims were checked by mutation: break the
thing the test names, reload into the container, re-run all ten files, record red/green. The repo
was left unmodified (`git status` clean apart from this directory); the container was rebuilt with
`up.sh` afterwards and all ten files pass. No statement was run against production.

---

## Critical

### C1. Editing a session's time silently zeroes every dong of court money
`docs/sql-export/06_functions.sql:846-889` (`recreate_session_intervals`, `PERFORM` at `:887`)
against `06_functions.sql:891-926` (`refresh_interval_courts`, overlap predicate at `:912-920`).

Before this branch the court money lived in `sessions.court_fee_addon`, which
`recreate_session_intervals` never touches. This branch moved the money into
`session_court_bookings.price_per_hour`, and `refresh_interval_courts` only credits bookings that
overlap the *current* interval window. `recreate_session_intervals` rewrites the window and leaves
the bookings where they were, so a time edit throws the whole court bill away.

Constructed case (container):

```
session 11:00-12:00, one booking "Sân 1" 11:00-12:00 @ 120000/h
  sum(session_intervals.court_cost) = 120000
SELECT recreate_session_intervals(sid, '2026-09-01 12:00+00', '2026-09-01 13:00+00');
  sum(session_intervals.court_cost) = 0        <-- all court money gone, no error
  calculate_session_costs -> total_court_fee 0 for every member
```

The same session shaped the legacy way (money in `court_fee_addon`, bookings outside the window)
keeps charging 60000/head after the identical edit — so this is a regression introduced by moving
the money, not pre-existing behaviour.

Reachable from the UI, not only from SQL. `src/views/SessionDetailView.vue:492` calls
`recreate_session_intervals`, then `:514` calls `set_session_court_bookings` — two separate
PostgREST requests, two separate transactions, no compensating action. Anything that fails between
them (network, the constraint violation in I3, a closed tab) commits step 1 and leaves the session
priced at zero. `src/views/SessionDetailView.vue:518-519` guarantees such a failure for a
cross-midnight session: both `start_time` and `end_time` of every booking are built from
`startDate`, so a 22:00→00:30 session produces `end_time < start_time` and trips
`session_court_bookings_time_order_check`. (Commit 9f4a3c7's cross-midnight fix reached `:479-480`,
the session recreate, but not the booking mapping eight lines below.)

### C2. A session created with the shipped UI defaults bills everyone 0 and finalizes with zero snapshot rows
`06_functions.sql:287-288` (the `court_cost > 0` CASE) + `:598` and `:603-605`
(`create_session_with_bookings`) + `:752` (`finalize_session`'s `IF r.final_total > 0`).

Nothing anywhere requires a court price to be non-zero: not the column
(`02_tables.sql:104`, `NOT NULL DEFAULT 0`), not `set_session_court_bookings`
(`06_functions.sql:657`, `COALESCE(...,0)`), not `create_session_with_bookings`
(`06_functions.sql:598`, same), and not the client — `src/views/CreateSessionView.vue:98` hardcodes
`p_price_per_hour: 0`, `:219` passes `:default-price="0"` to the editor, and `:23` defaults
`courtFee` (the addon) to 0. `CourtBookingEditor.vue:72-76` validates overlap, ordering and bounds
but never price. So the "forgot to type the prices" session is the *default* shape of every session
this branch creates.

Constructed case (container):

```
create_session_with_bookings('UI defaults', 10:00, 11:00, p_price_per_hour := 0,
  p_bookings := '[{"court_name":"Sân 1", 10:00-11:00, "price_per_hour":0}]', p_court_fee_addon := 0)
two members registered and present in both intervals

calculate_session_costs      -> Member A 0, Member B 0
view_session_summary         -> total_court_cost 0
finalize_session(sid)        -> 0 rows in session_costs_snapshot
sessions.status              -> 'waiting_for_payment'
```

The session reaches `waiting_for_payment` with nobody owing anything and no row to chase. Because
`finalize_session:752` skips `final_total = 0`, there is not even an empty debt row to notice.
Passing `p_bookings := NULL` reaches the same place through `:603-605`, which inserts a default
`'Sân 1 (Mặc định)'` booking at price 0.

Answering the brief's question directly: `price_per_hour = 0` **and** `court_cost = 0` is
indistinguishable from a genuinely free session, and the system treats it as free, silently.

### C3. Mixed pricing runs two different money models inside one session
`06_functions.sql:287-288`:

```sql
WHEN ist.court_cost > 0 THEN ist.court_cost
ELSE (v_price_per_hour / 2.0) * ist.active_court_count
```

The branch is chosen **per interval**, on a value that is 0 both when a court is genuinely free and
when the admin did not enter a price. There is no session-level "this session uses per-court
pricing" signal, so one 0-priced booking silently reverts that slot to the legacy hourly formula.

Constructed case (container), over-charge direction:

```
session 10:00-12:00, sessions.price_per_hour = 100000
  booking Sân 1 10:00-11:00 @ 120000/h
  booking Sân 2 11:00-12:00 @ 0        (price left blank)
intervals court_cost: 60000, 60000, 0, 0
calculate_session_costs -> Member A 110000, Member B 110000  (total 220000)
actual court spend      -> 120000
```

100000 VND of legacy hourly rate is invented for the hour whose booking says it costs nothing.
The same shape with `price_per_hour = 0` — i.e. every session this branch's UI creates
(`CreateSessionView.vue:98`) — under-charges instead: the second hour bills 0 and the club eats it.

---

## Important

### I1. `set_session_court_bookings(sid, NULL)` and `(sid, '[]')` silently delete every booking and zero the session
`06_functions.sql:641-658`. `jsonb_array_elements(NULL)` returns zero rows, so all four guards pass
vacuously, the unconditional `DELETE` at `:649` runs, the `INSERT ... SELECT` at `:651-658` inserts
nothing, and `:660`'s refresh writes `court_cost = 0` across the session.

```
starting state: 1 booking @120000/h, sum(court_cost) = 120000
SELECT set_session_court_bookings(sid, NULL);   -- returns void, no error
  bookings = 0, sum(court_cost) = 0
SELECT set_session_court_bookings(sid, '[]'::jsonb);  -- same result
```

The sibling RPC disagrees: `set_session_shuttle_usage(sid, NULL)` fails loudly on
`sessions.shuttle_usage`'s NOT NULL (`02_tables.sql:44`). Two RPCs written in the same commit
handle a null payload in opposite ways, and the money-bearing one is the permissive one.

### I2. Two overlapping bookings on the same court double-charge; the only guard is client-side
`06_functions.sql:612-661` has no overlap check. `src/utils/courtCost.ts:23-39` (`findOverlaps`) is
the only thing that stops it, and it runs in the browser.

```
SELECT set_session_court_bookings(sid,
  '[{"court_name":"Sân 1", 11:00-12:00, 120000},
    {"court_name":"Sân 1", 11:00-12:00, 120000}]');
intervals: active_court_count 2, 2 ; court_cost 120000, 120000
  -> one court for one hour at 120000/h billed as 240000
```

`db-tests/12_set_court_bookings.test.sql` never sends an overlapping payload, so the server side of
the rule the frontend enforces is unverified and, in fact, absent.

### I3. The new `end_time > start_time` constraint has no matching RPC guard — callers get a raw English 23514
`03_constraints.sql:33` added the CHECK; `06_functions.sql:612-661` validates `court_name`
(`:641-647`, Vietnamese message) but not the time order. Point 7 of the brief asks specifically for
the matching validation; it is missing for this constraint and for `create_session_with_bookings`
entirely.

```
SELECT set_session_court_bookings(sid,
  '[{"court_name":"Sân 1","start_time":"...T12:00Z","end_time":"...T11:00Z","price_per_hour":120000}]');
ERROR:  new row for relation "session_court_bookings" violates check constraint
        "session_court_bookings_time_order_check"
```

`create_session_with_bookings` is worse, because `src/views/CreateSessionView.vue:113` surfaces
`error.message` verbatim to the user. Two constructed cases both hit the raw constraint text:

```
create_session_with_bookings(..., '[{"court_name":"", ...}]')
  ERROR: violates check constraint "session_court_bookings_court_name_not_blank"
create_session_with_bookings(..., '[{"court_name":"Sân 1","start_time":11:00,"end_time":10:00}]')
  ERROR: violates check constraint "session_court_bookings_time_order_check"
```

The empty-string case is reachable from the UI: `CourtBookingEditor.vue:83-88` (`renameCourt`) lets
the admin clear a court-name field, and `isValid` (`:72-76`) does not check the name. The `COALESCE`
at `06_functions.sql:595` only falls back to `'Sân 1'` on NULL, not on `''` — a gap the comment in
`db-tests/12_set_court_bookings.test.sql:230-236` explicitly notes but nothing fixes.

### I4. `court_name NOT NULL` — the headline of commits be61fb7/a51b0b7 — is not covered by any test
Mutation: `ALTER TABLE session_court_bookings ALTER COLUMN court_name DROP NOT NULL;`
→ **all ten test files stay green.**

The CHECK cannot substitute for it: `court_name ~ '\S'` evaluates to NULL for a NULL name, and a
CHECK that is NULL passes. Proof in container (blank-CHECK kept, NOT NULL dropped):

```
INSERT INTO session_court_bookings(session_id, court_name, ...) VALUES (..., NULL, ...);
  -> accepted; 1 row with court_name IS NULL
```

`db-tests/12_set_court_bookings.test.sql` covers the *RPC guard* against a missing key and the
*CHECK* against whitespace, but never the column constraint against a literal NULL — which is the
only thing standing behind `create_session_with_bookings` and any direct PostgREST insert.

### I5. `create_session_with_bookings` — the only remaining session-creation path — has no test at all
Mutation: replace `COALESCE((v_booking_item->>'price_per_hour')::numeric, 0)` at
`06_functions.sql:598` with `0::numeric`, i.e. discard every per-booking price the client sends
→ **all ten test files stay green.**

Every session the app creates would be created free and the suite would not notice. The 7-argument
overload was dropped this branch, so this function is now the single creation path and it is
unreferenced by `db-tests/*` (only a comment mentions it).

Secondary, same function: it is the odd one out on guards. `set_session_court_bookings` and
`set_session_shuttle_usage` are `SECURITY DEFINER`, `SET search_path = public, pg_temp`, admin-checked
and revoked from `PUBLIC, anon`; `create_session_with_bookings` writes the same two tables while
being `SECURITY INVOKER`, guard-free, and still holding `=X/postgres` + `anon=X/postgres` in its
`proacl`. It is not currently exploitable — verified in the container that both `anon` and a
non-admin `authenticated` member are stopped by RLS ("new row violates row-level security policy"
on `sessions` and on `session_court_bookings` respectively) — but its entire defence is one RLS
policy, and the branch's own stated policy is not to rest on that.

### I6. `recreate_session_intervals` losing its court refresh is invisible to the suite
Mutation: delete `PERFORM refresh_interval_courts(p_session_id);` at `06_functions.sql:887`
→ **all ten test files stay green.**

This is the exact line that keeps `court_cost` consistent after a time edit — the mechanism whose
*other* failure mode is C1. Nothing pins it.

### I7. The `view_session_summary.total_court_cost` fix (commit 5665cbc) is untested
Mutation: restore the pre-branch expression (drop the `CASE WHEN si.court_cost > 0` at
`05_views.sql:55-58`, back to `si.active_court_count * s.price_per_hour / 2`)
→ **all ten test files stay green.**

With the old expression every per-court-priced session (all of which have `price_per_hour = 0`)
reports `total_court_cost = 0` in the sessions list and in `search_sessions_list`, while
`calculate_session_costs` correctly charges members — a list showing 0 for sessions that cost
120000. Verified the current expression does agree with the engine (`view` 120000 vs
`sum(total_court_fee)` 120000 on a 120000/h session), but nothing holds it there.

### I8. `set_session_shuttle_usage` rejects five bad shapes and accepts a negative price
`06_functions.sql:693-707` guards missing `used`/`tube_price`/`per_tube`, negative `used` and
`per_tube <= 0`. It does not guard a negative `tube_price`, which is the same class of silent
money-subtraction the other guards exist to prevent.

```
SELECT set_session_shuttle_usage(sid, '[{"name":"Vina","tube_price":-315000,"per_tube":12,"used":3}]');
  sessions.shuttle_fee_total = -78750
  calculate_session_costs -> total_shuttle_fee -52500 / -26250, final_total 148000 / 74000
```

Related, lower severity: a non-array payload (`'{"used":1}'`) escapes as a raw
`cannot extract elements from an object`, and junk keys plus string-typed numbers
(`{"used":"3","tube_price":"315000","garbage":"<script>"}`) are stored verbatim in
`sessions.shuttle_usage`, which anon can read (`08_rls.sql:66-68` on `sessions`).

### I9. The suite does not pin `SECURITY DEFINER` or `SET search_path` on the new RPCs
Two mutations, each leaving **all ten files green**:
- `ALTER FUNCTION ... RESET search_path` on `set_session_court_bookings`,
  `set_session_shuttle_usage`, `refresh_interval_courts`
- `ALTER FUNCTION ... SECURITY INVOKER` on the same three

`db-tests/drift-check.sql:42-49` *does* capture `secdef`, `proconfig` and a body hash, and
`:65-72` captures the raw `proacl` (correctly, rather than `has_function_privilege`) — but
`drift-check.sh` is a manual two-sided diff against a saved production snapshot, not part of
`run.sh`. `db-tests/drift/prod.txt` is 119 lines against `local.txt`'s 217 and contains no
`shuttle_types`, no `court_cost` and none of the new RPCs, i.e. it is a pre-branch capture; the
drift gate would currently produce an unreadable diff rather than a signal.

---

## Minor

### M1. Booking time outside the session window is clipped and the money is dropped without a word
`06_functions.sql:917` (`LEAST`/`GREATEST`). Session 11:00-12:00, booking 11:00-13:00 @120000/h
(the club pays for two hours) captures 120000 of 240000. `CourtBookingEditor.vue:60-62`
(`isOutOfBounds`) blocks this in the browser; `set_session_court_bookings` accepts it. Defensible
as "members pay for the session window", but the discrepancy is invisible everywhere in the UI.

### M2. `sessions.price_per_hour` is nullable and NULL silently produces a free session
`02_tables.sql:41` (`price_per_hour numeric DEFAULT 0`, nullable). With no per-court price,
`06_functions.sql:288` evaluates `(NULL / 2.0) * count` → NULL, `SUM` skips it, and every member
owes 0. `db-tests/11_calc_with_court_cost.test.sql:13-20` notes production has no NULL today, but
the column permits it and `SessionDetailView.vue:505` writes `sessionForm.price_per_hour` straight
through from a `v-model.number` field that yields no value when cleared.

### M3. `shuttle_types` DELETE is never exercised by `13_shuttle_usage.test.sql`
The file covers anon read, non-admin INSERT/UPDATE and admin INSERT/UPDATE, but not DELETE.
Independently verified in the container via `login_as` + `assert_denied` (non-superuser, so the
assertion is meaningful): anon DELETE → 0 rows, non-admin authenticated DELETE → 0 rows, admin
DELETE → 1 row removed. Policy is correct; the coverage is one statement short.

---

## Checked and clean (no finding)

- **Export vs migrations agree exactly.** Built a second container from `docs/sql-export/*.sql` at
  3efe1a4 plus the three migrations (`2026-09-09-phase1-pricing.sql`,
  `2026-09-11-court-name-not-null.sql`, `2026-09-11-view-total-court-cost.sql`) and diffed it
  against the container built from the branch's export, comparing `pg_get_functiondef` for every
  function, every column type/nullability/default, every constraint, every policy with roles and
  quals, every table ACL and RLS flag, every view definition, every index and every trigger:
  **0 lines of difference.**
- **`proacl` on the three new/changed SECURITY DEFINER functions is correct.** Raw ACL inspected
  (not `has_function_privilege`): `{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}`
  — both the `=X/postgres` PUBLIC entry and the `anon=X/postgres` Supabase entry are gone for
  `refresh_interval_courts`, `set_session_court_bookings`, `set_session_shuttle_usage`. Mutation
  confirms the tests detect a regression here: re-granting EXECUTE to `PUBLIC` and `anon` on
  `set_session_shuttle_usage` turns `13_shuttle_usage.test.sql` red.
- **No indirect anon path into `refresh_interval_courts`.** `recreate_session_intervals` and
  `trigger_refresh_courts` remain SECURITY INVOKER and anon-executable, but the nested call is
  refused (`permission denied for function refresh_interval_courts`) because the EXECUTE check
  happens at the call site under the caller's role.
- **`shuttle_types` RLS is right, and the brief's premise about it is not.** Guests do *not* need
  to read the catalogue: `useShuttleTypes` is consumed only by `SettingsView` and by
  `ShuttleUsageEditor`, and `SessionDetailView.vue:1656` renders that editor under
  `session.status === 'open' && authStore.isAdmin`. Guests read the frozen breakdown from
  `sessions.shuttle_usage` (`SessionDetailView.vue:272-280`), which anon can read. The
  authenticated-only SELECT policy is the correct choice, and mutating it (adding an anon SELECT
  policy) correctly turns `13_shuttle_usage.test.sql` red.
- **`refresh_interval_courts` arithmetic is exact, not approximate.** Partial overlap 10:15-10:45
  over two intervals → 30000 + 30000; a 2-hour booking over four intervals → 60000 x 4 = 240000
  exactly; zero-length bookings are refused by the CHECK. No rounding slack is consumed. Removing
  the `LEAST`/`GREATEST` clipping turns `10_court_cost.test.sql` and
  `12_set_court_bookings.test.sql` red.
- **Mutations the suite does catch** (each turned the named file red): admin guard removed from
  `set_session_court_bookings`; status guard removed from it; `court_name` guard removed from it;
  the RPC ignoring the submitted `price_per_hour`; `court_cost > 0` flipped to `>= 0`;
  `CEIL` → `FLOOR`; shuttle weight re-based from court-units to intervals; addon weight re-based
  the same way; both new CHECK constraints dropped; interval clipping removed; anon re-granted
  EXECUTE; anon granted SELECT on `shuttle_types`.
