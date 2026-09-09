# Phase 0 — Siết RLS và sửa hai lỗi tiền: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Đóng lỗ hổng cho phép bất kỳ ai xóa nợ của mình bằng anon key, sửa hai lỗi tiền đi kèm, và đưa `docs/sql-export/` khớp lại với production.

**Architecture:** Không đụng frontend. Toàn bộ thay đổi nằm ở tầng Postgres: chuyển bốn RPC ghi tiền sang `SECURITY DEFINER` kèm kiểm tra quyền admin bên trong, rồi mới bỏ hai policy mở toàn quyền. Mỗi bước được viết test trước trên một Postgres 17 chạy bằng Docker, nạp schema từ `docs/sql-export/`. Kết quả bàn giao là một file migration để người dùng tự chạy trên production, cộng với các file trong `docs/sql-export/` đã cập nhật.

**Tech Stack:** PostgreSQL 17 (Docker), psql, Supabase RLS. Không thêm dependency nào vào ứng dụng.

**Spec:** [docs/superpowers/specs/2026-09-09-pricing-model-and-create-session-ux-design.md](../specs/2026-09-09-pricing-model-and-create-session-ux-design.md) — mục 3.

## Global Constraints

- **Nguồn sự thật của DB là `docs/sql-export/*.sql`**, không phải thư mục migration. `docs/sql-export/README.md` ghi rõ: "Every DB/RPC/RLS change must be updated directly in these SQL files." Mọi task đổi DB đều phải sửa file export tương ứng trong cùng commit.
- **Nhưng đừng tin file export cho tới khi đã đối chiếu.** Nó được cập nhật bằng tay, nên trôi khỏi production theo hai đường: người sửa thẳng trên Supabase dashboard rồi quên file, hoặc agent áp thay đổi qua Supabase MCP rồi không ghi ngược lại. Task 0 là bước đối chiếu bắt buộc và phải chạy lại mỗi khi quay lại plan này.
- **Tuyệt đối không chạy lệnh ghi lên production.** Project Supabase `bufpmpehugzysvmbjlub` chỉ được đọc. Mọi thay đổi được giao cho người dùng dưới dạng file SQL để họ tự chạy.
- Mọi RPC được sửa hoặc tạo mới trong plan này phải có `SECURITY DEFINER` và `SET search_path = public, pg_temp`.
- Thông báo lỗi cho người dùng cuối viết tiếng Việt, khớp giọng các `RAISE EXCEPTION` sẵn có (ví dụ: `'Không thể xóa thành viên khi Session đang ở trạng thái "%"...'`).
- Giữ nguyên comment tiếng Việt đã có trong thân hàm khi sửa; chỉ thêm, không viết lại.
- Postgres 17, khớp phiên bản production.

---

## File Structure

| File | Trách nhiệm |
| --- | --- |
| `db-tests/drift-check.sql` | Bốn truy vấn chỉ đọc, chạy giống hệt nhau trên production và trên container, để phát hiện file export trôi khỏi thực tế |
| `db-tests/drift-check.sh` | Chạy bốn truy vấn đó trên container, ghi ra `db-tests/drift/local.txt` |
| `db-tests/up.sh` | Tạo container Postgres 17, nạp schema từ `docs/sql-export/`, tạo role `anon`/`authenticated`/`service_role`, cài stub `auth.uid()` |
| `db-tests/down.sh` | Xóa container |
| `db-tests/helpers.sql` | Role, stub `auth.uid()`, hàm `assert_eq` |
| `db-tests/seed.sql` | Fixture: 1 admin, 2 member thường, 1 session `open` với interval và điểm danh |
| `db-tests/run.sh` | Chạy mọi file `db-tests/*.test.sql` với `ON_ERROR_STOP=1` |
| `db-tests/01_finalize_status.test.sql` | Task 2 |
| `db-tests/02_admin_guard.test.sql` | Task 3 |
| `db-tests/03_group_payment.test.sql` | Task 4 |
| `db-tests/04_rls_lockdown.test.sql` | Task 5 |
| `docs/sql-export/06_functions.sql` | Thân các RPC (sửa ở Task 2, 3, 4, 6) |
| `docs/sql-export/08_rls.sql` | Policy (sửa ở Task 5, 6) |
| `docs/sql-export/09_grants.sql` | **File mới** — `GRANT`/`REVOKE` trên function, trước đây chưa được export |
| `docs/migrations/2026-09-09-phase0-security.sql` | **File mới** — script người dùng chạy trên production, gộp mọi thay đổi theo đúng thứ tự |

---

## Task 0: Đối chiếu `docs/sql-export/` với production

Cả plan này dựng bàn test **từ** `docs/sql-export/`. Nếu file export đã trôi khỏi production thì mọi test ở các task sau đều đang đo một schema không tồn tại. Task này biến việc đối chiếu thành một bước chạy lại được, không phải một lần kiểm tra rồi thôi.

**Files:**
- Create: `db-tests/drift-check.sql`
- Create: `db-tests/drift-check.sh`
- Create: `db-tests/drift/.gitignore` (nội dung: `*.txt`)

**Interfaces:**
- Consumes: `docs/sql-export/*.sql`; quyền đọc production qua Supabase MCP
- Produces: `db-tests/drift/local.txt` và `db-tests/drift/prod.txt`, hai file text cùng định dạng để `diff`

### Kết quả đối chiếu ngày 2026-09-09

Đã chạy một lần khi viết plan. Người thực hiện phải **chạy lại** và đối chiếu với bảng này; khác biệt mới nghĩa là có ai đó vừa đổi production.

