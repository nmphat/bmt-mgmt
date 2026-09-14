# Design: Mô hình giá sân/tiền cầu mới + siết bảo mật + dọn UX trang tạo buổi

**Ngày:** 2026-09-09
**Trạng thái:** Đã duyệt, chờ chuyển sang implementation plan
**Audit nền:** [docs/context/09-feature-audit-2026-09.md](../../context/09-feature-audit-2026-09.md)

---

## 1. Bối cảnh

Audit toàn bộ codebase và production DB (`bufpmpehugzysvmbjlub`) ngày 09/09/2026 phát hiện ba nhóm vấn đề cần xử lý cùng đợt:

1. **Một lỗ hổng bảo mật khai thác được ngay trên production.** Hai bảng tiền mở toàn quyền cho khách chưa đăng nhập.
2. **Mô hình giá không đủ diễn đạt thực tế.** Một buổi chỉ có một `price_per_hour`, trong khi giá sân thực tế đổi theo sân và theo khung giờ. Tiền cầu là một con số nhập tay, không truy được ra loại cầu và số quả.
3. **UX trang tạo buổi có ba điểm sai cụ thể** đã định vị được trong code, cộng với 1.623 dòng component chết làm mất khả năng sửa giờ sân sau khi tạo.

Mục tiêu của đợt này: bịt lỗ hổng, đưa mô hình giá về đúng thực tế, và trả lại khả năng sửa court booking — mà **không làm thay đổi một đồng nào** trong 53 buổi đã có.

---

## 2. Các quyết định đã chốt

| Quyết định | Lựa chọn | Lý do |
| --- | --- | --- |
| Thứ tự | Bảo mật trước, tính năng sau | Lỗ hổng khai thác được bằng anon key có sẵn trong bundle |
| Lưu giá sân | Cột `price_per_hour` trên từng dòng `session_court_bookings` | Tái dùng bảng và trigger sẵn có; giá đổi theo giờ = tách dòng; không thêm bảng, không thêm join |
| Lưu tiền cầu | Bảng danh mục `shuttle_types` + cột `sessions.shuttle_usage` kiểu jsonb | Danh mục để khỏi gõ lại; jsonb snapshot giá nên đổi giá sau không động vào buổi cũ; engine tính tiền không đổi |
| Nơi nhập số quả cầu | Chỉ ở trang chi tiết buổi | Lúc tạo buổi chưa biết đánh hết bao nhiêu quả |
| Layout nhập giá sân | Nhóm theo sân, trong mỗi sân là các khung giá | Gọn khi nhiều sân; khớp cách admin nghĩ về sân |
| 6 component chết | Xóa 5, trích logic từ `SessionHeader` rồi xóa nốt | Chúng có trước design system v1.0; nối dây lại sẽ regress touch target mobile |

### Vì sao không cần chấp nhận sai số

Yêu cầu ban đầu cho phép lệch vài nghìn đồng nếu logic quá phức tạp. Không cần dùng tới: `120000 × 0.5h = 60000` và `315000 / 12 × 3 = 78750` đều là số nguyên. Phép `CEIL` lên 1.000₫ mỗi người đã có sẵn ở cuối `calculate_session_costs` và không đổi. Đợt này không tạo ra sai số mới.

---

## 3. Phase 0 — Bảo mật và tính đúng của tiền

Phase này độc lập với ba phase sau và đi thành PR riêng. Áp trước, xác minh xong rồi mới làm tiếp — để nếu ba phase sau phải quay lui thì bản vá bảo mật vẫn đứng nguyên.

### 3.1 Lỗ hổng

```
session_costs_snapshot | policy "Public Access" | ALL | role public | USING(true) WITH CHECK(true)
session_payments       | policy "Public Access" | ALL | role public | USING(true) WITH CHECK(true)
```

Anon key nằm trong bundle JavaScript công khai. Với hai policy này, bất kỳ ai cũng có thể chạy `UPDATE session_costs_snapshot SET paid_amount = final_amount` để tự xóa nợ — và trigger `check_session_completion` sẽ tự chuyển buổi sang `done` — hoặc `DELETE` sạch lịch sử thanh toán.

### 3.2 Vì sao không thể chỉ drop policy

