# Business Logic — RPCs & Views

> **Dùng file này khi:** Cần hiểu thuật toán tính tiền, logic QR check, hoặc khi muốn sửa/thêm RPC.

---

## RPC: `calculate_session_costs(p_session_id uuid)`

**Mục đích:** Tính chi phí chi tiết cho từng thành viên trong 1 buổi. Kết quả được ghi vào `session_costs_snapshot`.

**Returns:** `TABLE(member_id, display_name, final_total, total_court_fee, total_shuttle_fee, total_extra_fee, intervals_count)`

### Các khái niệm

| Khái niệm         | Định nghĩa                                                                                |
| ----------------- | ----------------------------------------------------------------------------------------- |
| **Real attendee** | Member có ít nhất 1 interval `is_present = true`                                          |
| **Ghost member**  | Member đã đăng ký (`session_registrations`) nhưng `presence_count = 0` trong MỌI interval |
| **Court unit**    | `SUM(active_court_count)` qua tất cả intervals của buổi                                   |

> Nguồn sự thật attendance là `interval_presence`. Cờ `is_registered_not_attended` đã bị loại bỏ.

### Thuật toán tính tiền

#### A. Tiền sân (court fee) — chia cho cả Ghost + Real

**Option C — Additive model:** Tiền sân luôn là tổng của 2 nguồn cộng lại.

```
Cho mỗi interval:
  denominator = real_present_count_in_interval + total_ghost_count

  Nếu member là Ghost HOẶC có mặt (is_present = true):
    booking_cost = (price_per_hour / 2) × active_court_count / denominator
    addon_cost   = (court_fee_addon × active_court_count / total_court_units) / denominator
    court_cost_per_interval = booking_cost + addon_cost   ← luôn cộng cả 2

  Nếu không có mặt (và không phải ghost):
    court_cost_per_interval = 0
```

| Sessions cũ  | `price_per_hour=0`, `court_fee_addon=300k`   | booking_cost=0, addon=300k → **300k** ✅       |
| ------------ | -------------------------------------------- | --------------------------------------------- |
| Sessions mới | `price_per_hour=120k/h`, `court_fee_addon=0` | booking_cost=đủ, addon=0 → **booking_cost** ✅ |
| Mixed        | `price_per_hour>0`, `court_fee_addon>0`      | **cả hai cộng lại** (admin tự quản)           |

> **`court_fee_addon`** (`sessions.court_fee_addon`): khoản phí sân cố định, chia đều theo weighted intervals.
> **Ghost chịu tiền sân:** Đây là **feature có chủ đích** — người đăng ký nhưng không đến vẫn chiếm slot sân.

#### B. Tiền cầu (shuttle fee) — chỉ chia cho Real attendees

```
Cho mỗi interval:
  Nếu member có mặt (is_present = true):
    shuttle_cost = (shuttle_fee_total × active_court_count / total_court_units) / real_present_count_in_interval
  Nếu không có mặt (kể cả Ghost):
    shuttle_cost = 0
```

> Ghost **KHÔNG** chịu tiền cầu.

#### C. Phụ phí (extra fee)

```
total_extra = SUM(session_extra_charges.amount) WHERE member_id = X AND session_id = Y
```

#### D. Final total

```
final_total = CEIL((court_fee + shuttle_fee + extra_fee) / 1000) × 1000
```

> Làm tròn lên đến 1.000đ gần nhất.

### Ví dụ tính toán

```
Buổi: price_per_hour = 0, court_fee_addon = 300.000đ, shuttle_fee_total = 120.000đ
2 intervals: interval 1 active_court_count=2, interval 2 active_court_count=1
total_court_units = 3

Members: A (có mặt cả 2 interval), B (có mặt interval 1), C (ghost - đăng ký không đến)
ghost_count = 1

Interval 1: real_present = 2, denominator = 2 + 1 = 3
  Court fee per slot = (300k × 2/3) / 3 = 66.667đ
  Shuttle fee slot   = (120k × 2/3) / 2 = 40.000đ

Interval 2: real_present = 1, denominator = 1 + 1 = 2
  Court fee per slot = (300k × 1/3) / 2 = 50.000đ
  Shuttle fee slot   = (120k × 1/3) / 1 = 40.000đ

A: court = 66.667k + 50k = 116.667k, shuttle = 40k + 40k = 80k → total = 196.667k → 197.000đ
B: court = 66.667k, shuttle = 40k → total = 106.667k → 107.000đ
C (ghost): court = 66.667k + 50k = 116.667k, shuttle = 0 → total = 116.667k → 117.000đ

Kiểm tra: tổng court = 116.667 + 66.667 + 116.667 = 300.001 ≈ 300k ✓
          tổng shuttle = 80k + 40k + 0 = 120k ✓
```