| Hạng mục | Kết quả |
| --- | --- |
| 11 bảng và toàn bộ cột | Khớp |
| Index | Khớp |
| Thân function (đối chiếu 7 hàm, gồm `calculate_session_costs` và `finalize_session`) | Khớp |
| `health()`, `rpc_generate_draft()` | Có trên production, **thiếu** trong export |
| Policy `bank_config` | **Lệch** — xem Task 5 |
| `GRANT`/`REVOKE` trên function | **Chưa từng được export** — xem Task 3 |

- [ ] **Step 1: Viết bộ truy vấn đối chiếu**

Tạo `db-tests/drift-check.sql`. Bốn truy vấn này phải chạy được y nguyên trên cả hai phía, và không được chứa lệnh ghi nào.

```sql
-- 1. tables and columns
SELECT c.relname || ' | ' || string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ', ' ORDER BY a.attnum) AS row
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
WHERE n.nspname = 'public' AND c.relkind = 'r'
GROUP BY c.relname ORDER BY c.relname;

-- 2. indexes
SELECT indexname AS row FROM pg_indexes
WHERE schemaname = 'public' ORDER BY indexname;

-- 3. policies
SELECT tablename || ' | ' || policyname || ' | ' || cmd || ' | ' || roles::text
       || ' | ' || coalesce(qual, '-') || ' | ' || coalesce(with_check, '-') AS row
FROM pg_policies WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- 4. functions: name, args, security mode, search_path, and a body hash
SELECT p.proname || ' | ' || pg_get_function_identity_arguments(p.oid)
       || ' | secdef=' || p.prosecdef
       || ' | cfg=' || coalesce(array_to_string(p.proconfig, ','), '-')
       || ' | md5=' || md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g')) AS row
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname NOT LIKE 'gtrgm%' AND p.proname NOT LIKE 'gin_%'
  AND p.proname NOT IN ('set_limit','show_limit','show_trgm','similarity','similarity_dist',
                        'similarity_op','strict_word_similarity','strict_word_similarity_op',
                        'strict_word_similarity_dist_op','strict_word_similarity_commutator_op',
                        'strict_word_similarity_dist_commutator_op','word_similarity',
                        'word_similarity_op','word_similarity_dist_op',
                        'word_similarity_commutator_op','word_similarity_dist_commutator_op')
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);
```

Truy vấn 4 loại bỏ các hàm do `pg_trgm` cài ra, vì chúng không phải code của dự án.

- [ ] **Step 2: Viết script chạy phía cục bộ**

Tạo `db-tests/drift-check.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p db-tests/drift

docker exec -i bmt-test psql -U postgres -d bmt -At -v ON_ERROR_STOP=1 \
  < db-tests/drift-check.sql > db-tests/drift/local.txt

echo "wrote db-tests/drift/local.txt ($(wc -l < db-tests/drift/local.txt) rows)"
echo "now run the same four queries against production and save to db-tests/drift/prod.txt,"
echo "then: diff db-tests/drift/prod.txt db-tests/drift/local.txt"
```

Tạo `db-tests/drift/.gitignore` với nội dung `*.txt` — hai file kết quả là sản phẩm tạm, không commit.

- [ ] **Step 3: Lấy phía production**

Chạy từng truy vấn trong `db-tests/drift-check.sql` trên production bằng Supabase MCP (`execute_sql`, chỉ đọc), nối kết quả theo đúng thứ tự 1→4 vào `db-tests/drift/prod.txt`, mỗi dòng một bản ghi, không header.

**Không dùng `apply_migration` hay bất kỳ đường ghi nào.** Project `bufpmpehugzysvmbjlub` là production thật.

- [ ] **Step 4: So sánh và ghi nhận**

```bash
chmod +x db-tests/drift-check.sh
./db-tests/drift-check.sh
diff db-tests/drift/prod.txt db-tests/drift/local.txt || true
```

Đối chiếu khác biệt với bảng "Kết quả đối chiếu ngày 2026-09-09" ở trên.

- Khác biệt **trùng** với bảng đó: đúng dự kiến, các task sau sẽ vá. Đi tiếp.
- Khác biệt **mới**: có người vừa đổi production mà chưa ghi vào export. **Dừng lại**, báo người dùng, và cập nhật file export cho khớp production **trước khi** làm bất kỳ task nào — nếu không, migration ở Task 7 sẽ ghi đè thay đổi của họ.

- [ ] **Step 5: Commit**

```bash
git add db-tests/drift-check.sql db-tests/drift-check.sh db-tests/drift/.gitignore
git commit -m "test: add a repeatable drift check between docs/sql-export and production"
```

---

## Task 1: Bàn test Postgres cục bộ

Không có test framework nào trong repo và không có Postgres trên máy (`psql` chỉ là wrapper, không có cluster). Task này dựng bàn test bằng Docker để mọi task sau có chỗ chạy đỏ trước, xanh sau.

Chạy sau khi Task 0 xanh — bàn test chỉ đáng tin khi file export đã được đối chiếu.

**Files:**
- Create: `db-tests/up.sh`
- Create: `db-tests/down.sh`
- Create: `db-tests/helpers.sql`
- Create: `db-tests/seed.sql`
- Create: `db-tests/run.sh`
- Create: `db-tests/00_smoke.test.sql`

**Interfaces:**
- Consumes: `docs/sql-export/00_extensions.sql` … `08_rls.sql`
- Produces:
  - `db-tests/up.sh` — dựng container tên `bmt-test` cổng 55432, database `bmt`, user `postgres`, password `postgres`
  - `db-tests/run.sh` — chạy mọi `db-tests/*.test.sql`, thoát khác 0 nếu có assert nào fail
  - `assert_eq(actual anyelement, expected anyelement, label text)` — `RAISE EXCEPTION` khi lệch
  - Ba UUID cố định dùng lại ở mọi test: admin `11111111-1111-1111-1111-111111111111`, member A `22222222-…-2222`, member B `33333333-…-3333`
  - Session fixture `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa`