`add_manual_payment`, `finalize_session`, `remove_member_from_session` đều là `SECURITY INVOKER` và ghi vào hai bảng trên. Bỏ policy mà không làm gì thêm thì admin mất khả năng chốt buổi, thu tiền mặt và xóa thành viên khỏi buổi.

### 3.3 Migration, theo đúng thứ tự

**Bước 1 — Chuyển 4 RPC sang `SECURITY DEFINER`**, kèm `SET search_path = public, pg_temp`:

- `add_manual_payment`
- `finalize_session`
- `remove_member_from_session`
- `create_group_payment`

**Bước 2 — Chèn kiểm tra quyền admin vào 3 RPC đầu**, ngay đầu thân hàm:

```sql
IF NOT EXISTS (
  SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'
) THEN
  RAISE EXCEPTION 'Chỉ admin được thực hiện thao tác này';
END IF;
```

Chèn thẳng ba lần thay vì tách hàm `is_admin()` — trong một migration bảo mật, ít thành phần mới thì ít bề mặt phải kiểm tra hơn.

Sau đó `REVOKE EXECUTE ... FROM anon` trên ba hàm này.

`create_group_payment` **giữ quyền gọi cho `anon`** — đó là luồng khách trả tiền ở trang chủ, luồng chính của app. Nó chỉ ghi vào `group_payment_requests`, chỉ đọc `session_costs_snapshot`.

**Bước 3 — Bỏ hai policy**:

```sql
DROP POLICY "Public Access" ON public.session_costs_snapshot;
DROP POLICY "Public Access" ON public.session_payments;
```

Policy `"Public read access"` giữ nguyên, nên `/pay`, polling `check_qr_status` và bảng nợ trang chủ không đổi hành vi.

**Bước 4 — Dọn hai hàm gọi được bởi anon**:

```sql
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon, authenticated;
DROP FUNCTION IF EXISTS public.rpc_generate_draft(uuid, integer, text);
```

`rpc_generate_draft` sót lại từ một dự án khác; các bảng tournament nó tham chiếu không tồn tại trong schema này.

### 3.4 Bug đi kèm: `create_group_payment` không cập nhật được `total_amount`

Nhánh tái sử dụng mã chạy `UPDATE group_payment_requests SET total_amount = v_total`. Bảng đó **không có policy UPDATE nào**, cho cả `anon` lẫn `authenticated`. RLS chặn im lặng: 0 dòng bị sửa, không có lỗi trả về. Hệ quả là khi dùng lại một mã `GR` còn hạn, `total_amount` giữ giá trị cũ, mà `check_qr_status` lấy đúng cột đó làm `total` — thanh tiến trình hiển thị sai khi số nợ đã đổi.

Chuyển `create_group_payment` sang `SECURITY DEFINER` ở Bước 1 sửa luôn bug này.

### 3.5 Bug đi kèm: `finalize_session` không tính lại `status`

Mệnh đề `ON CONFLICT DO UPDATE` hiện chỉ cập nhật `final_amount` và ba cột breakdown. Nếu admin sửa phí rồi chốt lại một buổi đã có người trả, `final_amount` tăng nhưng `status` vẫn là `paid` → phát sinh khoản nợ không hiện ở bất kỳ đâu, vì `view_member_debt_summary` lọc `status <> 'paid'`.

Sửa:

```sql
ON CONFLICT (session_id, member_id) DO UPDATE
SET final_amount       = EXCLUDED.final_amount,
    court_fee_amount   = EXCLUDED.court_fee_amount,
    shuttle_fee_amount = EXCLUDED.shuttle_fee_amount,
    extra_fee_amount   = EXCLUDED.extra_fee_amount,
    status = CASE
      WHEN session_costs_snapshot.paid_amount >= EXCLUDED.final_amount THEN 'paid'::payment_status
      WHEN session_costs_snapshot.paid_amount >  0                      THEN 'partial'::payment_status
      ELSE 'pending'::payment_status
    END;
```

Production hiện chưa có dòng nào lệch, nên đây là sửa phòng ngừa, không phải sửa dữ liệu.

### 3.6 Không ảnh hưởng

Webhook Casso và SePay dùng service role nên bỏ qua RLS hoàn toàn. `check_qr_status` chỉ đọc, giữ `SECURITY INVOKER`, chạy được nhờ policy `"Public read access"`.

