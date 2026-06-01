# Session Domain

> **Dùng file này khi:** Làm việc với tính năng tạo buổi, điểm danh, quản lý interval, đóng buổi tính tiền.

---

## Session Lifecycle

```
[open]
  ├── Admin thêm/xóa member (session_registrations)
  ├── Admin chốt interval thủ công (session_intervals)
  │     └── Đánh dấu điểm danh (interval_presence)
  ├── Admin thêm phụ phí cho member (session_extra_charges)
  └── Admin "Finalize" (đóng buổi)
         ↓
[waiting_for_payment]
  └── (xem 05-payment-domain.md)
         ↓
[done] hoặc [cancelled]
```

---

## Tạo Session (`/create-session`)

**Route:** `POST /create-session` (Admin only)  
**RPC:** `create_session_with_bookings(...)`

**Form fields:**

| Field           | DB Column                    | Ghi chú                        |
| --------------- | ---------------------------- | ------------------------------ |
| Tên buổi        | `sessions.title`             | VD: "Thứ 3 - 07/01"            |
| Ngày            | `sessions.start_time`        | Combine với startTime          |
| Giờ bắt đầu     | `sessions.start_time`        | Format: "HH:mm"                |
| Giờ kết thúc    | `sessions.end_time`          |                                |
| Giá sân/giờ     | `sessions.price_per_hour`    | VND                            |
| Tiền cầu        | `sessions.shuttle_fee_total` | Tổng cả buổi                   |
| Sân (danh sách) | `session_court_bookings[]`   | Tên sân + giờ bắt đầu/kết thúc |

**RPC `create_session_with_bookings` làm gì:**

1. INSERT vào `sessions` (status = 'open')
2. **Tự động tạo `session_intervals`** theo từng chunk 30 phút từ start → end
3. INSERT các court vào `session_court_bookings`
4. Gọi `refresh_interval_courts()` — tính `active_court_count` mỗi interval dựa trên số booking overlap
5. Auto-add permanent members (nếu có)

> **Quan trọng:** Intervals được tạo TỰ ĐỘNG lúc tạo session. `active_court_count` mỗi interval được tính từ số `session_court_bookings` overlap với khung đó.

---

## Quản lý Members trong Session

**Trang:** `SessionDetailView.vue` — phần trên cùng

### Thêm member

```
SELECT members WHERE is_active = true
→ Hiển thị dropdown chọn nhiều member
→ INSERT vào session_registrations (session_id, member_id)
```

### Xóa member

```
DELETE FROM session_registrations WHERE session_id = X AND member_id = Y
```

> **Lưu ý:** Không thể xóa member sau khi buổi đã finalize (có snapshot).

---

## Quản lý Intervals (Điểm danh)

**Interval = khung thời gian 30 phút. Được tạo tự động khi tạo session, không cần tạo thủ công.**

- Mỗi buổi 2 giờ → 4 intervals (idx 0→3)
- `active_court_count` mỗi interval = số `session_court_bookings` có giờ overlap với interval đó (tính bởi `refresh_interval_courts`)
- Khi admin sửa court bookings → cần gọi lại `refresh_interval_courts(session_id)` để re-sync

### Cấu trúc interval

```sql
-- Ví dụ buổi 18:00-20:00 → 4 intervals tự động:
{ idx: 0, start: 18:00, end: 18:30, active_court_count: 2 }
{ idx: 1, start: 18:30, end: 19:00, active_court_count: 2 }
{ idx: 2, start: 19:00, end: 19:30, active_court_count: 1 }  -- 1 sân về sớm
{ idx: 3, start: 19:30, end: 20:00, active_court_count: 1 }
```

### Điểm danh (interval_presence)

Sau khi tạo interval, admin check ai có mặt:

```sql
-- Đánh dấu có mặt
INSERT INTO interval_presence (interval_id, member_id, is_present)
VALUES ($intervalId, $memberId, true)
ON CONFLICT DO UPDATE SET is_present = true

-- Đánh dấu vắng
UPDATE interval_presence SET is_present = false
WHERE interval_id = X AND member_id = Y
```

**Presence matrix ở UI:** Bảng 2D `presence[memberId][intervalId] = boolean`

> Không còn cờ `is_registered_not_attended` trong `session_registrations`. Toàn bộ logic vắng/có mặt dùng `interval_presence`.

### Ghost member tự động

Member đăng ký nhưng `presence_count = 0` trong mọi interval sẽ được xem là Ghost bởi RPC `calculate_session_costs` — xem `02-business-logic.md`.

---

## Phụ phí (Extra Charges)

**Component:** `SessionExtraCharges.vue`

Admin có thể thêm phụ phí cho từng member:

```sql
INSERT INTO session_extra_charges (session_id, member_id, amount, note)
VALUES ($sessionId, $memberId, $amount, $note)
```

Phụ phí này được cộng vào `final_amount` khi finalize.

---

## Finalize Session (Đóng buổi)

**Trigger:** Admin bấm nút "Chốt & Tính tiền"  
**RPC:** `finalize_session(p_session_id uuid)`

**Flow:**

```
1. UPDATE sessions SET status = 'waiting_for_payment'

2. Gọi calculate_session_costs(p_session_id)
   → Nhận về danh sách { member_id, final_total, court_fee, shuttle_fee, extra_fee }

3. Với mỗi member:
   INSERT INTO session_costs_snapshot
     (session_id, member_id, final_amount, payment_code = 'CL' + random 6 chars, status = 'pending')
   ON CONFLICT (session_id, member_id) DO UPDATE
     SET final_amount = EXCLUDED.final_amount, ... -- Cập nhật nếu finalize lại
```

> **Idempotent:** `finalize_session` có `ON CONFLICT (session_id, member_id) DO UPDATE` → an toàn gọi lại nhiều lần. Tuy nhiên cần chú ý: `payment_code` không bị overwrite (chỉ update amounts).

> Chỉ tạo snapshot khi `final_total > 0` — member có phí bằng 0 (VD: người được miễn phí) không có snapshot.

---

## Realtime Updates

`SessionDetailView` subscribe Supabase Realtime để tự refresh khi:

- Ai đó thay đổi presence
- Snapshot được update (payment received)

```typescript
const channel: RealtimeChannel = supabase
  .channel(`session-${sessionId}`)
  .on('postgres_changes', { event: '*', schema: 'public', table: 'interval_presence' }, refresh)
  .on('postgres_changes', { event: '*', schema: 'public', table: 'session_costs_snapshot' }, refresh)
  .subscribe()
```

---

## UI State Flow trong `SessionDetailView`

| Session Status        | UI hiển thị                                                               |
| --------------------- | ------------------------------------------------------------------------- |
| `open`                | Nút thêm member, tạo interval, điểm danh, phụ phí, nút "Chốt & Tính tiền" |
| `waiting_for_payment` | Bảng snapshot chi phí, nút tạo QR (single/group), nút confirm thủ công    |
| `done`                | Read-only, hiển thị tổng kết                                              |
| `cancelled`           | Read-only, hiển thị cancelled badge                                       |

---

## Computed: Preview chi phí (trước khi finalize)

Khi buổi còn `open`, admin có thể xem preview bằng cách gọi `calculate_session_costs()` mà **không** lưu vào DB.  
FE lưu kết quả vào `costs: ref<MemberCost[]>()` và hiển thị ở bảng.