- [ ] **Step 1: Viết script dựng container**

Tạo `db-tests/up.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONTAINER=bmt-test
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=bmt \
  -p 55432:5432 \
  postgres:17 >/dev/null

echo -n "waiting for postgres"
until docker exec "$CONTAINER" pg_isready -U postgres -d bmt >/dev/null 2>&1; do
  echo -n "."
  sleep 1
done
echo

psql_run() {
  docker exec -i "$CONTAINER" psql -U postgres -d bmt -v ON_ERROR_STOP=1 -q
}

# helpers must run first: they create the roles and the auth.uid() stub
# that 08_rls.sql and the RPCs depend on.
psql_run < db-tests/helpers.sql
for f in docs/sql-export/0{0,1,2,3,4,5,6,7,8}_*.sql; do
  echo "loading $f"
  psql_run < "$f"
done
psql_run < db-tests/seed.sql

echo "test database ready on localhost:55432"
```

Tạo `db-tests/down.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
docker rm -f bmt-test >/dev/null 2>&1 || true
echo "test database removed"
```

- [ ] **Step 2: Viết helpers**

Tạo `db-tests/helpers.sql`. Postgres thường không có role của Supabase và không có schema `auth`; schema export tham chiếu cả hai nên phải tạo trước.

```sql
-- Supabase roles referenced by 08_rls.sql
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;

-- Supabase auth schema + auth.uid() stub.
-- Tests impersonate a user with:  SET request.jwt.claim.sub = '<uuid>';
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE auth.users (id uuid PRIMARY KEY);

CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role;

-- Assertion helper. Raises, so ON_ERROR_STOP=1 turns a failed assert into
-- a non-zero exit code from psql.
CREATE OR REPLACE FUNCTION assert_eq(actual anyelement, expected anyelement, label text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF actual IS DISTINCT FROM expected THEN
    RAISE EXCEPTION 'FAIL % — expected %, got %', label, expected, actual;
  END IF;
  RAISE NOTICE 'ok   %', label;
END;
$$;

-- Supabase grants PostgREST roles table + function access by default.
-- Reproduce that here so RLS, not missing grants, is what the tests measure.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
```

- [ ] **Step 3: Viết fixture**

Tạo `db-tests/seed.sql`. Số liệu lấy đúng theo ví dụ đã tính tay trong `docs/context/02-business-logic.md` mục "Ví dụ tính toán", để Plan B dùng lại được cùng fixture này làm mốc so sánh.

```sql
-- Auth users (admin only; the other two members are not linked)
INSERT INTO auth.users (id) VALUES ('11111111-1111-1111-1111-111111111111');

INSERT INTO members (id, user_id, display_name, role, is_active) VALUES
  ('11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Admin', 'admin', true),
  ('22222222-2222-2222-2222-222222222222', NULL, 'Member A', 'member', true),
  ('33333333-3333-3333-3333-333333333333', NULL, 'Member B', 'member', true);

-- Old-style session: price_per_hour = 0, all court money in court_fee_addon
INSERT INTO sessions (id, title, start_time, end_time, price_per_hour, court_fee_addon, shuttle_fee_total, status)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Fixture session',
        '2026-09-01 11:00:00+00', '2026-09-01 12:00:00+00', 0, 300000, 120000, 'open');

-- Two 30-minute intervals, 2 courts then 1 court
INSERT INTO session_intervals (id, session_id, start_time, end_time, idx, active_court_count) VALUES
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '2026-09-01 11:00:00+00', '2026-09-01 11:30:00+00', 0, 2),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '2026-09-01 11:30:00+00', '2026-09-01 12:00:00+00', 1, 1);

-- A and B registered; A present in both intervals, B present in the first only
INSERT INTO session_registrations (session_id, member_id) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333');

INSERT INTO interval_presence (interval_id, member_id, is_present) VALUES
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', '22222222-2222-2222-2222-222222222222', true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', '22222222-2222-2222-2222-222222222222', true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', '33333333-3333-3333-3333-333333333333', true);

INSERT INTO bank_config (bank_id, account_number, account_name, template, is_active)
VALUES ('TPB', '10003392871', 'CLB CAU LONG BMT', 'compact2', true);
```

- [ ] **Step 4: Viết runner**

Tạo `db-tests/run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

failed=0
for f in db-tests/*.test.sql; do
  echo "=== $f"
  if docker exec -i bmt-test psql -U postgres -d bmt -v ON_ERROR_STOP=1 -q < "$f"; then
    echo "PASS $f"
  else
    echo "FAIL $f"
    failed=1
  fi
done
exit "$failed"
```

- [ ] **Step 5: Viết smoke test**

Tạo `db-tests/00_smoke.test.sql`. Test này khẳng định bàn test tự nó đúng: schema nạp được, fixture có mặt, engine tính tiền cho ra đúng ba con số đã tính tay trong `02-business-logic.md`.

```sql
BEGIN;

SELECT assert_eq((SELECT count(*)::int FROM members), 3, 'members seeded');
SELECT assert_eq((SELECT count(*)::int FROM session_intervals), 2, 'intervals seeded');

-- Worked example from docs/context/02-business-logic.md, minus the ghost member:
--   interval 1: real_present = 2, ghost = 0  -> court (300k*2/3)/2 = 100000 each
--   interval 2: real_present = 1, ghost = 0  -> court (300k*1/3)/1 = 100000
--   shuttle    1: (120k*2/3)/2 = 40000 each; 2: (120k*1/3)/1 = 40000
-- A = 100000+100000 court + 40000+40000 shuttle = 280000
-- B = 100000        court + 40000        shuttle = 140000
SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  280000::numeric, 'member A final_total');

SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  140000::numeric, 'member B final_total');

ROLLBACK;
```

