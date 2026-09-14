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

Ảnh chụp số liệu trên production (`bufpmpehugzysvmbjlub`), đo ngày
2026-09-10, dùng để so sánh:

```sql
SELECT count(*) AS snapshots,
       sum(paid_amount) AS total_paid,
       sum(final_amount) AS total_final,
       count(*) FILTER (WHERE status = 'paid') AS paid_rows,
       count(*) FILTER (WHERE status = 'partial') AS partial_rows,
       count(*) FILTER (WHERE status = 'pending') AS pending_rows
FROM session_costs_snapshot;
```

Kết quả đo được ngày 2026-09-10 (baseline để so sánh):

| snapshots | total_paid | total_final | paid_rows | partial_rows | pending_rows |
| --- | --- | --- | --- | --- | --- |
| 266 | 17948000 | 19207000 | 250 | 0 | 16 |

Chạy lại câu SELECT ở trên ngay trước khi chạy migration và so với bảng
này — nếu lệch (có buổi mới finalize, có thanh toán mới), đó là hoạt động
bình thường của app, không phải lỗi; chỉ cần biết số nào là "trước" của
riêng bạn.

### Sau khi chạy

Ba con số `snapshots`, `total_paid`, `total_final` (và các *_rows) phải
**không đổi** so với ngay trước khi chạy — migration này không chạm vào dữ
liệu.

Xác nhận ba policy đã biến mất:

```sql
SELECT tablename, policyname FROM pg_policies
WHERE schemaname = 'public' AND policyname = 'Public Access';
-- kỳ vọng: 0 dòng
```

Xác nhận năm hàm đã là SECURITY DEFINER (riêng `health` không cần: hàm này
`LANGUAGE sql STABLE`, không đọc bảng nào, chỉ trả về hằng số `1`, nên
không có gì để lộ qua RLS):

```sql
SELECT proname, prosecdef FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND proname IN ('add_manual_payment','finalize_session',
                  'remove_member_from_session','create_group_payment');
-- kỳ vọng: prosecdef = true cho cả bốn
```

Xác nhận `anon` không còn gọi được ba RPC admin:

```sql
SELECT has_function_privilege('anon', 'public.add_manual_payment(uuid, numeric, text)', 'execute') AS add_manual_payment,
       has_function_privilege('anon', 'public.finalize_session(uuid)', 'execute') AS finalize_session,
       has_function_privilege('anon', 'public.remove_member_from_session(uuid, uuid)', 'execute') AS remove_member_from_session;
-- kỳ vọng: false cho cả ba
```

### Kiểm tra trên ứng dụng

1. Đăng xuất hoàn toàn. Mở trang chủ, chọn vài người còn nợ, bấm trả tiền.
   Mã QR phải hiện ra và polling phải chạy.
2. Mở `/pay?code=<một mã CL còn nợ>`. QR phải hiện đúng số tiền.
3. Đăng nhập admin. Chốt một buổi thử, thu một khoản tiền mặt, xóa một
   thành viên khỏi một buổi đang mở. Cả ba phải chạy.

### Kết quả kiểm chứng (2026-09-09-phase0-verify.sql)

Đã chạy trên production `bufpmpehugzysvmbjlub` ngày 2026-09-10, ngay trước
và ngay sau khi áp migration.

| Truy vấn | Trước | Sau |
| --- | --- | --- |
| 1. anon/authenticated theo hàm | cả 8 hàm: `anon = true`, `authenticated = true` | `add_manual_payment`, `finalize_session`, `remove_member_from_session`: `anon = false`, `authenticated = true`. `create_group_payment`, `check_qr_status`, `health`: `anon = true`. `handle_new_user`: cả hai `false`. `rpc_generate_draft`: không còn |
| 2. Policy "Public Access" còn lại | 2 dòng — `session_costs_snapshot`, `session_payments` (`bank_config` vốn đã không có, nó chỉ tồn tại trong file export) | **0 dòng** |
| 3. Số liệu tiền | 266 snapshot, paid 17948000, final 19207000, 250 paid / 0 partial / 16 pending, 239 dòng payment | **giống hệt từng cột** |
| 4. proacl thô của sáu hàm | mọi hàm đều có cả `=X/postgres` (PUBLIC) lẫn `anon=X/postgres` (grant trực tiếp của Supabase) | ba RPC admin còn `postgres=X \| authenticated=X \| service_role=X` — **mất cả hai đường**. `create_group_payment` giữ nguyên cả hai |
| 5. Hàm dò tạm `_phase0%` còn sót | 0 | **0** |

Truy vấn 4 là truy vấn đáng đọc nhất. Nó cho thấy vì sao hai lần revoke đầu
tiên của plan này không có tác dụng: `anon` vào được bằng hai đường độc lập,
cắt một đường thì đường kia vẫn mở, và `has_function_privilege` vẫn trả
`true`. Chỉ `REVOKE ... FROM PUBLIC, anon` mới cắt hết.

Kết quả kiểm hành vi bằng `_phase0_verify_guard()` (bước 5 của Task 9):

- Không JWT: `auth.uid()` trả `NULL`, guard **không** cho qua.
- JWT admin (uuid lấy từ bảng `members` trên production, không ghi ra đây): `auth.uid()` trả đúng
  UUID đó, guard **cho qua**.
- JWT người lạ (`11111111-2222-3333-4444-555555555555`): `auth.uid()` trả
  đúng UUID đó, guard **không** cho qua.
- `pg_proc` sau khi DROP: **0** hàm tên `_phase0%`.

Cả ba trường hợp đều đi qua đường `request.jwt.claims` dạng JSON — đúng
đường PostgREST dùng — bên trong một hàm `SECURITY DEFINER` có
`SET search_path = public, pg_temp`.

Kiểm trực tiếp lỗ hổng, chạy dưới role `anon` thật trên production trong một
transaction rồi `ROLLBACK`:

| Hành động của khách | Số dòng bị ảnh hưởng |
| --- | --- |
| `UPDATE session_costs_snapshot SET paid_amount = final_amount` | **0** |
| `DELETE FROM session_payments` | **0** |
| `UPDATE bank_config SET account_number = '0000000000'` | **0** |

Trước migration, câu đầu tiên sẽ xóa sạch nợ của cả câu lạc bộ.

Khách vẫn đọc được đủ thứ cần cho luồng chính: 266 snapshot, 1 `bank_config`
đang bật, 36 member, 60 session, 239 payment, 158 group request.

Kết quả kiểm luồng khách chưa đăng nhập (bước 6 -- đăng xuất, mở trang
chủ, chọn người còn nợ, bấm trả tiền, QR có hiện và polling có chạy
không):

- Phần cơ sở dữ liệu: đã kiểm ở bảng trên — khách đọc được, ghi không được,
  và `create_group_payment` cùng `check_qr_status` vẫn gọi được bằng `anon`.
- Phần giao diện: **đã kiểm, chạy tốt** (2026-09-10, sau khi áp migration).
  Khách chưa đăng nhập trả 170.000 cho một thành viên, mã nhóm `GR0D4586`,
  QR hiện và polling báo thành công. Đối chiếu trong database:

  | Bước | Kết quả |
  | --- | --- |
  | `create_group_payment` gọi bởi `anon` | `GR0D4586`, tổng 170000, 2 snapshot, 03:42:51 UTC |
  | Webhook ngân hàng ghi payment (`service_role`) | 2 dòng, `payment_method = transfer`, 03:43:16 UTC |
  | Snapshot sau khi trả | `CLE6459D` 80000/80000 và `CL6949ED` 90000/90000, cả hai `paid` |
  | Polling | thấy nợ còn lại đã hết, báo thành công |

  25 giây từ lúc tạo mã tới lúc tiền được ghi nhận. Đây là bằng chứng cho hai
  điều: `create_group_payment` ghi được `group_payment_requests` là nhờ
  `SECURITY DEFINER` (bảng đó không có policy INSERT/UPDATE nào cho `anon`),
  và các edge function ghi `session_payments` bằng `service_role` nên không
  hề cần policy `"Public Access"` vừa bị xóa.

### Ghi chú đã biết

- Revoke EXECUTE trên `handle_new_user()` KHÔNG làm hỏng signup:
  PostgreSQL kiểm tra quyền EXECUTE trên function của một trigger tại thời
  điểm TẠO trigger, không phải khi trigger CHẠY. Đã xác minh trên container
  local: với `has_function_privilege('authenticated',
  'public.handle_new_user()', 'execute')` trả về `false`, insert vào
  `auth.users` vẫn kích hoạt trigger bình thường.
- Production có trigger `on_auth_user_created` trên `auth.users` gọi
  `public.handle_new_user()`. Trigger này KHÔNG có trong
  `docs/sql-export/` -- dựng lại database chỉ từ export sẽ ra một database
  mà đăng ký tài khoản không tạo dòng `members` nào và cũng không báo lỗi.
  Đây là drift đã biết, cố tình chưa sửa ở Phase 0.

### Rollback

