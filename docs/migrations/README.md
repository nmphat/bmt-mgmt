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

Chạy sau `2026-09-09-phase0-security.sql`. Đưa production từ trạng thái
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

### Trước khi chạy — chụp ảnh tiền của mọi buổi

Dùng `docs/migrations/2026-09-09-phase1-pricing-money-snapshot.sql` (2 câu
SELECT: tổng tiền từng buổi, và tổng tất cả buổi). Lưu kết quả ra
`before.csv`:

```bash
psql "$DATABASE_URL" -t -A -F',' -f docs/migrations/2026-09-09-phase1-pricing-money-snapshot.sql > before.csv
```

### Sau khi chạy — chụp lại và so

Chạy lại đúng lệnh trên ra `after.csv`, rồi `diff before.csv after.csv`.
**Phải không có khác biệt nào** — cả theo từng buổi lẫn tổng cộng. Có khác
biệt nghĩa là một buổi cũ vừa bị đổi tiền; quay lui ngay và tìm nguyên nhân
trước khi làm tiếp.

Kiểm tra thêm rằng chưa buổi nào rơi sang nhánh giá mới:

```sql
SELECT count(*) FROM session_court_bookings WHERE price_per_hour <> 0;
-- kỳ vọng: 0
```

Xác nhận `refresh_interval_courts` là `SECURITY DEFINER` và `anon` đã mất
quyền gọi cả 5 hàm (2 hàm mới + 3 hàm Phase 0 sót lại):

```sql
SELECT proname, prosecdef FROM pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname = 'refresh_interval_courts';
-- kỳ vọng: prosecdef = true

SELECT has_function_privilege('anon', 'public.set_session_court_bookings(uuid, jsonb)', 'execute') AS set_bookings,
       has_function_privilege('anon', 'public.set_session_shuttle_usage(uuid, jsonb)', 'execute') AS set_shuttle,
       has_function_privilege('anon', 'public.soft_delete_cancelled_session(uuid)', 'execute') AS soft_delete,
       has_function_privilege('anon', 'public.soft_delete_cancelled_sessions_bulk(uuid[])', 'execute') AS soft_delete_bulk,
       has_function_privilege('anon', 'public.gc_soft_deleted_sessions(interval)', 'execute') AS gc;
-- kỳ vọng: false cho cả năm
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

```sql
BEGIN;

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

Sau đó nạp lại `refresh_interval_courts`, `calculate_session_costs` và
`create_session_with_bookings` (bản 7 tham số) từ commit trước Task 1
(`3efe1a4`), và mở lại EXECUTE cho `anon` trên ba hàm Phase 0
(`soft_delete_cancelled_session`, `soft_delete_cancelled_sessions_bulk`,
`gc_soft_deleted_sessions`) nếu thật sự cần quay lại đúng trạng thái
production trước migration này — nhưng đó chính là lỗ hổng Phase 0 đang vá,
nên chỉ làm khi bắt buộc.

### Ghi chú đã biết

README này đã có hai playbook kiểm chứng chồng nhau (phần "Cách chạy" ở đầu
file, và các mục con "Trước/Sau khi chạy" riêng của từng migration) mà
không có mục nào dẫn rõ ràng đến mục kia. Đây là drift đã biết từ Phase 0,
chưa sửa ở đây — không thuộc phạm vi của Task 5.
