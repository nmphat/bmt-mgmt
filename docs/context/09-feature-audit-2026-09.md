# Feature Audit — 09/2026

> **Dùng file này khi:** Cần biết trạng thái thật của từng tính năng (code vs docs vs DB), trước khi lên kế hoạch sửa hoặc thêm tính năng.

**Phạm vi:** Toàn bộ `src/`, toàn bộ RPC/view/policy trên Supabase production (`bufpmpehugzysvmbjlub`), đối chiếu với `docs/context/00`–`08`.

**Phương pháp:** Đọc source code trực tiếp; query production ở chế độ chỉ đọc (không có lệnh ghi nào được thực thi); chạy Supabase advisor cho security và performance.

**Số liệu production tại thời điểm audit:** 36 members (35 chưa link `auth.users`, 1 admin), 53 sessions chưa xóa, 266 snapshots, 158 group payment requests, 54 dòng phụ thu.

---

## 1. Audit theo từng tính năng

Mỗi mục trả lời ba câu hỏi: chạy thế nào, UI nào đang có, thiếu gì.

### 1.1 Trang chủ — bảng nợ tổng hợp (`/`)

**Chạy thế nào.** `HomePage.vue` gọi `view_member_debt_summary` hai lần cho mỗi lần tải: một lần `head: true` để đếm, một lần lấy dữ liệu theo `range()`. Phân trang 20 dòng, nút "tải thêm" cộng dồn vào mảng. Tìm kiếm dùng `ilike` trên `display_name`. Nhấn trả tiền sẽ lấy toàn bộ snapshot chưa `paid` của những member được chọn, gọi `create_group_payment`, rồi mở `PaymentQRModal`.

**UI hiện có.** `HomeDebtTable.vue` (bảng + ô tìm kiếm + chọn nhiều), `PaymentQRModal.vue` (QR + polling), `CashPaymentModal.vue` (thu tiền mặt).

**Thiếu.**

- Không có RPC. Đây là màn hình chính của khách và là chỗ duy nhất trong app còn đọc thẳng view kèm `ilike` + `range` từ client.
- Hai lượt round-trip mỗi lần gõ tìm kiếm.
- `console.log('Snapshot IDs')` và `console.log('Group Data (RPC)')` còn nguyên trong bản production.

**Kết luận.** Luồng chính (khách xem nợ → quét QR → trả tiền) chạy đúng. Không phát hiện lỗi dữ liệu trên luồng này.

---

### 1.2 Danh sách buổi (`/sessions`)

**Chạy thế nào.** `DashboardView.vue` gọi `supabase.from('view_session_summary').select('*').order('session_date')`. Không giới hạn số dòng, không lọc, không tìm kiếm, không phân trang.

**UI hiện có.** Lưới thẻ session, badge trạng thái, nút "Tạo buổi" cho admin.

**Thiếu.**

- **RPC `search_sessions_list` tồn tại trong DB nhưng frontend chưa bao giờ gọi.** Toàn bộ tính năng mà `06-frontend-arch.md` mô tả — fuzzy search, lọc theo trạng thái, lọc theo khoảng ngày, đồng bộ URL query, infinite scroll bằng `IntersectionObserver`, cursor tổ hợp, khách chỉ thấy `waiting_for_payment` và `done` — đều **không có trong code**.
- Bằng chứng độc lập: Supabase performance advisor báo `idx_sessions_title_trgm`, `idx_sessions_status_deleted_at`, `idx_sessions_deleted_at` chưa từng được dùng lần nào. Ba index này được tạo riêng cho `search_sessions_list`.
- Route `/sessions` **không có** `meta.requiresAuth` hay `meta.requiresAdmin`, trong khi `03-auth-and-roles.md` ghi là admin-only. Khách chưa đăng nhập xem được toàn bộ buổi, kể cả buổi `open`.

---

### 1.3 Tạo buổi (`/create-session`)

**Chạy thế nào.** `CreateSessionView.vue` gọi `create_session_with_bookings` với `p_price_per_hour` **hardcode bằng 0**; ô "giá sân" trên form được truyền vào `p_court_fee_addon`. RPC tạo session, tự sinh interval 30 phút, chèn court bookings, rồi gọi `refresh_interval_courts`. Sau khi tạo, điều hướng sang `/session/:id?register=true`.