Script chạy trong một transaction nên lỗi giữa chừng sẽ tự quay lui. Nếu
đã COMMIT mà cần quay lại trạng thái cũ:

```sql
CREATE POLICY "Public Access" ON public.session_costs_snapshot
  AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY "Public Access" ON public.session_payments
  AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);

-- Mở lại lỗ hổng cũ: cho anon gọi lại ba RPC admin.
GRANT EXECUTE ON FUNCTION public.add_manual_payment(uuid, numeric, text) TO anon;
GRANT EXECUTE ON FUNCTION public.finalize_session(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.remove_member_from_session(uuid, uuid) TO anon;
```

`bank_config` không cần khôi phục gì ở đây: policy `"Public Access"` của nó
chưa từng tồn tại trên production, chỉ có trong file export (đã sửa ở Task
5) -- không có bước migration nào chạy trên production cần đảo ngược.

Chỉ dùng khi thật sự phải quay lui: hai policy và ba grant này chính là lỗ
hổng mà migration vá.

`rpc_generate_draft` (bị `DROP` ở bước 4) **không** có cách rollback bằng
SQL: thân hàm không được lưu ở đâu trong repo này. Đây là một hàm khoảng
200 dòng thuộc một app giải đấu (tournament) khác, đọc các bảng `teams`,
`team_members`, `registrations`, `user_profiles`, `user_quiz_scores`,
`draft_snapshots` và `audit_log` — không bảng nào trong số đó tồn tại ở
schema này, nên hàm chưa từng chạy thành công được ở đây. Nếu sau này thật
sự cần khôi phục, đường duy nhất là Supabase point-in-time recovery. Chữ ký
đầy đủ của hàm, để tham chiếu:

```sql
public.rpc_generate_draft(p_tournament_id uuid, p_num_teams integer, p_assigned_by text DEFAULT 'snake'::text)
```

## 2026-09-09-phase1-pricing.sql

Chạy sau `2026-09-09-phase0-security.sql`, trong một cửa sổ vắng người
dùng — script có `SET LOCAL lock_timeout = '5s'` nên một lần chạy bị nghẽn
sẽ tự fail nhanh và rollback thay vì treo, nhưng ba `ADD COLUMN` vẫn giữ
khóa ACCESS EXCLUSIVE trên `sessions`, `session_intervals` và
`session_court_bookings` tới lúc `COMMIT`. Đưa production từ trạng thái
trước Task 1 (per-court pricing + shuttle tube pricing) sang trạng thái mà
`docs/sql-export/` mô tả ở commit `2e22461`: thêm cột `price_per_hour` /
`court_cost` / `shuttle_usage`, bảng `shuttle_types`, constraint thứ tự thời
gian trên `session_court_bookings`, 5 hàm sửa/thêm (`refresh_interval_courts`,
`calculate_session_costs`, `create_session_with_bookings` 8 tham số,
`set_session_court_bookings`, `set_session_shuttle_usage`), drop overload 7
tham số của `create_session_with_bookings`, và grant/revoke đi kèm — kể cả
ba revoke sót lại từ Phase 0 (`soft_delete_cancelled_session`,
`soft_delete_cancelled_sessions_bulk`, `gc_soft_deleted_sessions`) mà lần
chạy phase0 trước chưa áp dụng lên production (đo ngày 2026-09-10, vẫn
`anon = true`).

**Không có backfill.** Default của các cột mới (`price_per_hour = 0`,
`court_cost = 0`, `shuttle_usage = '[]'`) là toàn bộ cơ chế giữ nguyên số
tiền của 53 buổi đang có: `court_cost = 0` khiến `calculate_session_costs`
rơi về công thức cũ. Không có UPDATE nào ghi dữ liệu trong script này.

### Trước khi chạy — kiểm tra dữ liệu rồi chụp ảnh tiền

Hai câu kiểm tra nhanh trước, vì `ADD CONSTRAINT` ở bước 1b của script
validate ngay lập tức — nếu có booking mới xuất hiện từ sau lần đo
2026-09-10 với `end_time <= start_time`, cả transaction sẽ abort (rollback
sạch, nhưng là một lỗi mù mờ ngay tại cổng production):

```sql
SELECT count(*) FROM session_court_bookings WHERE end_time <= start_time;  -- kỳ vọng: 0
SELECT to_regclass('public.shuttle_types');                                -- kỳ vọng: NULL
```

Sau đó dùng `docs/migrations/2026-09-09-phase1-pricing-money-snapshot.sql`
(per-member final_total, fingerprint của cùng dữ liệu đó, tổng cộng, và
ledger `session_costs_snapshot` đã chốt). Lưu kết quả ra `before.csv`:

```bash
psql "$DATABASE_URL" -t -A -F',' -f docs/migrations/2026-09-09-phase1-pricing-money-snapshot.sql > before.csv
```

Không có `psql` (ví dụ chạy trong Supabase SQL editor)? Chạy riêng câu
"Query 1b" trong file đó và chỉ cần chép lại một giá trị fingerprint.

### Sau khi chạy — chụp lại và so

Chạy lại đúng lệnh trên ra `after.csv`, rồi `diff before.csv after.csv`.
**Phải không có khác biệt nào** — cả theo từng thành viên trong từng buổi,
fingerprint, tổng cộng, lẫn ledger đã chốt. Có khác biệt nghĩa là một buổi
cũ vừa bị đổi tiền (hoặc tệ hơn, tiền bị xáo trộn giữa các thành viên trong
cùng buổi mà tổng buổi không đổi); quay lui ngay và tìm nguyên nhân trước
khi làm tiếp.

Kiểm tra thêm rằng chưa buổi nào rơi sang nhánh giá mới (cả ba cột mới):

```sql
SELECT count(*) FROM session_court_bookings WHERE price_per_hour <> 0;         -- kỳ vọng: 0
SELECT count(*) FROM session_intervals WHERE court_cost <> 0;                  -- kỳ vọng: 0
SELECT count(*) FROM sessions WHERE shuttle_usage <> '[]'::jsonb;              -- kỳ vọng: 0
```

