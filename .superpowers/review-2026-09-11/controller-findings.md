# Controller findings — 2026-09-11

Measured against production `bufpmpehugzysvmbjlub` (read-only except the two rolled-back probes below) and the local container. Range 3efe1a4..9f4a3c7.

## Baseline: green

| Check | Result |
| --- | --- |
| `pnpm type-check` | clean |
| `pnpm vitest run` | 29/29 |
| `./db-tests/run.sh` | 10/10 files |
| `pnpm i18n:audit` | MISSING 0, VI_ONLY 0, EN_ONLY 0 |
| Money parity on production | **0 mismatched rows / 266 compared, 0 VND drift** |

Money parity was measured by recomputing `calculate_session_costs` for every non-deleted session and joining against every stored `session_costs_snapshot` row. This is the branch's headline promise — 53 existing sessions must not move by a single dong — and it holds.

## Export versus production: no drift

All six functions the branch touched or created match production exactly on name, argument types, `prosecdef`, `proconfig` and privileges, as do both `shuttle_types` policies. The migrations were applied and the export tells the truth.

## C1 (Important) — two sibling RPCs were left at the old privilege level

The branch created three locked-down RPCs and left two it calls beside them wide open:

| function | secdef | search_path | anon EXECUTE |
| --- | --- | --- | --- |
| `set_session_court_bookings(uuid, jsonb)` | true | `public, pg_temp` | **false** |
| `set_session_shuttle_usage(uuid, jsonb)` | true | `public, pg_temp` | **false** |
| `refresh_interval_courts(uuid)` | true | `public, pg_temp` | **false** |
| `create_session_with_bookings(8 args)` | **false** | — | **true** |
| `recreate_session_intervals(uuid, timestamptz, timestamptz)` | **false** | — | **true** |

Both of the last two write session data, and `SessionDetailView.vue` calls `recreate_session_intervals` directly when the admin changes a session's times. Their ACLs still carry both `=X/postgres` and `anon=X/postgres`.

**Not exploitable today.** Probed on production as the real `anon` role inside a transaction that was rolled back:

| attempt as anon | rows affected |
| --- | --- |
| `create_session_with_bookings(...)` | session created: 0 |
| `DELETE FROM session_intervals` (what `recreate_session_intervals` does first) | 0 |
| `UPDATE session_court_bookings SET price_per_hour = 999999` | 0 |
| `UPDATE sessions SET shuttle_fee_total = 0` | 0 |
| `UPDATE shuttle_types SET tube_price = 1` | 0 |

RLS catches all of it. But that is one layer, and it is the layer Phase 0 just rewrote. This is the same family as Phase 0's finding I1 (`soft_delete_cancelled_session` and friends), which was closed by adding revokes without changing the function bodies. The same fix applies here: `REVOKE EXECUTE ... FROM PUBLIC, anon` plus `GRANT ... TO authenticated` in `docs/sql-export/09_grants.sql`, with strict `insufficient_privilege` assertions in `db-tests/04_rls_lockdown.test.sql`. No body change, no behaviour change.

Reminder for whoever writes it: on Supabase `anon` reaches EXECUTE through two independent grants, so `FROM anon` alone and `FROM PUBLIC` alone are both inert. Only `FROM PUBLIC, anon` works.

## C2 — `shuttle_types` has no anon policy, and that is correct

Its two policies are `shuttle_types_authenticated_read` (SELECT, authenticated) and `shuttle_types_admin_write` (ALL, authenticated). No anon access at all.

I checked whether that breaks a guest path, because `/session/:id` has NO route guard and is guest-reachable. It does not: `ShuttleUsageEditor` is the only reader and it renders under `v-if="session.status === 'open' && authStore.isAdmin"`. Guests see the already-computed `shuttle_fee_total` on `sessions`, which they can read. Not a finding — recorded so the next reader does not re-open it.

## C3 (Minor) — `useShuttleTypes` caches an empty result as loaded

`src/composables/useShuttleTypes.ts:13-26`: `fetchTypes` sets `loaded = true` after any successful query, including one that returns zero rows, and early-returns forever after. A caller that hit RLS, or hit the catalogue before any type was created, never retries without `force`. Only reachable by a non-admin today, who never renders the editor, so the blast radius is small — but `addType`/`updateType` are the only things that ever pass `force`, so an admin whose very first load raced an empty catalogue would need a page reload.

## C4 (Minor) — unused i18n keys nearly doubled

`UNUSED_COUNT` went 27 → 44 across this branch. Deleting six components orphaned their keys. `MISSING_COUNT` is 0 and both languages are in sync, so nothing is broken; the catalogue is just carrying 44 dead entries. Phase 1-4's Task 12 was the cleanup task and did not sweep them.