- [ ] **Step 6: Chạy bàn test**

```bash
chmod +x db-tests/up.sh db-tests/down.sh db-tests/run.sh
./db-tests/up.sh
./db-tests/run.sh
```

Kỳ vọng: `PASS db-tests/00_smoke.test.sql`.

Nếu smoke fail ở phần tính tiền, **dừng lại và đối chiếu** với `docs/context/02-business-logic.md` trước khi đi tiếp — mọi task sau đều dựa trên bàn test này.

- [ ] **Step 7: Commit**

```bash
git add db-tests/
git commit -m "test: add local Postgres test bed loaded from docs/sql-export"
```

---

## Task 2: `finalize_session` tính lại `status`

**Bug:** `ON CONFLICT DO UPDATE` chỉ cập nhật `final_amount` và ba cột breakdown. Chốt lại một buổi đã có người trả một phần thì `final_amount` tăng nhưng `status` vẫn giữ giá trị cũ. Nếu giá trị cũ là `paid`, khoản nợ mới biến mất khỏi `view_member_debt_summary` vì view đó lọc `status <> 'paid'`.

**Files:**
- Create: `db-tests/01_finalize_status.test.sql`
- Modify: `docs/sql-export/06_functions.sql:642-691` (thân `finalize_session`)

**Interfaces:**
- Consumes: `assert_eq`, fixture từ Task 1
- Produces: `finalize_session(p_session_id uuid)` — chữ ký không đổi, thêm cột `status` vào mệnh đề `ON CONFLICT DO UPDATE`

- [ ] **Step 1: Viết test đỏ**

Tạo `db-tests/01_finalize_status.test.sql`:

```sql
BEGIN;

-- Finalize once, then let member A pay in full.
SELECT finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

UPDATE session_costs_snapshot
SET paid_amount = final_amount, status = 'paid'
WHERE member_id = '22222222-2222-2222-2222-222222222222';

SELECT assert_eq(
  (SELECT status::text FROM session_costs_snapshot
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  'paid', 'A is paid before the price change');

-- Admin raises the shuttle fee and re-finalizes.
UPDATE sessions SET shuttle_fee_total = 240000
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

SELECT finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- A now owes more than they paid, so the row must drop back to partial.
SELECT assert_eq(
  (SELECT status::text FROM session_costs_snapshot
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  'partial', 'A falls back to partial after the price rise');

-- And the debt must be visible again.
SELECT assert_eq(
  (SELECT count(*)::int FROM view_member_debt_summary
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  1, 'A reappears in the debt summary');

-- B never paid, so B stays pending.
SELECT assert_eq(
  (SELECT status::text FROM session_costs_snapshot
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  'pending', 'B stays pending');

ROLLBACK;
```

- [ ] **Step 2: Chạy test, xác nhận đỏ**

```bash
./db-tests/run.sh
```

Kỳ vọng: `FAIL db-tests/01_finalize_status.test.sql` với thông báo `FAIL A falls back to partial after the price rise — expected partial, got paid`.

- [ ] **Step 3: Sửa hàm**

Trong `docs/sql-export/06_functions.sql`, thay mệnh đề `ON CONFLICT` của `finalize_session`:

```sql
            ON CONFLICT (session_id, member_id) DO UPDATE
            SET
                final_amount = EXCLUDED.final_amount,
                court_fee_amount = EXCLUDED.court_fee_amount,
                shuttle_fee_amount = EXCLUDED.shuttle_fee_amount,
                extra_fee_amount = EXCLUDED.extra_fee_amount,
                -- Recompute status: re-finalizing after a price change must not
                -- leave a row marked 'paid' while it owes money again.
                status = CASE
                    WHEN session_costs_snapshot.paid_amount >= EXCLUDED.final_amount
                        THEN 'paid'::public.payment_status
                    WHEN session_costs_snapshot.paid_amount > 0
                        THEN 'partial'::public.payment_status
                    ELSE 'pending'::public.payment_status
                END;
```

- [ ] **Step 4: Nạp lại hàm và chạy test**

```bash
docker exec -i bmt-test psql -U postgres -d bmt -v ON_ERROR_STOP=1 -q < docs/sql-export/06_functions.sql
./db-tests/run.sh
```

Kỳ vọng: mọi file `PASS`.

- [ ] **Step 5: Commit**

```bash
git add db-tests/01_finalize_status.test.sql docs/sql-export/06_functions.sql
git commit -m "fix(db): recompute snapshot status when re-finalizing a session"
```

---

## Task 3: Ba RPC ghi tiền thành `SECURITY DEFINER` và chỉ admin gọi được

Đây là bước phải làm **trước** khi bỏ policy ở Task 5. Ba hàm này hiện là `SECURITY INVOKER`; bỏ policy trước sẽ làm admin mất khả năng chốt buổi, thu tiền mặt và xóa thành viên.

**Files:**
- Create: `db-tests/02_admin_guard.test.sql`
- Modify: `docs/sql-export/06_functions.sql` — `add_manual_payment` (dòng 1-60), `finalize_session` (dòng ~642), `remove_member_from_session` (dòng ~808)
- Create: `docs/sql-export/09_grants.sql`

**Interfaces:**
- Consumes: `assert_eq`, fixture, stub `auth.uid()` từ Task 1
- Produces: ba hàm giữ nguyên chữ ký, thêm `SECURITY DEFINER`, `SET search_path = public, pg_temp`, và khối kiểm tra quyền admin ở đầu thân hàm. `docs/sql-export/09_grants.sql` giữ toàn bộ `GRANT`/`REVOKE` trên function.

- [ ] **Step 1: Viết test đỏ**

Tạo `db-tests/02_admin_guard.test.sql`:

```sql
BEGIN;

SELECT finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- As an anonymous visitor: every money-writing RPC must refuse.
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claim.sub = '';

DO $$
BEGIN
  BEGIN
    PERFORM add_manual_payment(
      (SELECT id FROM session_costs_snapshot LIMIT 1), 1000, 'hack');
    RAISE EXCEPTION 'FAIL anon could call add_manual_payment';
  EXCEPTION WHEN insufficient_privilege OR raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    RAISE NOTICE 'ok   anon blocked from add_manual_payment';
  END;
END $$;

DO $$
BEGIN
  BEGIN
    PERFORM finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    RAISE EXCEPTION 'FAIL anon could call finalize_session';
  EXCEPTION WHEN insufficient_privilege OR raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    RAISE NOTICE 'ok   anon blocked from finalize_session';
  END;
END $$;

RESET ROLE;

-- As a signed-in non-admin member: also refused.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

DO $$
BEGIN
  BEGIN
    PERFORM remove_member_from_session(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '33333333-3333-3333-3333-333333333333');
    RAISE EXCEPTION 'FAIL non-admin could remove a member';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    RAISE NOTICE 'ok   non-admin blocked from remove_member_from_session';
  END;
END $$;

RESET ROLE;

-- As admin: all three still work.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

SELECT add_manual_payment(
  (SELECT id FROM session_costs_snapshot
    WHERE member_id = '33333333-3333-3333-3333-333333333333'), 50000, 'cash');

SELECT assert_eq(
  (SELECT paid_amount FROM session_costs_snapshot
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  50000::numeric, 'admin can record a cash payment');

RESET ROLE;
ROLLBACK;
```

- [ ] **Step 2: Chạy test, xác nhận đỏ**

```bash
./db-tests/run.sh
```

Kỳ vọng: `FAIL db-tests/02_admin_guard.test.sql` với `FAIL anon could call add_manual_payment`.

- [ ] **Step 3: Thêm `SECURITY DEFINER` và kiểm tra quyền vào ba hàm**

Trong `docs/sql-export/06_functions.sql`, với **mỗi** hàm `add_manual_payment`, `finalize_session`, `remove_member_from_session`:

Đổi dòng khai báo, ví dụ với `add_manual_payment`:

```sql
CREATE OR REPLACE FUNCTION public.add_manual_payment(p_snapshot_id uuid, p_amount numeric, p_note text DEFAULT 'Tiền mặt'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
```

Và chèn khối này ngay sau `BEGIN` của cả ba hàm, trước mọi câu lệnh khác:

```sql
  -- Function runs as its owner, so it must check the caller itself.
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Chỉ admin được thực hiện thao tác này';
  END IF;
```

`finalize_session` khai báo `DECLARE r RECORD; v_payment_code TEXT;` — chèn khối kiểm tra sau `BEGIN`, không phải trong `DECLARE`.

- [ ] **Step 4: Tạo file grant**

Tạo `docs/sql-export/09_grants.sql`:

```sql
-- Function-level grants. Supabase exposes every function in the public
-- schema through /rest/v1/rpc, so anything that writes money must be
-- explicitly revoked from anon.

REVOKE EXECUTE ON FUNCTION public.add_manual_payment(uuid, numeric, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.finalize_session(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.remove_member_from_session(uuid, uuid) FROM anon;

GRANT EXECUTE ON FUNCTION public.add_manual_payment(uuid, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_session(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_member_from_session(uuid, uuid) TO authenticated;

-- create_group_payment stays callable by anon: guests pay from the home page.
GRANT EXECUTE ON FUNCTION public.create_group_payment(uuid[]) TO anon, authenticated;

-- Read-only, safe for guests.
GRANT EXECUTE ON FUNCTION public.check_qr_status(text) TO anon, authenticated;
```

Bổ sung `09_grants.sql` vào phần "Run order" của `docs/sql-export/README.md`, sau `08_rls.sql`.

- [ ] **Step 5: Nạp lại và chạy test**

```bash
docker exec -i bmt-test psql -U postgres -d bmt -v ON_ERROR_STOP=1 -q < docs/sql-export/06_functions.sql
docker exec -i bmt-test psql -U postgres -d bmt -v ON_ERROR_STOP=1 -q < docs/sql-export/09_grants.sql
./db-tests/run.sh
```

Kỳ vọng: mọi file `PASS`.

- [ ] **Step 6: Commit**

```bash
git add db-tests/02_admin_guard.test.sql docs/sql-export/06_functions.sql docs/sql-export/09_grants.sql docs/sql-export/README.md
git commit -m "fix(db): make money-writing RPCs SECURITY DEFINER with an admin check"
```

---

## Task 4: `create_group_payment` thành `SECURITY DEFINER`

**Bug:** nhánh tái sử dụng mã chạy `UPDATE group_payment_requests SET total_amount = v_total`, nhưng bảng đó không có policy `UPDATE` nào — cho cả `anon` lẫn `authenticated`. RLS chặn im lặng, 0 dòng bị sửa, không có lỗi. `check_qr_status` sau đó đọc `total_amount` cũ làm mục tiêu, nên thanh tiến trình hiển thị sai.

Hàm này **giữ quyền gọi cho `anon`** — khách trả tiền từ trang chủ là luồng chính. Nó chỉ ghi vào `group_payment_requests` và chỉ đọc `session_costs_snapshot`, nên không cần kiểm tra quyền admin.

**Files:**
- Create: `db-tests/03_group_payment.test.sql`
- Modify: `docs/sql-export/06_functions.sql:454-525` (`create_group_payment`)

**Interfaces:**
- Consumes: `assert_eq`, fixture
- Produces: `create_group_payment(p_snapshot_ids uuid[]) RETURNS jsonb` — chữ ký không đổi, thêm `SECURITY DEFINER` và `SET search_path = public, pg_temp`