Xác nhận `refresh_interval_courts` là `SECURITY DEFINER`, constraint mới đã
có, overload 7 tham số đã biến mất, và `anon` đã mất quyền gọi cả sáu hàm:
hai hàm mới (`set_session_court_bookings`, `set_session_shuttle_usage`), ba
hàm Phase 0 sót lại, và `refresh_interval_courts` — hàm thứ sáu, vì
migration này vừa biến nó thành `SECURITY DEFINER` (mandated addition #1),
nên nó cũng phải nằm trong diện revoke `anon`:

```sql
SELECT proname, prosecdef FROM pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname = 'refresh_interval_courts';
-- kỳ vọng: prosecdef = true

SELECT conname FROM pg_constraint WHERE conname = 'session_court_bookings_time_order_check';
-- kỳ vọng: 1 dòng

SELECT count(*) FROM pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname = 'create_session_with_bookings' AND pronargs = 7;
-- kỳ vọng: 0

SELECT has_function_privilege('anon', 'public.refresh_interval_courts(uuid)', 'execute') AS refresh_courts,
       has_function_privilege('anon', 'public.set_session_court_bookings(uuid, jsonb)', 'execute') AS set_bookings,
       has_function_privilege('anon', 'public.set_session_shuttle_usage(uuid, jsonb)', 'execute') AS set_shuttle,
       has_function_privilege('anon', 'public.soft_delete_cancelled_session(uuid)', 'execute') AS soft_delete,
       has_function_privilege('anon', 'public.soft_delete_cancelled_sessions_bulk(uuid[])', 'execute') AS soft_delete_bulk,
       has_function_privilege('anon', 'public.gc_soft_deleted_sessions(interval)', 'execute') AS gc;
-- kỳ vọng: false cho cả sáu
```

Một revoke lỡ tay cắt luôn cả `authenticated` sẽ làm hỏng ngay luồng sửa
buổi đang chạy mà truy vấn `anon` ở trên vẫn báo "an toàn" — nên phải kiểm
cả chiều ngược lại:

```sql
SELECT has_function_privilege('authenticated', 'public.refresh_interval_courts(uuid)', 'execute') AS refresh_courts,
       has_function_privilege('authenticated', 'public.set_session_court_bookings(uuid, jsonb)', 'execute') AS set_bookings,
       has_function_privilege('authenticated', 'public.set_session_shuttle_usage(uuid, jsonb)', 'execute') AS set_shuttle,
       has_function_privilege('authenticated', 'public.soft_delete_cancelled_session(uuid)', 'execute') AS soft_delete,
       has_function_privilege('authenticated', 'public.soft_delete_cancelled_sessions_bulk(uuid[])', 'execute') AS soft_delete_bulk;
-- kỳ vọng: true cho cả năm
```

`shuttle_types` là bảng mới; quyền của nó phụ thuộc `ALTER DEFAULT
PRIVILEGES` của Supabase có chạy đúng cho role đã chạy script hay không —
không gì trong export khẳng định điều đó, nên kiểm luôn:

```sql
SELECT has_table_privilege('authenticated', 'public.shuttle_types', 'select');
-- kỳ vọng: true
```

### Kiểm chứng cục bộ (Docker, không chạm production)

Dựng lại trạng thái "trước migration" bằng `git worktree add --detach <path>
3efe1a4` (commit ngay trước Task 1) rồi chạy `db-tests/up.sh` từ trong
worktree đó — `db-tests/up.sh` tự nạp `docs/sql-export/*.sql` của chính
worktree, nên bed dựng ra là schema cũ thật, không phải suy diễn lại bằng
tay. Áp script này vào bed đó hai lần (lần hai không đổi gì, xác nhận bằng
snapshot trước/sau của cột, index, policy, constraint và proacl của từng
hàm), rồi chạy `./db-tests/run.sh` (bộ test hiện tại, 10 file) từ checkout
HEAD — cả 10 file `PASS`. Chiều ngược lại (`./db-tests/down.sh &&
./db-tests/up.sh && ./db-tests/run.sh` từ `docs/sql-export/` hiện tại) cũng
10/10. Chi tiết đầy đủ, gồm log hai lần chạy và snapshot tiền trên bed cục
bộ, ở `.superpowers/sdd/2026-09-09-pricing-model-and-create-session-ux/task-5-report.md`.

### Rollback

**Cảnh báo: rollback này không trung lập với tiền.** `DROP COLUMN` trên
`price_per_hour`, `court_cost` và `shuttle_usage` là không thể hoàn tác. Nếu
đến lúc rollback đã có buổi nào dùng nhánh giá mới, xóa các cột đó rồi nạp
lại hàm cũ sẽ khiến buổi đó bị tính lại theo công thức cũ — tiền sân của nó
sụp về chỉ còn `court_fee_addon`, tức rollback tự nó là một sự kiện tiền,
không phải một cú undo vô hại. Chạy lại ba câu đếm ở mục "Sau khi chạy" bên
trên (`price_per_hour <> 0`, `court_cost <> 0`, `shuttle_usage <> '[]'`)
ngay trước khi rollback — **nếu bất kỳ câu nào khác 0, dừng lại và suy nghĩ
kỹ** trước khi chạy tiếp, vì rollback lúc đó sẽ đổi tiền của đúng những
buổi ấy.

Bốn hàm bên dưới phải nạp lại **trước** khi `DROP COLUMN` — plpgsql resolve
tên cột lúc THỰC THI, không phải lúc `CREATE FUNCTION`, nên nếu làm ngược
lại, mọi lệnh gọi `calculate_session_costs`/`refresh_interval_courts` (kể
cả từ `create_session_with_bookings`) sẽ báo lỗi "column does not exist"
suốt khoảng thời gian giữa `COMMIT` này và lúc nạp lại — hiển thị tiền,
chốt buổi, sửa buổi đều sập trong cửa sổ đó. Cả hai overload của
`create_session_with_bookings` (7 và 8 tham số) đều phải nạp lại: bản 8
tham số hiện tại (HEAD) ghi cột `price_per_hour` mà rollback này vừa xóa,
và giao diện đang bind vào đúng bản 8 tham số đó
(`src/views/CreateSessionView.vue:111`). Thân cả bốn hàm chép nguyên văn từ
commit `3efe1a4` (export cuối cùng trước Task 1):

```sql
BEGIN;

-- Cùng lý do với forward migration: ba DROP COLUMN bên dưới giữ khóa ACCESS
-- EXCLUSIVE trên cùng ba bảng, và rollback thường chạy trong điều kiện xấu
-- hơn (đã có sự cố). Fail nhanh thay vì treo.
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.refresh_interval_courts(p_session_id uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Update lại active_court_count cho từng interval thuộc session đó
    UPDATE session_intervals si
    SET active_court_count = (
        SELECT COUNT(*)
        FROM session_court_bookings b
        WHERE b.session_id = p_session_id
          -- Logic Overlap: Booking bắt đầu trước khi Interval kết thúc 
          -- VÀ Booking kết thúc sau khi Interval bắt đầu
          AND b.start_time < si.end_time
          AND b.end_time > si.start_time
    )
    WHERE si.session_id = p_session_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.calculate_session_costs(p_session_id uuid)
 RETURNS TABLE(member_id uuid, display_name text, final_total numeric, total_court_fee numeric, total_shuttle_fee numeric, total_extra_fee numeric, intervals_count integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_court_fee_addon      NUMERIC;
    v_price_per_hour       NUMERIC;
    v_total_shuttle_fee    NUMERIC;
    v_total_court_units    INT := 0;
    v_total_intervals      INT := 0;  -- fallback denominator when court bookings don't overlap
    v_ghost_count          INT;
BEGIN
    -- 1. Load session config
    SELECT s.court_fee_addon, s.price_per_hour, s.shuttle_fee_total
    INTO v_court_fee_addon, v_price_per_hour, v_total_shuttle_fee
    FROM sessions s
    WHERE s.id = p_session_id;

    -- 2. Total court-units (SUM of active_court_count across all intervals)
    SELECT COALESCE(SUM(si.active_court_count), 0),
           COUNT(si.id)
    INTO v_total_court_units, v_total_intervals
    FROM session_intervals si
    WHERE si.session_id = p_session_id;

    -- 3. Count ghost members
    WITH member_presence_counts AS (
        SELECT r.member_id, COUNT(p.id) FILTER (WHERE p.is_present = true) AS presence_count
        FROM session_registrations r
        JOIN session_intervals i ON i.session_id = r.session_id
        LEFT JOIN interval_presence p ON p.interval_id = i.id AND p.member_id = r.member_id
        WHERE r.session_id = p_session_id
        GROUP BY r.member_id
    )
    SELECT COUNT(*) INTO v_ghost_count
    FROM member_presence_counts
    WHERE presence_count = 0;

    -- 4. Compute costs
    RETURN QUERY
    WITH
    ghost_members AS (
        SELECT r.member_id
        FROM session_registrations r
        JOIN session_intervals i ON i.session_id = r.session_id
        LEFT JOIN interval_presence p ON p.interval_id = i.id AND p.member_id = r.member_id
        WHERE r.session_id = p_session_id
        GROUP BY r.member_id
        HAVING COUNT(p.id) FILTER (WHERE p.is_present = true) = 0
    ),

    interval_stats AS (
        SELECT
            i.id AS interval_id,
            i.active_court_count,
            COUNT(p.member_id) FILTER (WHERE p.is_present = true) AS real_present_count
        FROM session_intervals i
        LEFT JOIN interval_presence p ON p.interval_id = i.id
        WHERE i.session_id = p_session_id
        GROUP BY i.id, i.active_court_count
    ),

    member_interval_costs AS (
        SELECT
            m.id AS mem_id,
            m.display_name,

            -- A. COURT FEE — Option C additive (booking cost + addon)
            CASE
                WHEN (ist.real_present_count + v_ghost_count) > 0 THEN
                    CASE
                        WHEN gm.member_id IS NOT NULL OR p.is_present = true THEN
                            CASE
                                WHEN v_total_court_units > 0 THEN
                                    -- Normal: both booking cost and addon weighted by court-units
                                    (
                                        ((v_price_per_hour / 2.0) * ist.active_court_count)
                                        +
                                        (COALESCE(v_court_fee_addon, 0) * ist.active_court_count::numeric / v_total_court_units)
                                    ) / (ist.real_present_count + v_ghost_count)
                                WHEN v_total_intervals > 0 AND COALESCE(v_court_fee_addon, 0) > 0 THEN
                                    -- Fallback: court bookings don't overlap with intervals
                                    -- (e.g. timezone mismatch). Distribute addon equally per interval.
                                    -- price_per_hour booking cost = 0 (no valid court overlap).
                                    (v_court_fee_addon::numeric / v_total_intervals)
                                    / (ist.real_present_count + v_ghost_count)
                                ELSE 0
                            END
                        ELSE 0
                    END
                ELSE 0
            END AS court_cost,

            -- B. SHUTTLE FEE — only real attendees
            CASE
                WHEN ist.real_present_count > 0 AND v_total_court_units > 0 THEN
                    CASE
                        WHEN p.is_present = true THEN
                            (v_total_shuttle_fee * ist.active_court_count::numeric / v_total_court_units)
                            / ist.real_present_count
                        ELSE 0
                    END
                WHEN ist.real_present_count > 0 AND v_total_intervals > 0 THEN
                    -- Fallback for shuttle when no court overlap either
                    CASE
                        WHEN p.is_present = true THEN
                            (v_total_shuttle_fee / v_total_intervals) / ist.real_present_count
                        ELSE 0
                    END
                ELSE 0
            END AS shuttle_cost,

            CASE WHEN p.is_present = true THEN 1 ELSE 0 END AS is_present_flag

        FROM members m
        CROSS JOIN session_intervals i
        JOIN interval_stats ist ON ist.interval_id = i.id
        LEFT JOIN interval_presence p ON p.interval_id = i.id AND p.member_id = m.id
        JOIN session_registrations r ON r.member_id = m.id AND r.session_id = p_session_id
        LEFT JOIN ghost_members gm ON gm.member_id = m.id
        WHERE i.session_id = p_session_id
    ),

    extra_fee_calc AS (
        SELECT ex.member_id, SUM(ex.amount) AS total_extra
        FROM session_extra_charges ex
        WHERE ex.session_id = p_session_id
        GROUP BY ex.member_id
    )

    SELECT
        mic.mem_id,
        mic.display_name,
        COALESCE(CEIL((SUM(mic.court_cost) + SUM(mic.shuttle_cost) + COALESCE(ef.total_extra, 0)) / 1000.0) * 1000, 0) AS final_total,
        COALESCE(SUM(mic.court_cost), 0)   AS total_court_fee,
        COALESCE(SUM(mic.shuttle_cost), 0) AS total_shuttle_fee,
        COALESCE(ef.total_extra, 0)         AS total_extra_fee,
        COALESCE(SUM(mic.is_present_flag), 0)::INT AS intervals_count
    FROM member_interval_costs mic
    LEFT JOIN extra_fee_calc ef ON ef.member_id = mic.mem_id
    GROUP BY mic.mem_id, mic.display_name, ef.total_extra
    ORDER BY mic.display_name ASC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_session_with_bookings(p_title text, p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_price_per_hour numeric, p_shuttle_fee numeric, p_created_by uuid, p_bookings jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_session_id UUID;
    v_interval_start TIMESTAMPTZ;
    v_interval_end TIMESTAMPTZ;
    v_idx INT := 0;
    v_booking_item JSONB;
BEGIN
    INSERT INTO sessions (
        title, start_time, end_time, price_per_hour, shuttle_fee_total, created_by, status
    )
    VALUES (
        p_title, p_start_time, p_end_time, p_price_per_hour, p_shuttle_fee, p_created_by, 'open'
    )
    RETURNING id INTO v_session_id;

    v_interval_start := p_start_time;

    WHILE v_interval_start < p_end_time LOOP
        v_interval_end := v_interval_start + INTERVAL '30 minutes';

        IF v_interval_end > p_end_time THEN
            v_interval_end := p_end_time;
        END IF;

        INSERT INTO session_intervals (session_id, start_time, end_time, idx, active_court_count)
        VALUES (v_session_id, v_interval_start, v_interval_end, v_idx, 0);

        v_interval_start := v_interval_end;
        v_idx := v_idx + 1;
    END LOOP;

    IF p_bookings IS NOT NULL AND jsonb_array_length(p_bookings) > 0 THEN
        FOR v_booking_item IN SELECT * FROM jsonb_array_elements(p_bookings)
        LOOP
            INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time)
            VALUES (
                v_session_id,
                COALESCE(v_booking_item->>'court_name', v_booking_item->>'name', 'Sân 1'),
                (v_booking_item->>'start_time')::TIMESTAMPTZ,
                (v_booking_item->>'end_time')::TIMESTAMPTZ
            );
        END LOOP;
    ELSE
        INSERT INTO session_court_bookings (session_id, start_time, end_time, court_name)
        VALUES (v_session_id, p_start_time, p_end_time, 'Sân 1 (Mặc định)');
    END IF;

    PERFORM refresh_interval_courts(v_session_id);

    RETURN v_session_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_session_with_bookings(p_title text, p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_price_per_hour numeric, p_shuttle_fee numeric, p_created_by uuid, p_bookings jsonb, p_court_fee_addon numeric DEFAULT 0)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_session_id UUID;
    v_interval_start TIMESTAMPTZ;
    v_interval_end TIMESTAMPTZ;
    v_idx INT := 0;
    v_booking_item JSONB;
BEGIN
    INSERT INTO sessions (
        title, start_time, end_time, price_per_hour, shuttle_fee_total,
        court_fee_addon, created_by, status
    )
    VALUES (
        p_title, p_start_time, p_end_time, p_price_per_hour, p_shuttle_fee,
        p_court_fee_addon, p_created_by, 'open'
    )
    RETURNING id INTO v_session_id;

    v_interval_start := p_start_time;

    WHILE v_interval_start < p_end_time LOOP
        v_interval_end := v_interval_start + INTERVAL '30 minutes';

        IF v_interval_end > p_end_time THEN
            v_interval_end := p_end_time;
        END IF;

        INSERT INTO session_intervals (session_id, start_time, end_time, idx, active_court_count)
        VALUES (v_session_id, v_interval_start, v_interval_end, v_idx, 0);

        v_interval_start := v_interval_end;
        v_idx := v_idx + 1;
    END LOOP;

    IF p_bookings IS NOT NULL AND jsonb_array_length(p_bookings) > 0 THEN
        FOR v_booking_item IN SELECT * FROM jsonb_array_elements(p_bookings)
        LOOP
            INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time)
            VALUES (
                v_session_id,
                COALESCE(v_booking_item->>'court_name', v_booking_item->>'name', 'Sân 1'),
                (v_booking_item->>'start_time')::TIMESTAMPTZ,
                (v_booking_item->>'end_time')::TIMESTAMPTZ
            );
        END LOOP;
    ELSE
        INSERT INTO session_court_bookings (session_id, start_time, end_time, court_name)
        VALUES (v_session_id, p_start_time, p_end_time, 'Sân 1 (Mặc định)');
    END IF;

    PERFORM refresh_interval_courts(v_session_id);

    RETURN v_session_id;
END;
$function$;

DROP POLICY IF EXISTS shuttle_types_authenticated_read ON public.shuttle_types;
DROP POLICY IF EXISTS shuttle_types_admin_write ON public.shuttle_types;
DROP TABLE IF EXISTS public.shuttle_types;

ALTER TABLE public.session_court_bookings DROP CONSTRAINT IF EXISTS session_court_bookings_time_order_check;
ALTER TABLE public.session_court_bookings DROP COLUMN IF EXISTS price_per_hour;
ALTER TABLE public.session_intervals      DROP COLUMN IF EXISTS court_cost;
ALTER TABLE public.sessions               DROP COLUMN IF EXISTS shuttle_usage;

DROP FUNCTION IF EXISTS public.set_session_court_bookings(uuid, jsonb);
DROP FUNCTION IF EXISTS public.set_session_shuttle_usage(uuid, jsonb);

COMMIT;
```

Sau khi `COMMIT`, nếu thật sự cần quay lại đúng trạng thái production
trước migration này, mở lại EXECUTE cho `anon` trên ba hàm Phase 0
(`soft_delete_cancelled_session`, `soft_delete_cancelled_sessions_bulk`,
`gc_soft_deleted_sessions`) — nhưng đó chính là lỗ hổng Phase 0 đang vá,
nên chỉ làm khi bắt buộc.

Rollback này **không** mở lại `anon` trên `refresh_interval_courts`, và
sau rollback nó vẫn bị revoke: migration revoke `FROM PUBLIC, anon` trên
hàm đó, `CREATE OR REPLACE FUNCTION` (kể cả bản cũ nạp lại ở trên) giữ
nguyên ACL hiện có chứ không reset về mặc định, nên revoke đó sống sót qua
rollback. Đây là lựa chọn nên giữ, không phải một việc cần khôi phục: hàm
sau rollback là `SECURITY INVOKER` (không còn `SECURITY DEFINER`), nên nếu
`anon` gọi được thì cũng chỉ đụng RLS — không còn nguy hiểm như trước Task
1 — nhưng cũng không có lý do gì để trả lại quyền đó.

### Ghi chú đã biết

README này đã có hai playbook kiểm chứng chồng nhau (phần "Cách chạy" ở đầu
file, và các mục con "Trước/Sau khi chạy" riêng của từng migration) mà
không có mục nào dẫn rõ ràng đến mục kia. Đây là drift đã biết từ Phase 0,
chưa sửa ở đây — không thuộc phạm vi của Task 5.

## 2026-09-11-court-name-not-null.sql

Chạy sau `2026-09-09-phase1-pricing.sql`. Đã áp lên production.
`session_court_bookings.court_name` là `text` và nullable, và NULL đọc
được trong thực tế: `set_session_court_bookings` ghi thẳng
`e->>'court_name'` không có fallback và không validate — một phần tử
payload thiếu key này, hoặc gửi JSON null, sẽ lặng lẽ ghi một booking
không tên sân. Chỉ chặn ở RPC này thôi thì chưa đủ: `create_session_with_bookings`
dùng `COALESCE(v_booking_item->>'court_name', ..., 'Sân 1')`, và `COALESCE`
chỉ rơi xuống default khi giá trị là NULL — không rơi xuống khi giá trị là
`''` — nên đường đó vẫn ghi được tên rỗng bất kể migration này.

Script này có hai lớp, cố ý: một CHECK constraint (`court_name ~ '\S'`,
"có ít nhất một ký tự không phải khoảng trắng") trên cột — lớp chặn mọi
writer, kể cả `create_session_with_bookings` và bất kỳ đường ghi nào xuất
hiện sau này; và guard trong `set_session_court_bookings` — lớp biến một
lời gọi RPC hỏng thành thông báo lỗi tiếng Việt rõ ràng thay vì một lỗi
`23514` thô. Guard RPC dùng `e->>'court_name' ~ '^\s*$'` (khoảng trắng nói
chung — tab, xuống dòng, không chỉ dấu cách) chứ không dùng `trim() = ''`:
`trim()` một tham số chỉ cắt ký tự space (0x20), không cắt tab/xuống
dòng, nên `trim(E'\t') = ''` là false — một `court_name` chỉ có tab sẽ lọt
qua nếu dùng `trim()`.

### Trước khi chạy

```sql
SELECT count(*) FROM session_court_bookings
WHERE court_name IS NULL OR court_name ~ '^\s*$';
-- kỳ vọng: 0

SELECT count(*) FROM session_court_bookings
WHERE court_name ~ '^\s' OR court_name ~ '\s$';
-- kỳ vọng: 0 (không bắt buộc bởi constraint, chỉ để biết dữ liệu sạch tới đâu)
```

Đo ngày 2026-09-11 trên production: 47/47 dòng booking đều có `court_name`,
0 dòng NULL, 0 dòng khớp `^\s*$`, 0 dòng có khoảng trắng đầu/cuối, chỉ 2
tên sân khác nhau — cả `SET NOT NULL` lẫn CHECK constraint đều áp dụng
sạch. Nếu câu đầu ra khác 0 khi chạy thật, dừng lại: có booking mới
thiếu/rỗng tên xuất hiện sau lần đo, phải xử lý dữ liệu đó trước (nếu
không, `ALTER TABLE`/`ADD CONSTRAINT` sẽ báo lỗi và tự rollback toàn bộ
transaction).

### Sau khi chạy

```sql
SELECT is_nullable FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'session_court_bookings'
  AND column_name = 'court_name';
-- kỳ vọng: 'NO'

SELECT conname FROM pg_constraint
WHERE conname = 'session_court_bookings_court_name_not_blank'
  AND conrelid = 'public.session_court_bookings'::regclass;
-- kỳ vọng: 1 dòng
```

Idempotent cả hai bước: `SET NOT NULL` trên một cột đã `NOT NULL` là
no-op; `ADD CONSTRAINT` được bọc trong `DO $$ IF NOT EXISTS (... AND
conrelid = ...)` nên lần chạy thứ hai không làm gì cả. An toàn để chạy
lại.

### Kiểm chứng cục bộ (Docker, không chạm production)

Dựng lại trạng thái "trước migration" (tức export của nhánh này, trừ thay
đổi của script này) bằng `git worktree add --detach <path> 822e8c2` — `822e8c2`
là commit ngay trước script này — rồi chạy `db-tests/up.sh` từ trong
worktree đó. Áp script này vào bed đó hai lần (lần hai không đổi gì, xác
nhận bằng snapshot `is_nullable`, tên constraint, và `md5(prosrc)` của
thân hàm trước/sau), rồi chạy `./db-tests/run.sh` (bộ test hiện tại) từ
checkout HEAD. Chi tiết đầy đủ ở
`.superpowers/sdd/2026-09-09-pricing-model-and-create-session-ux/task-5b-report.md`.

### Rollback

```sql
BEGIN;
ALTER TABLE public.session_court_bookings DROP CONSTRAINT IF EXISTS session_court_bookings_court_name_not_blank;
ALTER TABLE public.session_court_bookings ALTER COLUMN court_name DROP NOT NULL;
COMMIT;
```

**Rollback này chỉ đảo ngược schema, không đảo ngược hành vi của RPC.**
Guard trong `set_session_court_bookings` vẫn còn nguyên sau khi chạy script
trên — hàm vẫn tiếp tục từ chối `court_name` thiếu/null/rỗng, bất kể cột
đã hết `NOT NULL` hay constraint đã bị xóa. Nếu lý do rollback chính là
guard đang từ chối một payload không lường trước được (chứ không phải một
sự cố về hiệu năng khóa hay tương tự), thì chỉ chạy script trên là **không
đủ** — phải nạp lại `set_session_court_bookings` từ `822e8c2` (bản không
có guard) trong cùng transaction rollback, nếu không hàm vẫn chặn đúng thứ
mà việc rollback định mở lại.

## 2026-09-11-view-total-court-cost.sql

Chạy sau `2026-09-09-phase1-pricing.sql` và **TRƯỚC**
`2026-09-11-court-pricing-guards.sql`. Đã áp lên production.
`view_session_summary.total_court_cost` vẫn tính theo công thức giờ cũ
(`active_court_count * price_per_hour / 2` + `court_fee_addon`) và bỏ qua
`session_intervals.court_cost`, nên mọi buổi tính theo giá sân — vốn có
`price_per_hour = 0` — hiện 0 đồng trong danh sách buổi trong khi thành viên
vẫn bị tính đủ tiền. Script đưa view về đọc `court_cost`.

### Đã bị thay thế — và tên file làm thứ tự chạy SAI

`2026-09-11-court-pricing-guards.sql` viết lại cùng view đó với biểu thức
chốt mô hình giá **một lần cho cả buổi**. Sắp theo tên file,
`court-pricing-guards` đứng **trước** `view-total-court-cost`, nên một người
chạy lại cả thư mục theo thứ tự tên file áp bản cũ **sau** bản mới và lặng lẽ
hoàn tác bản sửa tiền. Dựng lại được: container Postgres 17 từ export trước
nhánh + cả năm migration theo thứ tự tên file →
`db-tests/11_calc_with_court_cost.test.sql` đỏ với
`expected 60000, got 110000`.

Cách chữa **không** phải là nhớ thứ tự. Thân file đã được thay bằng đúng định
nghĩa hiện hành trong `docs/sql-export/05_views.sql`, nên chạy nó ở bất kỳ vị
trí nào, bao nhiêu lần cũng được, đều cho ra cùng một view đúng — không còn gì
cũ trong file để hoàn tác. Nội dung gốc nằm trong git history
(`43674cc:docs/migrations/2026-09-11-view-total-court-cost.sql`).

### Trước khi chạy

```sql
SELECT CASE WHEN pg_get_viewdef('public.view_session_summary'::regclass)
              ~ 'si.court_cost > ' THEN 'per-interval (bản đã bị thay thế)'
            WHEN pg_get_viewdef('public.view_session_summary'::regclass)
              ~ 'b.price_per_hour > ' THEN 'session-level (đúng, không cần chạy)'
            ELSE 'legacy (trước phase1-pricing)' END;
```

### Sau khi chạy

```sql
SELECT CASE WHEN pg_get_viewdef('public.view_session_summary'::regclass)
              ~ 'si.court_cost > ' THEN 'per-interval (SAI)'
            ELSE 'session-level (đúng)' END;
-- kỳ vọng: session-level (đúng)
```

`db-tests/drift-check.sql` nay có truy vấn `pg_get_viewdef` (query 7), nên
một production còn đang chạy bản per-interval hiện ra trong diff thay vì diff
sạch — trước đây drift check không đọc view nào cả và đây chính là chỗ một
trong hai bản sao của quyết định giá đang nằm.

### Rollback

Không có. `CREATE OR REPLACE VIEW` là idempotent và định nghĩa trong file
chính là định nghĩa hiện hành của `docs/sql-export/05_views.sql`.

## 2026-09-11-court-pricing-guards.sql

Chạy sau `2026-09-11-court-name-not-null.sql`. Đã áp lên production.
Bảy thay đổi, tất cả đều là `CREATE OR REPLACE` (không `DROP`), cộng một
trigger mới trên `session_extra_charges`. Không có `ALTER TABLE`, không có
backfill, không có `DELETE`.

1. **`calculate_session_costs`** — mô hình giá được chốt **một lần cho cả
   buổi** thay vì chọn lại theo từng interval. Trước đây nhánh tiền sân được
   chọn trên `ist.court_cost > 0`, không phân biệt được "khung này giá 0 đồng"
   với "buổi này tính theo `sessions.price_per_hour`", nên một buổi có cả giá
   sân thật lẫn `price_per_hour > 0` sẽ bịa thêm tiền cho những khung không có
   giá: 120000 tiền sân thật ra hóa đơn 220000. Nay cờ là "buổi này có ít nhất
   một `session_court_bookings.price_per_hour > 0` hay không"; có thì **mọi**
   interval dùng `court_cost`, không thì **mọi** interval dùng công thức giờ
   cũ. `court_fee_addon` **không đổi**, vẫn chia theo trọng số court-unit.
2. **`view_session_summary`** — bản sao của đúng biểu thức trên nằm trong
   `total_court_cost`; sửa cùng lúc để danh sách buổi không lệch với hóa đơn.
3. **`create_session_with_bookings`** — guard tiếng Việt cho booking đảo giờ
   và hai khung trùng giờ trên cùng một sân, chạy trước khi ghi dòng nào.
4. **`set_session_court_bookings`** — từ chối payload `NULL` (trước đây
   `jsonb_array_elements(NULL)` cho 0 dòng nên mọi guard đều lọt, `DELETE` vẫn
   chạy và cả buổi mất sạch tiền sân, không lỗi). `'[]'` **vẫn hợp lệ**: bỏ
   hết sân để quay về tính tiền bằng `court_fee_addon` là thao tác có thật.
   Thêm guard đảo giờ và trùng sân giống mục 3.
5. **`set_session_shuttle_usage`** — từ chối `tube_price` âm.
   `tube_price = 0` vẫn hợp lệ.
6. **`finalize_session`** — từ chối chốt khi vòng lặp không ghi được dòng
   snapshot nào. `UPDATE` trạng thái vẫn nằm **trước** vòng lặp (trigger
   `check_session_completion` chỉ nâng buổi lên `done` khi buổi đang ở
   `waiting_for_payment`, nên không dời xuống được); `RAISE` hủy cả lời gọi
   nên `UPDATE` đó được cuộn lại và buổi ở nguyên trạng thái cũ.
7. **`update_session_details` (hàm mới)** — gộp ba lời gọi rời nhau của màn
   hình sửa buổi vào một transaction, cộng trigger
   `check_charge_member_registered` chặn phụ thu cho người chưa đăng ký buổi.

### Trước khi chạy

```sql
-- 1) Money parity: bất biến của migration này.
WITH recomputed AS (
  SELECT s.id AS session_id, c.member_id, c.final_total
  FROM sessions s
  CROSS JOIN LATERAL calculate_session_costs(s.id) c
  WHERE s.deleted_at IS NULL
)
SELECT count(*) FILTER (WHERE r.final_total IS DISTINCT FROM snap.final_amount) AS mismatched_rows,
       COALESCE(sum(abs(r.final_total - snap.final_amount)), 0)                 AS vnd_drift,
       count(*)                                                                 AS compared_rows
FROM session_costs_snapshot snap
JOIN recomputed r ON r.session_id = snap.session_id AND r.member_id = snap.member_id;
-- kỳ vọng: 0 | 0 | 266

-- 2) Cờ mô hình giá.
SELECT count(*) FILTER (WHERE price_per_hour > 0) AS priced_bookings,
       count(*)                                   AS total_bookings
FROM session_court_bookings;
-- kỳ vọng: 0 | 47

-- 3) Phụ thu của người chưa đăng ký buổi.
SELECT count(*) FROM session_extra_charges ex
WHERE NOT EXISTS (SELECT 1 FROM session_registrations r
                  WHERE r.session_id = ex.session_id AND r.member_id = ex.member_id);
-- kỳ vọng: 0

-- 4) Buổi đang mở mà chốt ra 0 đồng cho tất cả.
SELECT s.id, s.title FROM sessions s
WHERE s.deleted_at IS NULL AND s.status = 'open'
  AND NOT EXISTS (SELECT 1 FROM calculate_session_costs(s.id) c WHERE c.final_total > 0);
```

Câu (2) là lý do bất biến tiền bạc đứng vững: **47/47 booking trên
production đều có `price_per_hour = 0`** (đo 2026-09-11), nên mọi buổi hiện
có đều đi nhánh "công thức giờ cũ" và không buổi nào đổi số tiền. Nếu
`priced_bookings` khác 0 khi chạy thật, **dừng lại**: có buổi đã dùng giá sân
thật và phải tính lại parity trước.

Câu (3) khác 0 **không** chặn script (trigger chỉ ràng buộc dòng ghi mới,
không đụng dòng cũ) nhưng phải xử lý trước: mỗi dòng đó là một khoản tiền
đang biến mất khỏi hóa đơn, không phải một dòng rác.

Câu (4) liệt kê những buổi sẽ **không chốt được** cho tới khi admin nhập giá
sân hoặc `court_fee_addon`. Đó là mục đích của mục 6, nhưng nên biết trước
để báo cho admin.

### Sau khi chạy

```sql
-- 1) Chạy lại đúng câu money parity ở trên. Kỳ vọng KHÔNG ĐỔI: 0 | 0 | 266.

-- 2) Quyền của các hàm SECURITY DEFINER -- đọc proacl THÔ.
SELECT p.proname, p.prosecdef, p.proconfig, p.proacl
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('update_session_details','set_session_court_bookings',
                    'set_session_shuttle_usage','refresh_interval_courts');
-- kỳ vọng cả bốn: prosecdef = t, proconfig = {"search_path=public, pg_temp"},
--                 proacl KHÔNG chứa '=X/' (PUBLIC) và KHÔNG chứa 'anon='

-- 3) Trigger phụ thu.
SELECT tgname FROM pg_trigger
WHERE tgrelid = 'public.session_extra_charges'::regclass AND NOT tgisinternal;
-- kỳ vọng: check_charge_member_registered
```

`has_function_privilege()` **không** thay được câu (2): `anon` tới được
EXECUTE bằng hai đường độc lập (grant mặc định của PostgreSQL cho `PUBLIC`
và `ALTER DEFAULT PRIVILEGES` của Supabase cấp thẳng cho `anon`), và
`has_function_privilege` trả `true` ở cả trường hợp hỏng lẫn không hỏng.
`update_session_details` là hàm **mới** nên nó nhận cả hai grant đó lúc được
tạo; hai dòng `REVOKE ... FROM PUBLIC, anon` ở cuối script là bắt buộc.

### Idempotent

Toàn bộ là `CREATE OR REPLACE` (giữ nguyên ACL sẵn có -- `DROP` rồi `CREATE`
sẽ áp lại default privileges của Supabase và lặng lẽ trả EXECUTE cho `anon`),
`DROP TRIGGER IF EXISTS` rồi `CREATE TRIGGER`, và `REVOKE`/`GRANT` vốn đã
idempotent. An toàn để chạy lại.

### Kiểm chứng cục bộ (Docker, không chạm production)

Dựng một container thứ hai từ export tại `41f557e` (commit ngay trước loạt
thay đổi này) bằng `git worktree add --detach <path> 41f557e`, nạp
`db-tests/helpers.sql` + export của worktree đó + `db-tests/seed.sql`, rồi áp
script này **hai lần**. Kết quả:

- Lần hai chạy sạch, không đổi gì (idempotent).
- `db-tests/drift-check.sql` trên container đã migrate và trên container dựng
  thẳng từ export của nhánh cho ra **222 dòng giống hệt nhau**, `diff` 0 dòng
  -- gồm md5 thân từng hàm, `prosecdef`, `proconfig`, `proacl` thô, mọi policy,
  index, cột và trigger.
- Cả 14 file trong `db-tests/` xanh trên container đã migrate.

### Rollback

```sql
BEGIN;
DROP TRIGGER IF EXISTS check_charge_member_registered ON public.session_extra_charges;
COMMIT;
```

Rồi nạp lại sáu hàm và view từ git tại `41f557e`
(`docs/sql-export/{05_views,06_functions}.sql`), bằng `CREATE OR REPLACE`,
**không** `DROP`. `update_session_details` có thể để lại: sau khi
`SessionDetailView` quay về ba lời gọi cũ thì không gì gọi nó, và nó đã bị
`REVOKE` khỏi `anon`.

## 2026-09-14-presence-guard-and-privilege-parity.sql

Chạy sau `2026-09-11-court-pricing-guards.sql`. Đã áp lên production.
Bốn hàm `CREATE OR REPLACE` (không `DROP`), một trigger mới trên
`interval_presence`, và **`ALTER TABLE` đầu tiên kể từ
`2026-09-11-court-name-not-null.sql`** — chỉ siết constraint, không sửa một
dòng dữ liệu nào. Không có backfill, không có `DELETE`.

1. **`calculate_session_costs`** — mẫu số chỉ đếm người **đã đăng ký** buổi.
   `real_present_count` trước đây đếm **mọi** dòng `interval_presence`, trong
   khi truy vấn ngoài join `session_registrations` nên chỉ người đã đăng ký
   mới ra hóa đơn. Một dòng điểm danh của người chưa đăng ký vì thế chia nhỏ
   tiền của cả buổi thêm một suất rồi vứt suất đó đi — không lỗi, không cảnh
   báo. Đo trên production: **một buổi** mang hình dạng này, trạng thái
   `cancelled`, 3 dòng điểm danh của một người chưa đăng ký, **0 snapshot và
   đã thu 0 đồng**; view báo 240000 còn máy tính tiền chỉ thu 180000. Không
   buổi đã chốt nào bị ảnh hưởng, nên money parity **không đổi**.
2. **`prevent_presence_for_unregistered_member` (hàm mới)** + trigger
   `check_presence_member_registered` `BEFORE INSERT OR UPDATE` trên
   `interval_presence` — cùng hình dạng với `check_charge_member_registered`
   của migration trước. Dòng `interval_presence` **không** mang `session_id`
   nên trigger phải lần ngược `interval_id → session_intervals → session_id`.
   Chặn ở tầng bảng vì `SessionDetailView.vue` upsert **thẳng** vào bảng qua
   PostgREST, không đi qua RPC nào. Trigger chỉ ràng buộc dòng **ghi mới**.
   `add_member_to_session_full_presence` và `batch_add_members_to_session`
   đều ghi registration **trước** rồi mới ghi presence, nên không hàm nào bị
   kẹt.
3. **`create_session_with_bookings`** — `SECURITY DEFINER`,
   `SET search_path = public, pg_temp`, admin check là câu lệnh đầu tiên
   (`'Chỉ admin được thực hiện thao tác này'`); route `/create-session` vốn đã
   `requiresAuth + requiresAdmin` và đây là caller duy nhất. Thêm guard tên
   sân rỗng/toàn khoảng trắng bằng **cùng một câu tiếng Việt** với
   `set_session_court_bookings` (`'Thiếu tên sân (court_name) trong dữ liệu
   đặt sân'`) thay vì lặng lẽ mặc định về `'Sân 1'` rồi để CHECK
   `court_name ~ '\S'` ném 23514 tiếng Anh lên màn hình. `COALESCE` ba tham
   số tiền về 0 để mục 5 không biến một trường bị thiếu thành 23502.
4. **`recreate_session_intervals`** — `SECURITY DEFINER`, `SET search_path`,
   admin check. Câu lệnh **đầu tiên** của hàm này xóa mọi dòng
   `interval_presence` của buổi. `update_session_details` gọi nó lồng bên
   trong; cả hai đều `SECURITY DEFINER` cùng một owner và `auth.uid()` đọc
   GUC `request.jwt.claims` chứ không đọc `current_user`, nên lời gọi lồng
   vẫn thấy đúng người gọi thật (`15_update_session_details.test.sql` pin
   điều này chứ không giả định).
5. **`sessions.price_per_hour` / `court_fee_addon` / `shuttle_fee_total`** —
   `SET DEFAULT 0` + `SET NOT NULL`. `price_per_hour = NULL` làm
   `(price_per_hour / 2.0) * active_court_count` ra `NULL`, `NULL` lan qua
   tổng, và cả buổi thành miễn phí trên nhánh giá cũ. Production: **0/54**
   buổi có `NULL` ở bất kỳ cột nào trong ba cột, nên không cần backfill.

### Trước khi chạy

```sql
-- 1) Money parity: bất biến của migration này.
WITH recomputed AS (
  SELECT s.id AS session_id, c.member_id, c.final_total
  FROM sessions s
  CROSS JOIN LATERAL calculate_session_costs(s.id) c
  WHERE s.deleted_at IS NULL
)
SELECT count(*) FILTER (WHERE r.final_total IS DISTINCT FROM snap.final_amount) AS mismatched_rows,
       COALESCE(sum(abs(r.final_total - snap.final_amount)), 0)                 AS vnd_drift,
       count(*)                                                                 AS compared_rows
FROM session_costs_snapshot snap
JOIN recomputed r ON r.session_id = snap.session_id AND r.member_id = snap.member_id;
-- kỳ vọng: 0 | 0 | 277

-- 2) Điểm danh của người chưa đăng ký -- thứ mục 1 sửa.
SELECT si.session_id, s.status, s.title, count(*) AS ghost_presence_rows,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM session_costs_snapshot cs
                                      WHERE cs.session_id = si.session_id)) AS rows_on_finalized_session
FROM interval_presence p
JOIN session_intervals si ON si.id = p.interval_id
JOIN sessions s ON s.id = si.session_id
WHERE NOT EXISTS (SELECT 1 FROM session_registrations r
                  WHERE r.session_id = si.session_id AND r.member_id = p.member_id)
GROUP BY si.session_id, s.status, s.title;
-- kỳ vọng: rows_on_finalized_session = 0 trên MỌI dòng.
-- Khác 0 thì DỪNG LẠI: mục 1 sẽ làm parity ở (1) lệch.

-- 3) Ba cột tiền có NULL nào không.
SELECT count(*) FILTER (WHERE price_per_hour IS NULL)    AS null_price,
       count(*) FILTER (WHERE court_fee_addon IS NULL)   AS null_addon,
       count(*) FILTER (WHERE shuttle_fee_total IS NULL) AS null_shuttle,
       count(*)                                          AS total_sessions
FROM sessions;
-- kỳ vọng: 0 | 0 | 0 | 54

-- 4) Quyền HIỆN TẠI của hai hàm sắp siết -- proacl THÔ.
SELECT p.proname, p.prosecdef, p.proconfig, p.proacl
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('create_session_with_bookings','recreate_session_intervals');
-- kỳ vọng TRƯỚC: prosecdef = f, proconfig = NULL, proacl còn '=X/postgres'
--                (PUBLIC) và/hoặc 'anon=X/postgres'
```

### Sau khi chạy

```sql
-- 1) Chạy lại đúng câu money parity ở trên. Kỳ vọng KHÔNG ĐỔI: 0 | 0 | 277.

-- 2) Quyền của hai hàm vừa siết -- đọc proacl THÔ.
SELECT p.proname, p.prosecdef, p.proconfig, p.proacl
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('create_session_with_bookings','recreate_session_intervals');
-- kỳ vọng cả hai: prosecdef = t, proconfig = {"search_path=public, pg_temp"},
--                 proacl = {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--                 -- KHÔNG có '=X/' (PUBLIC), KHÔNG có 'anon='

-- 3) Trigger điểm danh.
SELECT tgname FROM pg_trigger
WHERE tgrelid = 'public.interval_presence'::regclass AND NOT tgisinternal
ORDER BY tgname;
-- kỳ vọng: check_presence_member_registered, check_session_closed

-- 4) Ba cột tiền.
SELECT column_name, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'sessions'
  AND column_name IN ('price_per_hour','court_fee_addon','shuttle_fee_total')
ORDER BY column_name;
-- kỳ vọng cả ba: is_nullable = NO, column_default = 0
```

`has_function_privilege()` **không** thay được câu (2), đúng như ở migration
trước: `anon` tới được EXECUTE bằng hai đường độc lập và
`has_function_privilege` trả `true` ở cả trường hợp hỏng lẫn không hỏng.
Khác với `update_session_details`, hai hàm ở đây **đã tồn tại**, nên
`CREATE OR REPLACE` giữ nguyên ACL cũ của chúng — mà ACL cũ chính là cái phải
sửa. `REVOKE ... FROM PUBLIC, anon` ở cuối script là bắt buộc, và thiếu một
trong hai vế là no-op hoàn toàn.

### Idempotent

Bốn hàm là `CREATE OR REPLACE`, trigger là `DROP TRIGGER IF EXISTS` rồi
`CREATE TRIGGER`, `REVOKE`/`GRANT` vốn đã idempotent, và `SET DEFAULT` /
`SET NOT NULL` trên cột đã ở đúng trạng thái là no-op. An toàn để chạy lại.

### Kiểm chứng cục bộ (Docker, không chạm production)

Dựng container thứ hai từ `db-tests/helpers.sql` + export tại `59a5cef`
(commit ngay trước loạt thay đổi này) + `db-tests/seed.sql`. Trạng thái trước
khi chạy tái hiện đúng production: cả hai hàm `prosecdef = f`,
`proacl = {=X/postgres,postgres=X/postgres,anon=X/postgres,...}` — **cả hai**
đường vào của `anon` đều còn. Áp script **hai lần**:

- Lần hai chạy sạch, không đổi gì (idempotent).
- `db-tests/drift-check.sql` trên container đã migrate và trên container dựng
  thẳng từ export của nhánh cho ra **225 dòng giống hệt nhau**, `diff` 0 dòng.
- Thêm một lượt quét `is_nullable` trên toàn bộ `information_schema.columns`
  (query 1 của `drift-check.sql` **không** mang nullability): 0 dòng lệch.
- Cả 15 file trong `db-tests/` xanh trên container đã migrate.

### Rollback

```sql
BEGIN;
DROP TRIGGER IF EXISTS check_presence_member_registered ON public.interval_presence;
ALTER TABLE public.sessions ALTER COLUMN price_per_hour    DROP NOT NULL;
ALTER TABLE public.sessions ALTER COLUMN court_fee_addon   DROP NOT NULL;
ALTER TABLE public.sessions ALTER COLUMN shuttle_fee_total DROP NOT NULL;
COMMIT;
```

Rồi nạp lại ba hàm từ git tại `59a5cef` (`docs/sql-export/06_functions.sql`),
bằng `CREATE OR REPLACE`, **không** `DROP`. Quyền **không** tự quay lại khi
nạp lại thân hàm: muốn trả `create_session_with_bookings` /
`recreate_session_intervals` về trạng thái cũ thì phải
`GRANT EXECUTE ... TO PUBLIC, anon` một cách có chủ đích — nhưng đừng, đó
chính là lỗ hổng script này vá. `prevent_presence_for_unregistered_member`
có thể để lại: không trigger nào gọi nó sau khi `DROP TRIGGER`, và nó đã bị
`REVOKE` khỏi mọi role.

## 2026-09-14b-empty-interval-and-privilege-sweep.sql

Chạy sau `2026-09-14-presence-guard-and-privilege-parity.sql`. Chưa áp lên
production. Bảy hàm, tất cả `CREATE OR REPLACE` (không `DROP`), cộng bốn lệnh
REVOKE/GRANT. Không có `ALTER TABLE`, không có backfill, không có `DELETE`.

**Chữ `b` trong tên file là cố ý.** `2026-09-14-empty-...` sắp **trước**
`2026-09-14-presence-...` theo thứ tự tên file (`e` < `p`), nên chạy lại cả
thư mục sẽ áp presence-guard **sau** file này và hoàn tác
`calculate_session_costs` cùng `create_session_with_bookings` về bản cũ —
đúng cái bẫy mà `2026-09-11-view-total-court-cost.sql` đã dính. `14b` > `14-`
ở cả locale lẫn `LC_ALL=C`, nên thứ tự tên file nay trùng với thứ tự phải
chạy.

1. **`calculate_session_costs`** — hai lỗ cùng một hình dạng.
   *Tiền sân:* một interval mà **không ai** điểm danh trước đây làm cả biểu
   thức trả 0, nên toàn bộ tiền sân của khung đó không vào hóa đơn của ai,
   trong khi `view_session_summary` vẫn cộng đủ — hai con số trên cùng một
   màn hình admin lệch nhau và không có gì đối chiếu chúng. Dựng lại được
   bằng RPC đã ship: buổi 11:00–13:00, một sân 120000/h, hai người bỏ về sau
   tiếng đầu → danh sách 240000, hóa đơn cộng lại 120000. Nay khung đó chia
   đều cho **mọi người đã đăng ký buổi**: sân đã đặt là tốn tiền dù không ai
   bước vào, và người đặt là người nợ — đúng lý do ghost đang phải trả tiền
   sân. Ghost nằm trong nhóm đó nên chỉ chịu **đúng một suất**, không bị tính
   hai lần. Phép chia được đưa ra ngoài cả hai nhánh tử số, nên số học tử số
   không đổi một ký tự: buổi nào cũng có người ở mọi interval thì mẫu số vẫn
   là `real_present_count + v_ghost_count` và không một đồng nào xê dịch.
   *Tiền cầu:* cân theo riêng những interval **có người**
   (`v_present_court_units` / `v_present_intervals`) thay vì theo tổng đơn vị
   sân của mọi interval. Ghost không trả tiền cầu (luật đã chốt), nên phần
   của một khung không ai có mặt trước đây không có ai nhận.
2. **`finalize_session`** — từ chối chốt một buổi có `shuttle_fee_total > 0`
   mà chưa ai được điểm danh. Buổi toàn ghost vẫn có tiền sân để chia nên
   guard "không có khoản nào để chia" cũ **không** nổ: buổi chốt sạch sẽ với
   nguyên tiền cầu không đòi của ai. `RAISE` cuộn lại cả `UPDATE` trạng thái
   ở bước 1, y như guard cũ.
3. **`set_session_court_bookings`** — khung sân phải nằm **trong** giờ của
   buổi. `refresh_interval_courts` cắt overlap bằng `LEAST`/`GREATEST`, nên
   một sân 10:00–14:00 giá 120000/h trên buổi 11:00–12:00 ghi đủ 480000 vào
   `session_court_bookings` nhưng chỉ 120000 tới được interval — và ở đây
   view **đồng ý** với engine (cả hai đọc `court_cost` đã bị cắt), nên không
   màn hình nào hiện ra con số thật.
4. **`create_session_with_bookings`** — cùng guard đó ở đường tạo buổi. Buổi
   tạo được thì phải sửa lại được.
5. **`update_session_details`** — `COALESCE(p_court_fee_addon, 0)`, đúng như
   `create_session_with_bookings` đã làm từ vòng trước.
6. **`add_member_to_session_full_presence`** và
7. **`batch_add_members_to_session`** — `SECURITY DEFINER`,
   `SET search_path = public, pg_temp`, admin check là câu lệnh đầu tiên, và
   `REVOKE EXECUTE ... FROM PUBLIC, anon` + `GRANT ... TO authenticated`. Cả
   hai ghi `session_registrations` và `interval_presence` — số dòng
   `interval_presence` chính là mẫu số chia tiền. Trước đây `anon` giữ
   EXECUTE qua **cả hai** đường và chỉ bị RLS chặn; một thành viên đã đăng
   nhập mà không phải admin thì không bị chặn gì cả.

**Guard ở bước 3 và 4 chỉ chặn lần ghi SAU, nó không sửa dữ liệu đang có.**
Câu 3) trong khối "Trước khi chạy" liệt kê những booking hiện đang nằm ngoài
giờ buổi; sửa tay trên màn hình sửa buổi, script này không đụng vào chúng.