---

## RPC: `check_qr_status(p_code text) RETURNS jsonb`

**Mục đích:** Check trạng thái thanh toán của 1 mã QR. FE gọi polling mỗi 2 giây.

**Input:** `p_code` — payment code (prefix `CL...` hoặc `GR...`)

**Output JSON:**

```json
{
  "found": true,
  "type": "single" | "group",
  "code": "CL8F3A21",
  "total": 150000,       // Số tiền mục tiêu của QR này (lúc tạo)
  "paid": 100000,        // Đã trả được bao nhiêu cho QR này
  "remaining": 50000,    // Còn thiếu (thực tế trong DB)
  "success": false,      // true khi remaining <= 1000đ (sai số cho phép)
  "details": [...]       // Chi tiết từng member
}
```

### Case 1: Single (`CL...`)

- Tra `session_costs_snapshot WHERE payment_code = p_code`
- `total` = `final_amount` (tổng bill ban đầu)
- `remaining` = `final_amount - paid_amount`
- `paid_progress` = `total - remaining`
- `success` = `remaining <= 1000`

### Case 2: Group (`GR...`)

- Tra `group_payment_requests WHERE group_code = p_code`
- `total` = `group_payment_requests.total_amount` (snapshot tại lúc tạo QR)
- `remaining` = `SUM(final_amount - paid_amount)` của tất cả snapshots trong group
- `paid_progress` = `MAX(0, total - remaining)`
- `success` = `remaining <= 1000`

> **Lý do tách `total` và `remaining`:** Khi người khác trong group trả trước, `remaining` giảm nhưng `total` giữ nguyên → `paid` tăng. UI hiển thị progress bar chính xác.

### Trường hợp không tìm thấy

```json
{ "found": false }
```

---

## View: `view_session_summary`

**Dùng ở:** Dashboard (`/sessions`) — hiển thị danh sách buổi

```sql
SELECT
  id, title, start_time, end_time,
  start_time::date AS session_date,
  status, price_per_hour,
  
  -- Tổng chi phí sân (tính lại từ intervals)
  COALESCE(SUM(si.active_court_count × price_per_hour/2), 0)
    + COALESCE(court_fee_addon, 0) AS total_court_cost,
  
  shuttle_fee_total,
  
  -- Tổng phụ phí
  COALESCE(SUM(ex.amount)) AS total_extra_cost,
  
  -- Số thành viên đã đăng ký
  COUNT(r.id) AS total_registrations,
  
  -- Tổng tiền đã thu được
  COALESCE(SUM(sc.paid_amount)) AS total_collected
FROM sessions s
-- ... (subqueries)
```

---

## RPC: `search_sessions_list(...)`

**Mục đích:** API list cho trang `/sessions` với fuzzy search title + filter + cursor pagination.

**Input chính:**

- `p_query text` — từ khóa tìm theo `title` (fuzzy qua `pg_trgm`)
- `p_status text[]` — mảng status cần lọc
- `p_start_date date`, `p_end_date date` — khoảng ngày
- `p_limit int` — page size
- `p_cursor_status_rank`, `p_cursor_session_date`, `p_cursor_id` — cursor composite cho infinite scroll

**Output:** Trả ra cùng shape với `view_session_summary` + `status_rank` để FE lấy cursor trang kế tiếp.

**Sort:** `status_rank ASC` → `session_date DESC` → `id DESC`

**Search condition:**

- `lower(title) LIKE %query%` hoặc
- `similarity(lower(title), lower(query)) >= threshold`

> Thiết kế này giữ compatibility với UX status-priority hiện tại, đồng thời cho infinite scroll ổn định (không duplicate giữa các page).

---

## View: `view_member_session_details`

**Dùng ở:** Trang Member Detail — xem lịch sử nợ/đã trả của 1 member