- [ ] **Step 1: Viết test đỏ**

Tạo `db-tests/03_group_payment.test.sql`:

```sql
BEGIN;

SELECT finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

SET LOCAL ROLE anon;
SET LOCAL request.jwt.claim.sub = '';

-- A guest creates a group code for both members.
SELECT create_group_payment(ARRAY(SELECT id FROM session_costs_snapshot ORDER BY id));

SELECT assert_eq(
  (SELECT total_amount FROM group_payment_requests),
  (SELECT sum(final_amount - paid_amount) FROM session_costs_snapshot),
  'group total matches the debt at creation');

RESET ROLE;

-- One member pays. The stored total must refresh when the code is reused.
UPDATE session_costs_snapshot
SET paid_amount = final_amount, status = 'paid'
WHERE member_id = '22222222-2222-2222-2222-222222222222';

SET LOCAL ROLE anon;
SELECT create_group_payment(ARRAY(SELECT id FROM session_costs_snapshot ORDER BY id));

SELECT assert_eq(
  (SELECT count(*)::int FROM group_payment_requests),
  1, 'reuse does not create a second row');

SELECT assert_eq(
  (SELECT total_amount FROM group_payment_requests),
  (SELECT sum(final_amount - paid_amount) FROM session_costs_snapshot),
  'reused group total refreshed to the remaining debt');

-- check_qr_status reads that column, so it must agree.
SELECT assert_eq(
  ((SELECT check_qr_status(group_code) FROM group_payment_requests)->>'total')::numeric,
  (SELECT sum(final_amount - paid_amount) FROM session_costs_snapshot),
  'check_qr_status reports the refreshed total');

RESET ROLE;
ROLLBACK;
```

- [ ] **Step 2: Chạy test, xác nhận đỏ**

```bash
./db-tests/run.sh
```

Kỳ vọng: `FAIL db-tests/03_group_payment.test.sql` ở assert `reused group total refreshed to the remaining debt` — giá trị nhận được là tổng nợ cũ, không phải tổng nợ còn lại.

- [ ] **Step 3: Sửa khai báo hàm**

Trong `docs/sql-export/06_functions.sql`:

```sql
CREATE OR REPLACE FUNCTION public.create_group_payment(p_snapshot_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
```

Thân hàm giữ nguyên. Không thêm kiểm tra quyền admin — khách phải gọi được hàm này.

- [ ] **Step 4: Nạp lại và chạy test**

```bash
docker exec -i bmt-test psql -U postgres -d bmt -v ON_ERROR_STOP=1 -q < docs/sql-export/06_functions.sql
./db-tests/run.sh
```

Kỳ vọng: mọi file `PASS`.

- [ ] **Step 5: Commit**

```bash
git add db-tests/03_group_payment.test.sql docs/sql-export/06_functions.sql
git commit -m "fix(db): let group payment refresh its stored total on reuse"
```

---

## Task 5: Bỏ hai policy mở toàn quyền và sửa drift ở `bank_config`

Đến đây bốn RPC đã tự đứng được, nên bỏ policy sẽ không làm hỏng chức năng nào.

Task này còn sửa một drift nguy hiểm: `docs/sql-export/08_rls.sql` khai báo `bank_config` có policy `"Public Access"` `FOR ALL TO public USING(true) WITH CHECK(true)` và **thiếu** ba policy admin mà production đang có (`bank_config_admin_insert`, `bank_config_admin_update`, `bank_config_admin_delete`). Ai chạy lại file export sẽ mở `bank_config` cho ghi ẩn danh, tức cho phép người lạ đổi số tài khoản in trên mã QR.

**Files:**
- Create: `db-tests/04_rls_lockdown.test.sql`
- Modify: `docs/sql-export/08_rls.sql`

**Interfaces:**
- Consumes: `assert_eq`, fixture, các hàm đã sửa ở Task 2–4
- Produces: `08_rls.sql` khớp production, trừ hai policy `"Public Access"` bị bỏ hẳn

- [ ] **Step 1: Viết test đỏ**

Tạo `db-tests/04_rls_lockdown.test.sql`:

```sql
BEGIN;

SELECT finalize_session('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

SET LOCAL ROLE anon;
SET LOCAL request.jwt.claim.sub = '';

-- Guests must still be able to read: /pay, polling and the home debt table.
SELECT assert_eq(
  (SELECT count(*)::int > 0 FROM session_costs_snapshot),
  true, 'anon can still read snapshots');

SELECT assert_eq(
  (SELECT count(*)::int > 0 FROM bank_config WHERE is_active),
  true, 'anon can still read the active bank config');

-- Guests must not be able to clear their own debt.
WITH attempt AS (
  UPDATE session_costs_snapshot SET paid_amount = final_amount RETURNING 1
)
SELECT assert_eq((SELECT count(*)::int FROM attempt), 0, 'anon cannot mark snapshots paid');

WITH attempt AS (
  DELETE FROM session_payments RETURNING 1
)
SELECT assert_eq((SELECT count(*)::int FROM attempt), 0, 'anon cannot delete payments');

-- Guests must not be able to redirect the QR to another bank account.
WITH attempt AS (
  UPDATE bank_config SET account_number = '9999999999' RETURNING 1
)
SELECT assert_eq((SELECT count(*)::int FROM attempt), 0, 'anon cannot rewrite bank config');

SELECT assert_eq(
  (SELECT account_number FROM bank_config WHERE is_active),
  '10003392871', 'bank account number unchanged');

RESET ROLE;
ROLLBACK;
```

- [ ] **Step 2: Chạy test, xác nhận đỏ**

```bash
./db-tests/run.sh
```