### Trước khi chạy

Năm câu, đầy đủ trong header của script. Bắt buộc:

```sql
-- 1) Money parity -- kỳ vọng: 0 | 0 | 277
WITH recomputed AS (
  SELECT s.id AS session_id, c.member_id, c.final_total
  FROM sessions s
  CROSS JOIN LATERAL calculate_session_costs(s.id) c
  WHERE s.deleted_at IS NULL
)
SELECT count(*) FILTER (WHERE r.final_total IS DISTINCT FROM snap.final_amount) AS mismatched_rows,
       COALESCE(sum(abs(r.final_total - snap.final_amount)), 0)                 AS vnd_drift,
       count(*)                                                                 AS compared_rows
FROM session_costs_snapshot snap
JOIN recomputed r ON r.session_id = snap.session_id AND r.member_id = snap.member_id;

-- 2) DỪNG LẠI NẾU KHÁC 0 -- interval không ai điểm danh trên buổi đã chốt tiền
SELECT count(*) AS empty_intervals_on_settled_sessions
FROM session_intervals si
JOIN sessions s ON s.id = si.session_id AND s.deleted_at IS NULL
WHERE EXISTS (SELECT 1 FROM session_costs_snapshot snap WHERE snap.session_id = s.id)
  AND NOT EXISTS (
    SELECT 1 FROM interval_presence p
    JOIN session_registrations r ON r.member_id = p.member_id AND r.session_id = s.id
    WHERE p.interval_id = si.id AND p.is_present = true);
```