**UI hiện có.** Form một cột: tên buổi, ngày, giờ bắt đầu/kết thúc, giá sân, tiền cầu, danh sách sân (tên + giờ) với cảnh báo inline khi giờ sân nằm ngoài giờ buổi.

**Thiếu và lỗi.**

- **Sân đầu tiên bị hardcode.** `CreateSessionView.vue:41-43` khởi tạo `bookings` bằng giá trị cố định `{ court_name: 'Sân 1', start_time: '18:00', end_time: '20:00' }`. Đổi giờ buổi thì sân 1 vẫn giữ 18:00–20:00. Sân thêm sau (`addBooking`) thì lấy đúng giờ buổi, nên hành vi không nhất quán giữa sân đầu và các sân sau.
- **Mất ô `price_per_hour`.** Form chỉ có "giá sân" và nó đi vào `court_fee_addon`. Muốn đặt `price_per_hour` phải tạo buổi xong rồi vào trang chi tiết sửa. Hai khoản này cộng dồn trong công thức tính tiền, nên gọi cả hai là "giá sân" gây nhầm.
- **Không có giá riêng theo sân hoặc theo khung giờ.** Mô hình hiện tại chỉ có một `price_per_hour` cho cả buổi.
- **Không có ô nhập số quả cầu.** `shuttle_fee_total` là một con số nhập tay.
- Không xem trước được số interval sẽ sinh ra.
- Trình soạn court booking ở đây và trình soạn trong `SessionHeader.vue` là hai bản sao gần như giống hệt (`addBooking` / `removeBooking` / `validateBookingTime`), chưa tách thành component dùng chung.

---

### 1.4 Chi tiết buổi (`/session/:id`)

**Chạy thế nào.** `SessionDetailView.vue` (1.951 dòng) tự fetch mọi thứ: session summary, intervals, toàn bộ members, registrations, presence, snapshots, và `calculate_session_costs` để xem trước. Có realtime channel và cơ chế chống fetch chồng (`isFetching` + `pendingRefresh`). Thêm member gọi `add_member_to_session_full_presence` **lặp từng người** bằng `Promise.all`. Xóa member gọi `remove_member_from_session`. Điểm danh `upsert` thẳng vào `interval_presence`. Sửa session `update` thẳng bảng `sessions`. Chốt buổi gọi `finalize_session`.

**UI hiện có.** Header + form sửa inline, lưới điểm danh, bảng chi phí xem trước, `SessionExtraCharges`, bảng thanh toán, thanh group payment, `PaymentQRModal`, `ManualPaymentModal`.

**Thiếu và lỗi.**

- **Sáu component đã viết nhưng không nơi nào import.** Tổng 1.623 dòng chết:

  | Component | Dòng |
  | --- | --- |
  | `components/session/SessionHeader.vue` | 658 |
  | `components/session/SessionPaymentTable.vue` | 311 |
  | `components/session/SessionAttendanceGrid.vue` | 207 |
  | `components/session/SessionCostSummary.vue` | 142 |
  | `components/session/SessionGroupPaymentBar.vue` | 61 |
  | `components/MemberUnpaidSessionsModal.vue` | 244 |

  `SessionDetailView.vue` cài đặt lại toàn bộ các phần đó ngay trong file. Đợt refactor tách component đã viết xong nhưng chưa bao giờ được nối dây.

- **Không sửa được giờ buổi và giờ sân sau khi tạo.** Form sửa inline chỉ có tên, trạng thái, `price_per_hour`, `court_fee_addon`, `shuttle_fee_total`. Phần sửa giờ buổi và sửa court booking chỉ nằm trong `SessionHeader.vue` đang chết. Hệ quả: `recreate_session_intervals` và `refresh_interval_courts` **không được gọi từ bất kỳ code sống nào**. Đặt sai giờ sân lúc tạo thì không có đường sửa trong app.
  - **[FIXED 2026-09-11]** Giờ sửa được rồi. `SessionDetailView` gọi `recreate_session_intervals` khi giờ thay đổi, và `set_session_court_bookings` khi lưu. `SessionHeader.vue` đã bị xóa.