Kỳ vọng: `FAIL db-tests/04_rls_lockdown.test.sql` ở `anon cannot mark snapshots paid` — nhận được số dòng lớn hơn 0.

- [ ] **Step 3: Sửa `08_rls.sql`**

Xóa hẳn ba dòng khai báo `"Public Access"` (dòng 3 cho `bank_config`, dòng 18 cho `session_costs_snapshot`, dòng 35 cho `session_payments`), thay bằng lệnh drop để file chạy được cả trên database đã có policy đó:

```sql
DROP POLICY IF EXISTS "Public Access" ON public.bank_config;
DROP POLICY IF EXISTS "Public Access" ON public.session_costs_snapshot;
DROP POLICY IF EXISTS "Public Access" ON public.session_payments;
```

Xóa dòng `bank_config_public_read ... TO public` và thêm bốn policy đúng như production đang chạy:

```sql
DROP POLICY IF EXISTS bank_config_public_read ON public.bank_config;
CREATE POLICY bank_config_public_read ON public.bank_config
  AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS bank_config_admin_insert ON public.bank_config;
CREATE POLICY bank_config_admin_insert ON public.bank_config
  AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'));

DROP POLICY IF EXISTS bank_config_admin_update ON public.bank_config;
CREATE POLICY bank_config_admin_update ON public.bank_config
  AS PERMISSIVE FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'));

DROP POLICY IF EXISTS bank_config_admin_delete ON public.bank_config;
CREATE POLICY bank_config_admin_delete ON public.bank_config
  AS PERMISSIVE FOR DELETE TO authenticated
  USING (EXISTS (SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'));
```

- [ ] **Step 4: Nạp lại và chạy test**

```bash
docker exec -i bmt-test psql -U postgres -d bmt -v ON_ERROR_STOP=1 -q < docs/sql-export/08_rls.sql
./db-tests/run.sh
```

Kỳ vọng: mọi file `PASS`. Đặc biệt `02_admin_guard` và `03_group_payment` phải vẫn xanh — đó là bằng chứng bỏ policy không làm hỏng đường ghi hợp lệ.

- [ ] **Step 5: Commit**

```bash
git add db-tests/04_rls_lockdown.test.sql docs/sql-export/08_rls.sql
git commit -m "fix(db): drop public write access on money tables, resync bank_config policies"
```

---

## Task 6: Dọn hai hàm gọi được bởi khách

`handle_new_user()` là trigger function nhưng vẫn nằm trong schema `public`, nên Supabase phơi nó ra `/rest/v1/rpc/handle_new_user` cho cả `anon` lẫn `authenticated`. `rpc_generate_draft(uuid, integer, text)` sót lại từ một dự án khác; các bảng tournament nó tham chiếu không tồn tại trong schema này.

**Files:**
- Modify: `docs/sql-export/09_grants.sql`
- Modify: `docs/sql-export/06_functions.sql` (nếu `rpc_generate_draft` có mặt trong file — kiểm tra trước)

**Interfaces:**
- Consumes: `09_grants.sql` từ Task 3
- Produces: không có API mới

- [ ] **Step 1: Xử lý hai hàm chỉ có trên production**

Task 0 đã xác nhận `health()` và `rpc_generate_draft()` tồn tại trên production nhưng vắng mặt trong `docs/sql-export/06_functions.sql`. Hai hàm đi hai hướng khác nhau:

```bash
grep -n "rpc_generate_draft\|FUNCTION public.health" docs/sql-export/*.sql || echo "neither is in the export"
```

- `rpc_generate_draft` bị xóa khỏi production ở Task 7. Không thêm vào export. Nếu vì lý do nào đó nó lại có trong export, xóa khối định nghĩa đó đi.
- `health()` được giữ lại. Lấy định nghĩa từ production và **thêm vào cuối `06_functions.sql`**, kèm `SET search_path = public, pg_temp`, để lần dựng schema tiếp theo không thiếu nó:

```sql
CREATE OR REPLACE FUNCTION public.health()
 RETURNS text
 LANGUAGE sql
 SET search_path = public, pg_temp
AS $function$ SELECT 'ok'::text $function$;
```

Đối chiếu thân hàm thật bằng `pg_get_functiondef` qua MCP trước khi dán — chỉ chép, không tự nghĩ ra.

- [ ] **Step 2: Thêm revoke vào `09_grants.sql`**

Nối vào cuối `docs/sql-export/09_grants.sql`:

```sql
-- Trigger function; nothing should call it over the REST API.
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon, authenticated;
```

- [ ] **Step 3: Nạp lại và chạy test**

```bash
docker exec -i bmt-test psql -U postgres -d bmt -v ON_ERROR_STOP=1 -q < docs/sql-export/09_grants.sql
./db-tests/run.sh
```

Kỳ vọng: mọi file `PASS`.

- [ ] **Step 4: Commit**

```bash
git add docs/sql-export/09_grants.sql docs/sql-export/06_functions.sql
git commit -m "chore(db): revoke REST access to handle_new_user"
```

---

## Task 7: Script migration cho production và runbook

Mọi thay đổi ở trên mới chỉ nằm trong file export và đã xanh trên bàn test cục bộ. Task này gom chúng thành một script để người dùng chạy trên production, kèm cách kiểm tra trước và sau.

**Files:**
- Create: `docs/migrations/2026-09-09-phase0-security.sql`
- Create: `docs/migrations/README.md`

**Interfaces:**
- Consumes: các thay đổi từ Task 2–6
- Produces: một script chạy được một lần, bọc trong transaction

- [ ] **Step 1: Viết script migration**

Tạo `docs/migrations/2026-09-09-phase0-security.sql`. Chép nguyên văn thân bốn hàm đã sửa từ `docs/sql-export/06_functions.sql` vào các chỗ đánh dấu — script phải tự đứng được, người chạy không phải mở file khác.