Câu 2) là **điều kiện dừng**: đây là hình dạng duy nhất mà bước 1 làm đổi số
tiền. Đo trên production hiện tại: 0 buổi.

### Sau khi chạy

Năm câu, đầy đủ trong script. Bắt buộc: money parity lần hai phải giống hệt
(`0 | 0 | 277`); engine so với danh sách buổi trên mọi buổi chưa xóa phải cho
0 buổi lệch (phép đo mà parity **không** làm được — parity chỉ chứng minh
engine không đổi, nó không chứng minh engine thu đúng số tiền câu lạc bộ đã
trả); và `proacl` **thô** của hai hàm vừa gia cố:

```sql
SELECT p.proname, p.prosecdef, p.proconfig, p.proacl
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('add_member_to_session_full_presence',
                    'batch_add_members_to_session');
-- kỳ vọng cả hai: prosecdef = t
--                 proconfig = {"search_path=public, pg_temp"}
--                 proacl    = {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
```

Không dùng `has_function_privilege()` để kiểm tra: nó trả `true` ở **cả** hai
trường hợp (hỏng và không hỏng) nên không phân biệt được `anon` đi vào bằng
đường nào.

### Idempotent

Chạy lần hai không đổi gì: `CREATE OR REPLACE` ghi lại cùng một thân hàm,
`REVOKE`/`GRANT` trên một ACL đã đúng là no-op. Đã chạy hai lần liên tiếp
trong container, lần hai sạch.