### 3.7 Xác minh

1. Với anon key, thử `UPDATE session_costs_snapshot SET paid_amount = final_amount` → phải thất bại hoặc 0 dòng.
2. Với anon key, mở trang chủ, chọn vài người, bấm trả tiền → `create_group_payment` phải trả về mã và QR hiện đúng.
3. Đăng nhập admin: chốt một buổi thử, thu tiền mặt, xóa một thành viên khỏi buổi → cả ba phải chạy.
4. Tạo lại mã `GR` cho cùng một nhóm sau khi một người đã trả → `total_amount` trong DB phải khớp số nợ mới.

---

## 4. Phase 1 — Giá theo sân và theo khung giờ

### 4.1 Schema

```sql
ALTER TABLE session_court_bookings ADD COLUMN price_per_hour numeric NOT NULL DEFAULT 0;
ALTER TABLE session_intervals      ADD COLUMN court_cost     numeric NOT NULL DEFAULT 0;
```

Một sân có giá đổi theo giờ được biểu diễn bằng nhiều dòng cùng `court_name`:

| court_name | start_time | end_time | price_per_hour |
| --- | --- | --- | --- |
| Sân 1 | 17:00 | 18:00 | 120000 |
| Sân 1 | 18:00 | 19:00 | 130000 |
| Sân 2 | 18:00 | 20:00 | 135000 |

### 4.2 `refresh_interval_courts` tính thêm `court_cost`

Giữ nguyên phần tính `active_court_count`. Thêm, cho mỗi interval:

```sql
court_cost = COALESCE((
  SELECT SUM(
    b.price_per_hour
    * EXTRACT(epoch FROM (LEAST(b.end_time, i.end_time) - GREATEST(b.start_time, i.start_time))) / 3600.0
  )
  FROM session_court_bookings b
  WHERE b.session_id = i.session_id
    AND b.start_time < i.end_time
    AND b.end_time   > i.start_time
), 0)
```

### 4.3 `calculate_session_costs` đổi đúng một biểu thức

```
booking_cost = CASE
  WHEN si.court_cost > 0 THEN si.court_cost
  ELSE (v_price_per_hour / 2.0) * ist.active_court_count
END
```

Phần chia mẫu số (`real_present_count + ghost_count`), phần `court_fee_addon`, phần tiền cầu, phần phụ phí và phép `CEIL` cuối **giữ nguyên không đổi**.

### 4.4 Vì sao buổi cũ không đổi tiền

Toàn bộ court booking hiện có sẽ nhận `price_per_hour = 0` theo giá trị mặc định của cột. `refresh_interval_courts` sẽ tính ra `court_cost = 0` cho chúng, và nhánh `ELSE` giữ nguyên công thức cũ. Không cần script migrate dữ liệu lịch sử.

### 4.5 `price_per_hour` cấp session

Sau đợt này, `sessions.price_per_hour` chỉ còn hai vai trò: giá mặc định gợi ý khi thêm sân mới trên form, và nhánh dự phòng cho buổi cũ. Nó không còn tham gia công thức khi sân đã có giá riêng. Giữ cột lại, không xóa.

### 4.6 `create_session_with_bookings`

Mở rộng để đọc `price_per_hour` từ từng phần tử của `p_bookings jsonb`. Đồng thời `DROP` overload 7 tham số — nó là code chết và tạo rủi ro PostgREST chọn nhầm overload.

### 4.7 RPC mới thay cho ghi thẳng bảng

```
set_session_court_bookings(p_session_id uuid, p_bookings jsonb)
```

Thay toàn bộ court booking của buổi rồi gọi `refresh_interval_courts` trong cùng một transaction. Thay cho cặp `delete` + `insert` mà `SessionHeader.vue` đang làm từ client.

Hai RPC mới của Phase 1 và Phase 2 — `set_session_court_bookings` và `set_session_shuttle_usage` — dùng cùng khuôn với các RPC đã siết ở Phase 0: `SECURITY DEFINER`, `SET search_path = public, pg_temp`, kiểm tra quyền admin ở đầu thân hàm, và `REVOKE EXECUTE ... FROM anon`. Cả hai còn kiểm thêm `sessions.status = 'open'` và `RAISE EXCEPTION` nếu buổi đã chốt. Với RLS hiện tại thì `SECURITY INVOKER` cũng chạy được, nhưng viết theo khuôn này để chúng không vỡ khi các policy `ALL … USING(true)` cho `authenticated` được siết ở đợt sau.