```sql
-- Phase 0 — security lockdown + two money bugs
-- Run once, as the postgres/owner role, in the Supabase SQL editor.
-- Everything is inside one transaction: a failure rolls the whole thing back.

BEGIN;

-- 1. Functions first, so the writes they perform keep working once the
--    permissive policies come off in step 3.
--    Paste the four updated bodies from docs/sql-export/06_functions.sql:
--      add_manual_payment, finalize_session,
--      remove_member_from_session, create_group_payment

-- <<< add_manual_payment >>>
-- <<< finalize_session >>>
-- <<< remove_member_from_session >>>
-- <<< create_group_payment >>>

-- 2. Function grants.
REVOKE EXECUTE ON FUNCTION public.add_manual_payment(uuid, numeric, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.finalize_session(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.remove_member_from_session(uuid, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_group_payment(uuid[]) TO anon, authenticated;

-- 3. Close the holes.
DROP POLICY IF EXISTS "Public Access" ON public.session_costs_snapshot;
DROP POLICY IF EXISTS "Public Access" ON public.session_payments;
DROP POLICY IF EXISTS "Public Access" ON public.bank_config;

-- 4. Leftover from another project; the tournament tables it reads do not
--    exist in this schema.
DROP FUNCTION IF EXISTS public.rpc_generate_draft(uuid, integer, text);

COMMIT;
```

- [ ] **Step 2: Viết runbook**

Tạo `docs/migrations/README.md`:

```markdown
# Migrations

`docs/sql-export/` là nguồn sự thật của schema. Thư mục này giữ các script
chạy một lần để đưa một database đang chạy từ trạng thái cũ sang trạng thái
mà `docs/sql-export/` mô tả.

## Cách chạy

1. Mở Supabase SQL editor của project.
2. Chạy phần "Trước khi chạy" bên dưới và lưu lại kết quả.
3. Dán toàn bộ script, chạy một lần.
4. Chạy phần "Sau khi chạy" và so sánh.

## 2026-09-09-phase0-security.sql

### Trước khi chạy

Lưu ảnh chụp số liệu để so sánh về sau:

```sql
SELECT count(*) AS snapshots,
       sum(paid_amount) AS total_paid,
       count(*) FILTER (WHERE status = 'paid') AS paid_rows
FROM session_costs_snapshot;
```

### Sau khi chạy

Ba con số trên phải **không đổi** — migration này không chạm vào dữ liệu.

Xác nhận hai policy đã biến mất:

```sql
SELECT tablename, policyname FROM pg_policies
WHERE schemaname = 'public' AND policyname = 'Public Access';
-- kỳ vọng: 0 dòng
```

Xác nhận bốn hàm đã là SECURITY DEFINER:

```sql
SELECT proname, prosecdef FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND proname IN ('add_manual_payment','finalize_session',
                  'remove_member_from_session','create_group_payment');
-- kỳ vọng: prosecdef = true cho cả bốn
```

### Kiểm tra trên ứng dụng

1. Đăng xuất hoàn toàn. Mở trang chủ, chọn vài người còn nợ, bấm trả tiền.
   Mã QR phải hiện ra và polling phải chạy.
2. Mở `/pay?code=<một mã CL còn nợ>`. QR phải hiện đúng số tiền.
3. Đăng nhập admin. Chốt một buổi thử, thu một khoản tiền mặt, xóa một
   thành viên khỏi một buổi đang mở. Cả ba phải chạy.

### Rollback

Script chạy trong một transaction nên lỗi giữa chừng sẽ tự quay lui. Nếu
đã COMMIT mà cần quay lại trạng thái cũ:

```sql
CREATE POLICY "Public Access" ON public.session_costs_snapshot
  AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY "Public Access" ON public.session_payments
  AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);
```

Chỉ dùng khi thật sự phải quay lui: hai policy này chính là lỗ hổng.
```

- [ ] **Step 3: Kiểm tra script chạy được trên database sạch**

```bash
./db-tests/down.sh && ./db-tests/up.sh
docker exec -i bmt-test psql -U postgres -d bmt -v ON_ERROR_STOP=1 -q \
  < docs/migrations/2026-09-09-phase0-security.sql
./db-tests/run.sh
```

Kỳ vọng: script chạy không lỗi, mọi test `PASS`.

Lưu ý: `up.sh` nạp file export đã sửa, nên migration đang chạy trên một database vốn đã ở trạng thái đích — nó phải idempotent. Nếu bước này báo lỗi thì script chưa idempotent, sửa cho tới khi chạy lại được.

- [ ] **Step 4: Commit**

```bash
git add docs/migrations/
git commit -m "docs(db): add phase 0 security migration and runbook"
```

- [ ] **Step 5: Bàn giao**

Báo người dùng: script nằm ở `docs/migrations/2026-09-09-phase0-security.sql`, cách chạy và cách kiểm tra ở `docs/migrations/README.md`. **Không tự chạy lên production.**

---

## Định nghĩa hoàn thành

- [ ] Task 0 đã chạy lại, và mọi khác biệt giữa export và production đều đã được giải thích hoặc vá
- [ ] `./db-tests/up.sh && ./db-tests/run.sh` xanh toàn bộ từ một máy sạch
- [ ] `docs/sql-export/08_rls.sql` khớp production, trừ ba policy `"Public Access"` đã bỏ hẳn
- [ ] `docs/sql-export/09_grants.sql` tồn tại và có trong "Run order" của README
- [ ] `docs/migrations/2026-09-09-phase0-security.sql` chạy sạch trên database dựng từ file export
- [ ] Không có lệnh ghi nào được chạy lên project `bufpmpehugzysvmbjlub`
- [ ] Người dùng đã nhận script và runbook