### Kiểm chứng cục bộ (Docker, không chạm production)

Container thứ hai `bmt-mig`, dựng từ `db-tests/helpers.sql` + export tại
`43674cc` + `db-tests/seed.sql`. **Pre-state dựng lại đúng production**:

```
add_member_to_session_full_presence secdef=false cfg=- acl={=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
batch_add_members_to_session        secdef=false cfg=- acl={=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
```

- Script chạy hai lần; lần hai là no-op sạch.
- `db-tests/drift-check.sql` trên container đã migrate so với container dựng
  thẳng từ export nhánh: **262 dòng mỗi bên, `diff` ra 0 dòng.**
- Toàn bộ 15 file test xanh trên container đã migrate.
- **Replay toàn bộ thư mục theo thứ tự tên file** (export tại `3efe1a4` + cả
  tám migration): drift **0 dòng** so với container dựng thẳng từ export, và
  15/15 test xanh. Đây là phép đo mà C3 đã đỏ trước khi sửa.

### Rollback

Không có `ALTER TABLE`, không có dữ liệu bị ghi, nên rollback chỉ là nạp lại
bảy hàm ở bản `43674cc` bằng `CREATE OR REPLACE` (**không** `DROP` — `DROP`
rồi `CREATE` áp lại `ALTER DEFAULT PRIVILEGES` của Supabase và trả EXECUTE
cho `anon`), trong một transaction.

Phần quyền ở bước 8 **không** nên rollback: trả EXECUTE cho `anon` trên hai
hàm ghi bảng đó là mở lại đúng lỗ vừa bịt.