---

## 5. Phase 2 — Tiền cầu theo ống

### 5.1 Schema

```sql
CREATE TABLE shuttle_types (
  id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name       text    NOT NULL,
  tube_price numeric NOT NULL,
  per_tube   int     NOT NULL DEFAULT 12,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE sessions ADD COLUMN shuttle_usage jsonb NOT NULL DEFAULT '[]';
```

RLS cho `shuttle_types`: `SELECT` cho `anon` và `authenticated`; `INSERT`/`UPDATE`/`DELETE` chỉ cho admin.

### 5.2 Hình dạng `shuttle_usage`

```json
[
  { "type_id": "…", "name": "Vina",   "tube_price": 315000, "per_tube": 12, "used": 3 },
  { "type_id": "…", "name": "Victor", "tube_price": 360000, "per_tube": 12, "used": 2 }
]
```

Tên và giá được **snapshot tại thời điểm nhập**. Sửa giá trong danh mục sau đó không làm đổi tiền của buổi cũ. `type_id` giữ lại để báo cáo theo loại cầu về sau, không dùng để tính tiền.

### 5.3 RPC ghi

```
set_session_shuttle_usage(p_session_id uuid, p_usage jsonb)
```

Ghi `shuttle_usage` và `shuttle_fee_total` trong **cùng một lệnh `UPDATE`**, nên không tồn tại đường nào để hai giá trị lệch nhau:

```sql
UPDATE sessions
SET shuttle_usage    = p_usage,
    shuttle_fee_total = COALESCE((
      SELECT SUM((e->>'tube_price')::numeric / NULLIF((e->>'per_tube')::numeric, 0) * (e->>'used')::numeric)
      FROM jsonb_array_elements(p_usage) e
    ), 0),
    updated_at = now()
WHERE id = p_session_id;
```

Yêu cầu admin và `status = 'open'`.

### 5.4 Engine tính tiền không đổi

`calculate_session_costs` vẫn đọc `sessions.shuttle_fee_total`, vẫn chia theo trọng số `active_court_count / total_court_units` của từng interval, rồi chia đều cho người có mặt. Ghost vẫn không chịu tiền cầu. **Không sửa một dòng nào** trong phần shuttle của hàm này.

Ví dụ kiểm chứng: Vina 315.000₫/ống 12 quả dùng 3 quả = 78.750₫; Victor 360.000₫/ống 12 quả dùng 2 quả = 60.000₫; `shuttle_fee_total` = 138.750₫.

---

## 6. Phase 3 — Giao diện

### 6.1 `CourtBookingEditor.vue` (component mới, dùng chung)

```
┌─ Sân 1 ──────────────────┐
│ 17:00→18:00  120.000đ/h  │
│ 18:00→19:00  130.000đ/h  │
│        [+ khung giờ]     │
└──────────────────────────┘
┌─ Sân 2 ──────────────────┐
│ 18:00→20:00  135.000đ/h  │
└──────────────────────────┘
         [+ Thêm sân]

Tổng tiền sân: 250.000 đ
```

DB lưu phẳng; component gom nhóm theo `court_name` khi hiển thị và trải phẳng lại khi lưu.

Validate, trong đó ba điều đầu trích từ `SessionHeader.vue`:

- Giờ kết thúc phải sau giờ bắt đầu.
- Khung giờ phải nằm trong giờ buổi.
- Không xóa được khung giờ cuối cùng của sân cuối cùng.
- **Mới:** hai khung giờ của cùng một sân chồng lên nhau thì **chặn lưu**, không chỉ cảnh báo. `refresh_interval_courts` cộng tiền của mọi booking phủ interval, nên khung chồng nhau sẽ tính tiền sân hai lần.

Design system v1.0: `min-h-11` cho mọi target chạm, `rounded-xl`, `font-bold`, `text-[20px]` cho tiêu đề. Mobile trước.

Props/emit:

```ts
defineProps<{ bookings: CourtBooking[]; sessionStart: string; sessionEnd: string; defaultPrice: number; disabled?: boolean }>()
defineEmits<{ 'update:bookings': [CourtBooking[]] }>()
```

### 6.2 `CreateSessionView.vue`

- Bỏ hardcode `{ court_name: 'Sân 1', start_time: '18:00', end_time: '20:00' }` ở dòng 41–43. Khung giờ đầu tiên bám theo giờ buổi và cập nhật khi giờ buổi đổi.
- Nhúng `CourtBookingEditor`, xóa bản sao trình soạn booking trong file.
- Đổi nhãn ô "giá sân" thành phụ phí sân cố định, ánh xạ rõ ràng vào `court_fee_addon`, kèm mô tả ngắn phân biệt với giá theo giờ của từng sân.
- **Bỏ ô tiền cầu.** `create_session_with_bookings` vẫn nhận `p_shuttle_fee`; truyền `0`. Buổi mới bắt đầu với `shuttle_fee_total = 0` và `shuttle_usage = []`, admin nhập cầu ở trang chi tiết sau khi đánh xong.
- Thêm dòng xem trước: "sẽ tạo N khung 30 phút".

### 6.3 `SessionDetailView.vue`

- Thêm khối sửa giờ buổi, gọi `recreate_session_intervals`, giữ nguyên cảnh báo đỏ "đổi giờ sẽ reset điểm danh" đã có trong `SessionHeader`.
- Nhúng `CourtBookingEditor`, lưu qua `set_session_court_bookings`.
- Thêm khối nhập cầu: dropdown chọn loại cầu từ `shuttle_types` đang `is_active`, stepper `−` / `+` cho số quả, tổng tiền cập nhật ngay khi gõ. Lưu qua `set_session_shuttle_usage`.
- Cả ba khối chỉ hiện khi `isSessionEditable` (admin và `status = 'open'`).

### 6.4 `SettingsView.vue`

Thêm mục quản lý danh mục loại cầu: danh sách, thêm, sửa, bật/tắt `is_active`. Trang này đã `requiresAdmin` sẵn.

---

## 7. Phase 4 — Dọn dẹp

Xóa hẳn:

- `src/components/session/SessionAttendanceGrid.vue`
- `src/components/session/SessionCostSummary.vue`
- `src/components/session/SessionPaymentTable.vue`
- `src/components/session/SessionGroupPaymentBar.vue`
- `src/components/MemberUnpaidSessionsModal.vue`
- `src/components/session/SessionHeader.vue` — sau khi đã trích logic sửa giờ và court booking sang `CourtBookingEditor`

Tổng 1.623 dòng.

Căn cứ: các file này bị bỏ rơi từ 11/03/2026, khi phase v1.0 `02-session-detail-task-cockpit` viết lại `SessionDetailView` theo hướng inline. Chúng có **0** lần dùng `min-h-11` và **0** lần `text-[20px]`, trong khi file sống có 26 và 6 — tức chúng có trước design system v1.0. Chúng cũng thiếu mobile card layout, admin gate, editability lock và hàng đợi refresh mà phase v1.0 đã thêm.

---

## 8. Kiểm chứng

**Điều kiện tiên quyết:** `node_modules` chưa được cài, `pnpm type-check` hiện fail ngay ở bước chạy binary (`vue-tsc: not found`). Cài dependency trước khi bắt đầu.

**Cổng cho engine tính tiền — bắt buộc.** Trước khi sửa `calculate_session_costs`, chạy hàm cho cả 53 buổi chưa xóa và lưu kết quả. Sau khi sửa, chạy lại và so sánh từng `member_id`. Chênh lệch phải bằng **0** cho mọi buổi cũ. Đây chính là cách `BUG-001` từng được xác minh, dùng lại nguyên phương pháp.

**Cổng cho Phase 0:** bốn bước xác minh ở mục 3.7.

**Cổng cho tính năng mới:** một buổi thử với sân 1 chia hai khung giá và sân 2 một khung giá; đối chiếu tổng tiền sân tính tay với `court_cost` từng interval. Một buổi thử với hai loại cầu; đối chiếu `shuttle_fee_total` với phép tính tay.

Mọi migration đều do người dùng tự apply lên production. Không có lệnh ghi nào được chạy tự động lên project thật.

---

