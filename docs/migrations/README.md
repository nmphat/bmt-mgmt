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
- JWT admin (`0a5399cd-46ea-46b2-bb26-f2869a239e25`): `auth.uid()` trả đúng
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
- Phần giao diện: **chưa kiểm.** Phải mở trình duyệt thật mới kiểm được.
  Người vận hành xác nhận rồi ghi kết quả vào đây.

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
CREATE POLICY "Public Access" ON public.bank_config
  AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);

-- Mở lại lỗ hổng cũ: cho anon gọi lại ba RPC admin.
GRANT EXECUTE ON FUNCTION public.add_manual_payment(uuid, numeric, text) TO anon;
GRANT EXECUTE ON FUNCTION public.finalize_session(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.remove_member_from_session(uuid, uuid) TO anon;
```

Chỉ dùng khi thật sự phải quay lui: ba policy và ba grant này chính là lỗ
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
