# Known Bugs & Roadmap

> **Dùng file này khi:** Debug, planning sprint, hoặc cần biết trạng thái hiện tại của app.

---

## Trạng thái hiện tại (March 2026)

- ✅ **Hoạt động ổn:** Auto-detect thanh toán từ QR (banking webhook + polling)
- ✅ **Fixed:** Tính tiền sân sai (BUG-001 — lệch logic trước khi có `court_fee_addon` additive model)
- ✅ **Fixed:** `bank_config` đã có dữ liệu + FE có `useBankConfig` fallback
- ✅ **Fixed:** `session_costs_snapshot.status` đã migrate sang enum `payment_status`
- ✅ **Fixed:** `members.is_permanent` đã được remove
- 🔧 **Đang rework:** Trang Create Session
- ❌ **Bugs đã biết:** Mobile layout vỡ

---

## Bugs đã biết

### ✅ BUG-001: Tính tiền sai sau khi thêm weighted interval + extra charges

**Mô tả:** Sau khi update tính năng `active_court_count` theo từng interval (weighted) và thêm `session_extra_charges`, kết quả tính tiền bị sai.

**Nguyên nhân gốc rễ (đã xác định):**
Trước khi chuẩn hóa sang mô hình `court_fee_addon`, RPC `calculate_session_costs` từng tính lệch do
chỉ dựa vào `price_per_hour` ở một số case dữ liệu cũ.

**Fix đã áp dụng (chuẩn hiện tại):**

- Dùng additive model: `booking_cost (price_per_hour)` + `court_fee_addon` theo weighted interval
- Giữ fallback hợp lý khi `total_court_units = 0` để tránh lỗi chia 0
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

### 🟡 DEBT-004: Cần siết quyền thao tác admin ở một số UI path

**Mô tả:** Có chỗ dùng điều kiện `isAuthenticated` thay vì `isAdmin` cho thao tác nhạy cảm trên UI.

**Cần làm:**

- [ ] Rà toàn bộ action button theo chuẩn `authStore.isAdmin`
- [ ] Bổ sung test regression cho matrix quyền admin/member/guest

---

### 🟡 DEBT-005: Docs/API snapshot có độ trễ so với DB thật

**Mô tả:** Một số tài liệu từng lag sau các migration lớn (`payment_status`, `bank_config`, soft-delete).

**Cần làm:**

- [ ] Thêm checklist "update docs" ngay sau mỗi migration/RPC change
- [ ] Cân nhắc xuất lại `docs/api.yaml` định kỳ

---

## Pending Features (Chưa implement)

### P1 — Cần thiết gần

| Feature                                | Mô tả                                  | File liên quan                |
| -------------------------------------- | -------------------------------------- | ----------------------------- |
| **Responsive bảng**                    | Horizontal scroll + ẩn cột trên mobile | Tất cả views có table         |
| **Checkbox chọn buổi** ở `/member/:id` | Chọn N buổi → tạo group QR             | `MemberDetailView.vue`        |
| **Filter status** ở Dashboard          | Lọc open/waiting/done                  | `DashboardView.vue`           |
| **Quyền admin ở UI actions**           | Chặn member/guest bấm action nhạy cảm  | `SessionDetailView.vue`, components/session/* |
| **Docs sync automation nhẹ**           | Chuẩn hóa quy trình update docs sau migration | `docs/context/*`        |

### P2 — Quan trọng nhưng không khẩn

| Feature                                    | Mô tả                                              |
| ------------------------------------------ | -------------------------------------------------- |
| **Create Session rework**                  | Form mới theo design target ở `07-ui-ux-design.md` |
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
| **Docs/API CI check**   | Cảnh báo khi schema thay đổi nhưng docs chưa cập nhật |

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