## 9. Ngoài phạm vi đợt này

Danh sách đầy đủ mọi finding của bản audit **không** được xử lý trong bốn phase trên. Chi tiết và bằng chứng nằm trong [09-feature-audit-2026-09.md](../../context/09-feature-audit-2026-09.md). Ghi ở đây để không finding nào thất lạc giữa hai tài liệu.

### 9.1 Bảo mật còn tồn (không chặn được như P0 nhưng cần làm)

- **Policy `ALL` với `USING(true)` cho `authenticated`** trên `members`, `sessions`, `session_intervals`, `interval_presence`. Hiện chỉ 1 tài khoản có auth nên rủi ro thực tế thấp, nhưng sẽ bung ngay khi link tài khoản cho member. Hai RPC mới ở Phase 1 và 2 đã viết sẵn theo khuôn `SECURITY DEFINER` để không vỡ khi siết nhóm policy này.
- **22 function thiếu `SET search_path`.** Phase 0 chỉ vá 6 hàm nó chạm tới; 16 hàm còn lại vẫn hở.
- **Bốn view là `SECURITY DEFINER`**: `view_attendance_log`, `view_member_debt_summary`, `view_member_session_details`, `view_session_summary`.
- **`view_member_debt_summary` lộ `auth_user_id`** ra `anon`. Bỏ cột đó khỏi view.
- **Auth chưa bật kiểm tra mật khẩu rò rỉ** (HaveIBeenPwned). Bật trong dashboard, không cần migration.
- `pg_trgm` cài trong schema `public`.

### 9.2 Tiền và đối soát

- **Lệch 426.000₫** giữa `SUM(session_payments)` và `paid_amount` ở 5 snapshot của buổi `C30 TT ngày 08/02/2026` — mỗi người vừa có dòng `transfer` vừa có dòng `cash`. Chưa có chốt chặn thu trùng và chưa có màn hình đối soát.
- **28 snapshot có `paid_amount > 0` nhưng không có dòng `session_payments`** (1.271.000₫), toàn bộ thuộc tháng 2 và 3/2026. Là dữ liệu có trước khi có logging — **không cần sửa**, chỉ cần nhớ khi dựng báo cáo doanh thu để không hiểu nhầm là thất thoát.
- **Ba dòng `interval_presence` mồ côi**, vẫn được đếm vào `real_present_count` nên buổi liên quan bị tính thiếu tiền. Nguồn là nhánh dự phòng `SessionDetailView.vue:488` xóa thẳng `session_registrations`; bỏ nhánh đó và dọn ba dòng.
- **Phụ thu vẫn cho chọn người chưa đăng ký buổi.** `calculate_session_costs` INNER JOIN `session_registrations` nên khoản đó bị bỏ qua im lặng. Production hiện chưa có dòng nào như vậy.

### 9.3 Quyền trên giao diện

- Route `/sessions` thiếu `meta.requiresAuth` và `meta.requiresAdmin`, trong khi docs ghi là admin-only.
- `SessionExtraCharges` nhận `:isAdmin="authStore.isAuthenticated"` — mọi tài khoản đăng nhập đều thấy nút thêm/xóa phí. Đây là `DEBT-004` trong `08-bugs-and-roadmap.md`, vẫn chưa đóng.

### 9.4 Code chưa nối dây và code trùng lặp

- **`search_sessions_list` chưa được frontend gọi.** `/sessions` không tìm kiếm, không lọc, không phân trang. Ba index `idx_sessions_title_trgm`, `idx_sessions_status_deleted_at`, `idx_sessions_deleted_at` chưa từng được dùng.
- `batch_add_members_to_session` chưa dùng — `SessionDetailView` gọi `add_member_to_session_full_presence` lặp N lần.
- `get_session_delete_impact`, `soft_delete_cancelled_session`, `soft_delete_cancelled_sessions_bulk` chưa có UI nào gọi. `gc_soft_deleted_sessions` chưa thấy cron.
- View `view_attendance_log` chưa dùng ở đâu.
- Hai UI cấu hình ngân hàng trùng nhau: `ProfileView` dùng `useBankConfig`, `SettingsView` dùng `useBankConfigStore`. Gộp một.
- Hai modal thu tiền mặt trùng nhau: `ManualPaymentModal` (trang chi tiết buổi) và `CashPaymentModal` (trang chủ), cùng gọi `add_manual_payment`.
- `SessionDetailView` vẫn 1.951 dòng sau đợt này. Tách nhỏ ở đợt sau, theo design system v1.0 — không phải bằng cách khôi phục các component đã xóa ở Phase 4.