- Thêm nhiều member gọi N lần RPC thay vì dùng `batch_add_members_to_session` đã có sẵn.
- Hủy buổi `update` thẳng `sessions`. Các RPC `get_session_delete_impact`, `soft_delete_cancelled_session`, `soft_delete_cancelled_sessions_bulk` chưa có UI nào gọi.
- Nhánh dự phòng ở dòng 488 xóa thẳng `session_registrations`, để lại `interval_presence` mồ côi. Production đang có 3 dòng như vậy.

---

### 1.5 Phụ thu

**Chạy thế nào.** `SessionExtraCharges.vue` insert và delete thẳng bảng `session_extra_charges`. `calculate_session_costs` cộng `SUM(amount)` vào `final_total`.

**UI hiện có.** Form thêm (chọn member, số tiền, ghi chú) với hai layout mobile/desktop, danh sách dạng card trên mobile và bảng trên desktop.

**Thiếu và lỗi.**

- Dropdown nhận `:members="allMembers"` — toàn bộ 36 người, không lọc `is_active`, không lọc theo registration. Nhưng `calculate_session_costs` INNER JOIN `session_registrations`, nên phụ thu gán cho người chưa đăng ký buổi sẽ bị bỏ qua im lặng. Production hiện chưa có dòng nào như vậy.
- `:isAdmin="authStore.isAuthenticated"` — mọi tài khoản đã đăng nhập đều thấy nút thêm/xóa.
- Ghi thẳng bảng, chưa có RPC.

---

### 1.6 Thanh toán

**Chạy thế nào.** `finalize_session` sinh snapshot kèm mã `CL######`. Group QR qua `create_group_payment` với fingerprint md5 chống trùng, hạn 1 ngày. QR dựng từ `img.vietqr.io` với `bank_config`. Polling `check_qr_status` mỗi 2 giây, coi là xong khi còn thiếu dưới 1.000₫. Webhook Casso và SePay chạy bằng service role, match regex mã trong nội dung chuyển khoản, phân bổ tiền lần lượt theo thứ tự snapshot. Trigger `check_session_completion` tự chuyển session sang `done`.

**UI hiện có.** `PaymentQRModal` (QR + polling, dùng ở 3 trang), `PaymentView` (trang QR public để chia sẻ), `ManualPaymentModal` (trang chi tiết buổi), `CashPaymentModal` (trang chủ).

**Thiếu và lỗi.**

- `ManualPaymentModal` và `CashPaymentModal` là hai UI cho cùng một việc, cùng gọi `add_manual_payment`.
- `PaymentView` lấy số tiền từ query string. Sửa URL là đổi được số tiền trên QR.
- `PaymentView` không polling; chỉ `PaymentQRModal` polling.
- Không có màn hình đối soát giữa `paid_amount` và `session_payments`.

---

### 1.7 Thành viên (`/members`, `/member/:id`)

**Chạy thế nào.** `MemberView.vue` insert / update / delete thẳng bảng `members`. `MemberDetailView.vue` đọc `view_member_debt_summary` và `view_member_session_details`, cộng thêm một truy vấn `interval_presence` join `session_intervals` để hiện khung giờ đã đánh.

**UI hiện có.** Danh sách + form thêm + sửa inline + xóa; trang chi tiết có lịch sử buổi, tổng nợ, nút tạo QR (đơn và gộp).

**Thiếu.**

- Xóa member là hard delete. FK sẽ chặn nếu member đã có snapshot, nhưng lỗi trả về là thông báo Postgres thô.
- `MemberUnpaidSessionsModal.vue` viết xong nhưng không được dùng.
- Chưa có RPC cho thao tác ghi.

---

### 1.8 Cấu hình ngân hàng

**Chạy thế nào.** Hai đường song song: `composables/useBankConfig.ts` (dùng bởi `ProfileView`, `PaymentView`, `PaymentQRModal`) và `stores/bankConfig.ts` (dùng bởi `SettingsView`). Cả hai đọc/ghi thẳng bảng `bank_config`.

**UI hiện có.** `SettingsView.vue` (`/settings`, admin-only) và một khối quản lý ngân hàng trong `ProfileView.vue` (`/profile`, public route).

**Thiếu.**

- Trùng lặp hoàn toàn: hai màn hình, hai lớp state, một bảng.
- Cả hai ghi thẳng bảng.

