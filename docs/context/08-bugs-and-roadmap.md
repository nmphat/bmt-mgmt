# Known Bugs & Roadmap

> **Dùng file này khi:** Debug, planning sprint, hoặc cần biết trạng thái hiện tại của app.

---

## Trạng thái hiện tại (March 2026)

- ✅ **Hoạt động ổn:** Auto-detect thanh toán từ QR (banking webhook + polling)
- ✅ **Fixed:** Tính tiền sân sai (BUG-001 — court_fee_total thay vì price_per_hour)
- 🔧 **Đang rework:** Trang Create Session
- ❌ **Bugs đã biết:** Mobile layout vỡ

---

## Bugs đã biết

### ✅ BUG-001: Tính tiền sai sau khi thêm weighted interval + extra charges

**Mô tả:** Sau khi update tính năng `active_court_count` theo từng interval (weighted) và thêm `session_extra_charges`, kết quả tính tiền bị sai.

**Nguyên nhân gốc rễ (đã xác định):**
RPC `calculate_session_costs` tính tiền sân từ `price_per_hour` thay vì `court_fee_total`. Hầu hết
các session thực tế đặt `price_per_hour = 0` và nhập tổng tiền sân vào `court_fee_total`, khiến
tiền sân luôn trả về 0 sau khi refactor.

**Fix đã áp dụng (migration `fix_calculate_session_costs_court_fee_v2`):**

- Khi `court_fee_total > 0`: phân bổ theo `court_fee_total × courts_in_interval / total_court_units`
  (giống cách tính `shuttle_fee_total`) — đây là mode chính cho tất cả sessions thực tế
- Khi `court_fee_total = 0`: fallback về `price_per_hour / 2 × courts` (hỗ trợ sessions kiểu cũ)
- Ghost member, weighted intervals, extra charges: tất cả đều đúng

**Verified:** So sánh RPC output với snapshots hiện có → discrepancy = 0 cho tất cả members.

---

### 🔴 BUG-002: Mobile layout vỡ trên các bảng

**Mô tả:** Các bảng nhiều cột bị overflow hoặc co lại không đọc được trên mobile.

**Cụ thể:**

- Presence grid (điểm danh): nhiều interval → cột tràn ra ngoài viewport
- Cost breakdown table: cột sân/cầu/phụ phí làm vỡ layout
- Session list table trên Dashboard

**Cần làm:**

- [ ] Presence grid: `overflow-x-auto` + sticky first column (tên member)
- [ ] Cost table mobile: ẩn cột Sân, Cầu, Phụ phí — chỉ hiện Tên + Tổng + Action (`hidden sm:table-cell`)
- [ ] Session list: dùng card style trên mobile thay vì table row

---

### 🟡 BUG-003: Create Session form đang bị rối

**Mô tả:** Trang `/create-session` đang được rework, form hiện tại có UX chưa tốt.

**Target design:** Xem [07-ui-ux-design.md — Create Session](./07-ui-ux-design.md)

**Cần làm:**

- [ ] Simplify court booking input (giữ logic nhưng UI gọn hơn)
- [ ] Auto-preview số interval sẽ tạo ra (dựa trên giờ)
- [ ] Validation: court time phải nằm trong session time

---

### 🟡 BUG-004: `bank_config` bảng rỗng, hardcode bank info

**Mô tả:** Thông tin ngân hàng (TPBank, số TK) đang hardcode ở 3 nơi trong FE.

**Vị trí:** `src/types/index.ts`, `PaymentView.vue`, `PaymentQRModal.vue`

**Cần làm:**

- [ ] Tạo 1 constant/composable trung tâm cho BANK_INFO
- [ ] Hoặc populate `bank_config` table và fetch từ DB

---

### 🟡 BUG-005: `snapshot.status` là `text` thay vì enum

**Mô tả:** Field `session_costs_snapshot.status` dùng `text` ('pending'/'partial'/'paid') thay vì Postgres enum → dễ typo.

**Cần làm:**

- [ ] Migration: tạo enum `payment_status` và alter column

---

### 🟢 DEBT-001: `is_permanent` field chưa dùng

**Mô tả:** `members.is_permanent` tồn tại nhưng không có logic nào dùng đến.

**Quyết định:** Xóa khỏi `members` table và khỏi `Member` interface trong FE.

---

### 🟢 DEBT-002: Leftover boilerplate

- `src/stores/counter.ts` — boilerplate Vite, chưa xóa
- `console.log('supabase', supabase)` trong `src/lib/supabase.ts`

---

## Pending Features (Chưa implement)

### P1 — Cần thiết gần

| Feature                                | Mô tả                                  | File liên quan                |
| -------------------------------------- | -------------------------------------- | ----------------------------- |
| **Responsive bảng**                    | Horizontal scroll + ẩn cột trên mobile | Tất cả views có table         |
| **Checkbox chọn buổi** ở `/member/:id` | Chọn N buổi → tạo group QR             | `MemberDetailView.vue`        |
| **Filter status** ở Dashboard          | Lọc open/waiting/done                  | `DashboardView.vue`           |
| **Fix tính tiền**                      | Verify và fix BUG-001                  | RPC `calculate_session_costs` |
| **Centralize BANK_INFO**               | Xóa duplicate                          | `types/index.ts`, Modals      |

### P2 — Quan trọng nhưng không khẩn

| Feature                                    | Mô tả                                              |
| ------------------------------------------ | -------------------------------------------------- |
| **Create Session rework**                  | Form mới theo design target ở `07-ui-ux-design.md` |
| **Bottom nav bar**                         | Thay top nav bằng bottom nav (mobile-first)        |
| **Member có thể xem session đã finalized** | Access control: non-auth xem status != 'open'      |
| **Quick action "Tạo buổi"** ở Home         | Button nổi bật trên home page                      |
| **Search session** trên Dashboard          | Tìm theo tên hoặc ngày                             |
| **Pagination** cho session list            | Hiện 13 sessions, sắp cần phân trang               |

### P3 — Future

| Feature                 | Mô tả                                     |
| ----------------------- | ----------------------------------------- |
| **Thông báo Zalo/Push** | Thông báo khi session mở, khi có tiền vào |
| **Thống kê**            | Biểu đồ tần suất, tiền theo tháng         |
| **Recurring session**   | Tạo lịch định kỳ (mỗi thứ 3)              |
| **`bank_config` từ DB** | Fetch bank info thay vì hardcode          |
| **Enum migration**      | `payment_status` enum thay vì text        |

---

## Approach phát triển

```
Requirement → Tưởng tượng UI → Sửa BE → Implement FE
```

**Quy trình làm tính năng mới:**

1. Xác định UI/UX trong `07-ui-ux-design.md`
2. Xác định DB changes cần trong `01-database-schema.md`
3. Viết/sửa RPC nếu cần, document trong `02-business-logic.md`
4. Implement FE component
5. Update docs liên quan