**Còn ghi thẳng bảng, trái chủ trương RPC-first.** Đợt này chỉ chuyển được hai đường: court booking (`set_session_court_bookings`) và tiền cầu (`set_session_shuttle_usage`). Còn lại:

| File | Bảng | Thao tác |
| --- | --- | --- |
| `SessionDetailView.vue` | `sessions` | update khi sửa buổi và khi hủy buổi |
| `SessionDetailView.vue` | `interval_presence` | upsert khi điểm danh |
| `SessionDetailView.vue` | `session_registrations` | delete ở nhánh dự phòng (xem 9.2) |
| `SessionExtraCharges.vue` | `session_extra_charges` | insert, delete |
| `MemberView.vue` | `members` | insert, update, delete |
| `useBankConfig.ts` | `bank_config` | update, delete |
| `stores/bankConfig.ts` | `bank_config` | insert, delete |

Đường hủy buổi đáng ưu tiên: nó nên gọi `soft_delete_cancelled_session` kèm `get_session_delete_impact` để xem trước, thay vì `update status = 'cancelled'` rồi bỏ đó.

**Xóa thành viên là hard delete.** `MemberView.deleteMember` chạy `delete` thẳng; FK sẽ chặn nếu thành viên đã có snapshot, nhưng thứ người dùng nhìn thấy là thông báo lỗi Postgres thô. Nên chuyển sang `is_active = false`.

**`PaymentView` không polling.** Chỉ `PaymentQRModal` polling `check_qr_status`. Người quét QR từ link chia sẻ không thấy trạng thái tự cập nhật. `05-payment-domain.md` đã ghi nhận điều này là hiện trạng có chủ đích, nhưng đáng nâng cấp.

### 9.5 Hiệu năng

- `HomePage.fetchDebts` gọi hai lượt cho mỗi lần tìm kiếm hoặc phân trang (một `head: true` để đếm, một để lấy dữ liệu). Gộp thành một RPC cursor giống `search_sessions_list`.
- 158/158 `group_payment_requests` đã hết hạn, chưa có cron dọn.
- 8 khóa ngoại thiếu index, trong đó có `session_payments.snapshot_id` và `session_extra_charges.session_id`.
- 19 chỗ multiple permissive policy; 8 policy gọi `auth.uid()` không bọc trong `(select …)`.

### 9.6 Dọn dẹp và tài liệu

- `console.log('Snapshot IDs')` và `console.log('Group Data (RPC)')` còn trong `HomePage.vue` bản production.
- Thư mục rác `false/metadata-v1.3/` bị commit nhầm ở `5b2f7d7`.
- `PaymentView` lấy số tiền từ query string; sửa URL là đổi được số tiền trên QR.
- `06-frontend-arch.md` chưa có `SettingsView.vue`, `CashPaymentModal.vue`, `stores/bankConfig.ts`, `components/session/*`; mục "Sessions list pattern" mô tả tính năng chưa tồn tại. Cần cập nhật cùng lúc với Phase 4.

---

## 10. Rủi ro

| Rủi ro | Giảm thiểu |
| --- | --- |
| Migration Phase 0 làm hỏng luồng khách trả tiền | `create_group_payment` giữ quyền gọi cho `anon`; policy `"Public read access"` giữ nguyên; bốn bước xác minh ở 3.7 |
| Sửa engine làm lệch tiền buổi cũ | Nhánh `ELSE` giữ nguyên công thức cũ; cổng so sánh 53 buổi, chênh lệch phải bằng 0 |
| `shuttle_fee_total` lệch với `shuttle_usage` | Cả hai được ghi trong cùng một lệnh `UPDATE` bên trong RPC |
| Đổi giá trong danh mục làm đổi tiền buổi cũ | `shuttle_usage` snapshot tên và giá tại thời điểm nhập |
| Xóa nhầm component đang được dùng | Đã kiểm: cả sáu file không được import ở bất kỳ đâu trong `src/` |