---

## 2. Drift giữa docs, code và DB

### 2.1 Docs mô tả tính năng chưa tồn tại

`06-frontend-arch.md` mục "Sessions list pattern" mô tả `search_sessions_list`, đồng bộ URL query, infinite scroll và lọc theo quyền khách. Không có phần nào trong `DashboardView.vue`.

### 2.2 RPC có trong DB nhưng frontend không gọi

| RPC / View | Trạng thái |
| --- | --- |
| `search_sessions_list` | Không gọi ở đâu |
| `recreate_session_intervals` | Chỉ có trong `SessionHeader.vue` (component chết) |
| `refresh_interval_courts` | Chỉ có trong `SessionHeader.vue` (component chết) |
| `batch_add_members_to_session` | Không gọi ở đâu |
| `get_session_delete_impact` | Không gọi ở đâu |
| `soft_delete_cancelled_session` | Không gọi ở đâu |
| `soft_delete_cancelled_sessions_bulk` | Không gọi ở đâu |
| `gc_soft_deleted_sessions` | Không gọi ở đâu, chưa thấy cron |
| `view_attendance_log` | Không gọi ở đâu |
| `rpc_generate_draft` | Sót lại từ dự án khác; bảng tournament không tồn tại |

### 2.3 Ghi thẳng bảng thay vì RPC

Dự án ưu tiên RPC. Các chỗ còn ghi thẳng:

| File | Bảng | Thao tác |
| --- | --- | --- |
| `SessionDetailView.vue` | `sessions` | update (sửa, hủy) |
| `SessionDetailView.vue` | `interval_presence` | upsert |
| `SessionDetailView.vue` | `session_registrations` | delete (nhánh dự phòng) |
| `SessionExtraCharges.vue` | `session_extra_charges` | insert, delete |
| `MemberView.vue` | `members` | insert, update, delete |
| `SessionHeader.vue` (chết) | `sessions`, `session_court_bookings` | update, delete, insert |
| `useBankConfig.ts` | `bank_config` | update, delete |
| `stores/bankConfig.ts` | `bank_config` | insert, delete |

### 2.4 Sai lệch khác

- `create_session_with_bookings` có hai overload (7 tham số và 8 tham số). Frontend gọi bản 8. Bản 7 là code chết và tạo rủi ro chọn nhầm overload.
- Route `/settings` và các file `SettingsView.vue`, `CashPaymentModal.vue`, `stores/bankConfig.ts`, `components/session/*` chưa có trong `06-frontend-arch.md`.
- Thư mục `false/metadata-v1.3/` bị commit nhầm ở `5b2f7d7`, là rác sinh ra từ một lệnh pnpm.

---

## 3. Lỗi và rủi ro

### 3.1 P0 — Bảo mật

**RLS mở toàn quyền cho khách trên hai bảng tiền.**

```
session_costs_snapshot | policy "Public Access" | ALL | role public | USING(true) WITH CHECK(true)
session_payments       | policy "Public Access" | ALL | role public | USING(true) WITH CHECK(true)
```

Anon key nằm trong bundle JavaScript công khai. Với hai policy này, bất kỳ ai cũng có thể `UPDATE session_costs_snapshot SET paid_amount = final_amount` để tự xóa nợ — và trigger `check_session_completion` sẽ tự chuyển session sang `done` — hoặc `DELETE` sạch lịch sử thanh toán. Đây là lỗ hổng khai thác được ngay, không cần tài khoản.

Hướng sửa: bỏ policy `"Public Access"` trên cả hai bảng, giữ `"Public read access"` để trang `/pay` vẫn chạy, và đưa mọi thao tác ghi vào RPC `SECURITY DEFINER`.

Các vấn đề bảo mật mức thấp hơn:

- `members`, `sessions`, `session_intervals`, `interval_presence` có policy `ALL` cho `authenticated` với `USING(true)`. Hiện chỉ 1 tài khoản có auth nên rủi ro thực tế thấp, nhưng sẽ thành vấn đề ngay khi link tài khoản cho member.
- `handle_new_user()` và `rpc_generate_draft()` là `SECURITY DEFINER` và gọi được bởi `anon` qua `/rest/v1/rpc/`.
- 22 function thiếu `SET search_path`.
- `view_member_debt_summary` lộ `auth_user_id` ra public.
- Bốn view là `SECURITY DEFINER`.
- Auth chưa bật kiểm tra mật khẩu rò rỉ (HaveIBeenPwned).