```sql
SELECT
  scs.id AS snapshot_id,
  scs.member_id, scs.session_id,
  s.title AS session_title,
  s.start_time,
  s.start_time::date AS session_date,
  scs.final_amount,
  scs.court_fee_amount, scs.shuttle_fee_amount, scs.extra_fee_amount,
  scs.paid_amount,
  (scs.final_amount - scs.paid_amount) AS remaining_amount,
  scs.status,
  scs.payment_code,
  scs.created_at
FROM session_costs_snapshot scs
JOIN sessions s ON s.id = scs.session_id
```

---

## Danh sách đầy đủ tất cả RPCs & Triggers

### RPCs (Functions thường)

| RPC                                   | Args                                                         | Returns | Mô tả                                                |
| ------------------------------------- | ------------------------------------------------------------ | ------- | ---------------------------------------------------- |
| `create_session_with_bookings`        | title, start/end, price, shuttle, created_by, bookings jsonb | uuid    | Tạo session + auto intervals + court bookings        |
| `finalize_session`                    | p_session_id                                                 | void    | Tính tiền + tạo snapshots + set waiting_for_payment  |
| `calculate_session_costs`             | p_session_id                                                 | TABLE   | Engine tính tiền — xem §trên                         |
| `add_member_to_session_full_presence` | p_session_id, p_member_id                                    | void    | Thêm 1 member + tick present cho tất cả intervals    |
| `batch_add_members_to_session`        | p_session_id, p_member_ids[]                                 | void    | Thêm nhiều members + tick present                    |
| `remove_member_from_session`          | p_session_id, p_member_id                                    | void    | Xóa member + cascade presence/extra charges/snapshot |
| `create_group_payment`                | p_snapshot_ids[]                                             | jsonb   | Tạo/reuse group QR với fingerprint dedup             |
| `check_qr_status`                     | p_code                                                       | jsonb   | Polling status — xem §trên                           |
| `add_manual_payment`                  | p_snapshot_id, p_amount, p_note                              | void    | Confirm thanh toán thủ công                          |
| `refresh_interval_courts`             | p_session_id                                                 | void    | Recalculate active_court_count từ court bookings     |
| `recreate_session_intervals`          | p_session_id                                                 | void    | Xóa/tạo lại intervals 30p theo giờ session hiện tại  |
| `get_session_delete_impact`           | p_session_id                                                 | TABLE   | Preview số records sẽ bị dọn khi xóa session hủy     |
| `soft_delete_cancelled_session`       | p_session_id                                                 | jsonb   | Xóa dữ liệu liên quan rồi đánh dấu deleted_at         |
| `soft_delete_cancelled_sessions_bulk` | p_session_ids[]                                              | TABLE   | Bulk soft-delete tối đa 50 sessions / lần gọi        |
| `gc_soft_deleted_sessions`            | p_older_than interval                                        | integer | Cron cleanup hard-delete session đã soft-delete cũ    |
| `search_sessions_list`                | p_query, p_status[], p_start_date, p_end_date, p_limit, cursor fields | TABLE | Fuzzy search + filter + cursor pagination cho dashboard sessions |

### Triggers (Functions + Trigger)

| Trigger                            | Table                                    | Event                       | Mô tả                                              |
| ---------------------------------- | ---------------------------------------- | --------------------------- | -------------------------------------------------- |
| `handle_new_user`                  | auth.users                               | AFTER INSERT                | Tự tạo member row khi user đăng ký                 |
| `check_session_completion`         | session_costs_snapshot                   | AFTER UPDATE                | Tự set session='done' khi tất cả paid              |
| `prevent_change_on_locked_session` | interval_presence, session_registrations | BEFORE INSERT/UPDATE/DELETE | Chặn sửa khi session không phải 'open'             |
| `trigger_refresh_courts`           | session_court_bookings                   | AFTER INSERT/UPDATE/DELETE  | Tự refresh active_court_count khi booking thay đổi |
| `update_updated_at_column`         | sessions                                 | BEFORE UPDATE               | Auto-update updated_at                             |

---

## Quy tắc Business chính cần nhớ

1. **Ghost member chịu tiền sân nhưng không chịu tiền cầu** — đây là thiết kế có chủ đích
2. **Final amount làm tròn lên 1.000đ** — sau khi tổng 3 loại phí
3. **Success threshold = 1.000đ** — cho phép sai số ngân hàng
4. **Group QR total là snapshot tại thời điểm tạo** — không update ngược lại khi người khác trả
5. **Tiền sân tính theo interval** (30p = price/2), không phải tổng giờ
6. **`active_court_count` có thể khác nhau mỗi interval** — tính từ court bookings overlap, không nhập tay
