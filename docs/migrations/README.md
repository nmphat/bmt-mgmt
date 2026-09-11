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

Chạy sau `2026-09-09-phase1-pricing.sql`. `session_court_bookings.court_name`
là `text` và nullable, và NULL đọc được trong thực tế: `set_session_court_bookings`
ghi thẳng `e->>'court_name'` không có fallback và không validate — một
phần tử payload thiếu key này, hoặc gửi JSON null, sẽ lặng lẽ ghi một
booking không tên sân. Script này thêm guard từ chối `court_name` thiếu,
JSON null, hoặc chỉ có khoảng trắng vào `set_session_court_bookings`, rồi
đặt cột `NOT NULL` để trạng thái vô nghĩa đó không còn biểu diễn được nữa.

### Trước khi chạy

```sql
SELECT count(*) FROM session_court_bookings
WHERE court_name IS NULL OR trim(court_name) = '';
-- kỳ vọng: 0
```

Đo ngày 2026-09-11 trên production: 47/47 dòng booking đều có `court_name`,
0 dòng NULL — constraint áp dụng sạch. Nếu câu trên ra khác 0 khi chạy
thật, dừng lại: có booking mới không tên xuất hiện sau lần đo, phải xử lý
dữ liệu đó trước khi `SET NOT NULL` (nếu không, `ALTER TABLE` sẽ báo lỗi và
tự rollback toàn bộ transaction).

### Sau khi chạy

```sql
SELECT is_nullable FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'session_court_bookings'
  AND column_name = 'court_name';
-- kỳ vọng: 'NO'
```

Idempotent: `SET NOT NULL` trên một cột đã `NOT NULL` là no-op, nên chạy
script này lần thứ hai không đổi gì — an toàn để chạy lại.

### Kiểm chứng cục bộ (Docker, không chạm production)

Dựng lại trạng thái "trước migration" (tức export của nhánh này, trừ thay
đổi của script này) bằng `git worktree add --detach <path> 822e8c2` — `822e8c2`
là commit ngay trước script này — rồi chạy `db-tests/up.sh` từ trong
worktree đó. Áp script này vào bed đó hai lần (lần hai không đổi gì, xác
nhận bằng snapshot `is_nullable` và thân hàm trước/sau), rồi chạy
`./db-tests/run.sh` (bộ test hiện tại) từ checkout HEAD. Chi tiết đầy đủ ở
`.superpowers/sdd/2026-09-09-pricing-model-and-create-session-ux/task-5b-report.md`.

### Rollback

```sql
BEGIN;
ALTER TABLE public.session_court_bookings ALTER COLUMN court_name DROP NOT NULL;
COMMIT;
```

Hàm `set_session_court_bookings` không cần nạp lại: guard mới trong thân
hàm chỉ từ chối các payload vốn dĩ đã vô nghĩa (thiếu/null/rỗng
`court_name`), không đổi hành vi trên payload hợp lệ, nên không có gì phải
hoàn tác ở đó.