### 3.2 P1 — Đúng đắn dữ liệu

1. **`finalize_session` không tính lại `status`.** Mệnh đề `ON CONFLICT DO UPDATE` chỉ cập nhật `final_amount` và ba cột breakdown. Nếu admin sửa phí rồi chốt lại một buổi đã có người trả, `final_amount` tăng nhưng `status` vẫn là `paid` → phát sinh nợ không hiện ở đâu. Production hiện chưa có dòng nào lệch, nhưng lỗi vẫn còn đó.

2. **Không có chốt chặn thu trùng.** Webhook và `add_manual_payment` cộng dồn độc lập. Production có 5 snapshot ở buổi `C30 TT ngày 08/02/2026` mà `SUM(session_payments) > paid_amount`, lệch **426.000₫**; mỗi người vừa có dòng `transfer` vừa có dòng `cash`. Báo cáo doanh thu dựng trên `session_payments` sẽ đội số.

3. **Phụ thu gán cho người chưa đăng ký buổi bị bỏ qua im lặng.** Xem mục 1.5.

4. **Ba dòng `interval_presence` mồ côi.** Chúng vẫn được đếm vào `real_present_count` trong `interval_stats`, làm cả buổi bị tính thiếu tiền.

5. **Giờ sân không sửa được sau khi tạo.** Nếu court booking không phủ đúng interval, `calculate_session_costs` rơi vào nhánh dự phòng và chia `court_fee_addon` đều theo số interval — kết quả khác với ý định của admin, và không có cách sửa trong app.

6. **28 snapshot có `paid_amount > 0` nhưng không có dòng `session_payments`** (1.271.000₫), toàn bộ thuộc tháng 2 và 3/2026. Đây là dữ liệu có trước khi có logging — lịch sử, không phải lỗi đang chạy.

### 3.3 P2 — Nợ kỹ thuật và hiệu năng

- 1.623 dòng component chết (mục 1.4).
- Trùng lặp: hai UI cấu hình ngân hàng, hai modal thu tiền mặt, hai trình soạn court booking.
- `SessionDetailView.vue` 1.951 dòng, gánh gần như toàn bộ domain session.
- `HomePage.fetchDebts` gọi hai lượt cho mỗi lần tìm kiếm hoặc phân trang.
- 158/158 `group_payment_requests` đã hết hạn, chưa có cron dọn.
- 8 khóa ngoại thiếu index, trong đó có `session_payments.snapshot_id` và `session_extra_charges.session_id`.
- 19 chỗ multiple permissive policy; 8 policy gọi `auth.uid()` không bọc trong `(select ...)`.
- Còn `console.log` trong `HomePage.vue`.
- `DEBT-004` trong `08-bugs-and-roadmap.md` vẫn đúng: nhiều nút thao tác dùng `isAuthenticated` thay vì `isAdmin` — `SessionExtraCharges`, và toàn bộ `SessionHeader.vue`.

---

## 4. Hướng nâng cấp đang cân nhắc

Ba hạng mục dưới đây do người dùng nêu, chưa chốt thiết kế:

1. **Sửa UX trang tạo buổi.** Bỏ hardcode sân đầu tiên; làm rõ sự khác nhau giữa `price_per_hour` và `court_fee_addon`; xem trước số interval.
2. **Giá theo từng sân và từng khung giờ.** Ví dụ: sân 1 từ 17h–18h giá 120k/giờ, 18h–19h giá 130k/giờ; sân 2 từ 18h–20h giá 135k/giờ. Mô hình hiện tại chỉ có một `price_per_hour` cho cả buổi.
3. **Tiền cầu tính theo ống.** Nhập giá một ống và số quả đã dùng thay vì nhập tổng tiền. Ví dụ: cầu Vina 315k một ống 12 quả, dùng 3 quả; cầu Victor 360k một ống, dùng 2 quả. Hiện `shuttle_fee_total` là số nhập tay, được chia theo trọng số sân của từng interval rồi chia đều cho người có mặt.
