# Database Schema Reference

> **Dùng file này khi:** Viết SQL, migration, RPC, RLS policy, hoặc cần biết chính xác tên cột và kiểu dữ liệu.

**Supabase Project:** `bufpmpehugzysvmbjlub` | PostgreSQL 17  
**Schema:** `public` (tất cả tables bên dưới đều có RLS enabled)

---

## Entity Relationship Overview

```
auth.users
   └─ members (user_id FK → auth.users)
         ├─ session_registrations (member_id FK)
         ├─ interval_presence     (member_id FK)
         ├─ session_costs_snapshot(member_id FK)
         └─ session_extra_charges (member_id FK)

sessions
   ├─ session_intervals     (session_id FK)
   │     └─ interval_presence (interval_id FK)
   ├─ session_registrations  (session_id FK)
   ├─ session_extra_charges  (session_id FK)
   ├─ session_costs_snapshot (session_id FK)
   │     └─ session_payments  (snapshot_id FK)
   └─ session_court_bookings (session_id FK) [ít dùng]

group_payment_requests
   └─ snapshot_ids: uuid[]  ← array ref tới session_costs_snapshot (KHÔNG có FK)
```

---

## Tables

### `members`

Danh sách thành viên CLB. Liên kết với `auth.users` qua `user_id`.

| Column         | Type        | Nullable | Default            | Ghi chú                  |
| -------------- | ----------- | -------- | ------------------ | ------------------------ |
| `id`           | uuid        | NO       | uuid_generate_v4() | PK                       |
| `user_id`      | uuid        | YES      |                    | FK → auth.users.id       |
| `display_name` | text        | NO       |                    | Tên hiển thị             |
| `role`         | user_role   | YES      | 'member'           | Enum: admin / member     |
| `is_active`    | boolean     | YES      | true               | Có đang hoạt động không  |
| `is_permanent` | boolean     | YES      | false              | **⚠️ Dư thừa, chưa dùng** |
| `created_at`   | timestamptz | YES      | now()              |                          |
| `updated_at`   | timestamptz | YES      | now()              |                          |

---

### `sessions`

Mỗi row là 1 buổi đánh cầu lông.

| Column                | Type           | Nullable | Default            | Ghi chú                         |
| --------------------- | -------------- | -------- | ------------------ | ------------------------------- |
| `id`                  | uuid           | NO       | uuid_generate_v4() | PK                              |
| `title`               | text           | NO       |                    | Tên buổi (VD: "Thứ 3 - 07/01")  |
| `start_time`          | timestamptz    | NO       |                    | Giờ bắt đầu                     |
| `end_time`            | timestamptz    | NO       |                    | Giờ kết thúc                    |
| `price_per_hour`      | numeric        | YES      | 0                  | Giá sân mỗi giờ (VND)           |
| `default_court_count` | integer        | YES      | 1                  | Số sân mặc định                 |
| `court_fee_total`     | numeric        | YES      | 0                  | Tổng tiền sân (có thể override) |
| `shuttle_fee_total`   | numeric        | YES      | 0                  | Tổng tiền cầu cho buổi          |
| `status`              | session_status | YES      | 'open'             | Enum — xem §Enums               |
| `created_by`          | uuid           | YES      |                    | FK → auth.users.id              |
| `created_at`          | timestamptz    | YES      | now()              |                                 |
| `updated_at`          | timestamptz    | YES      | now()              |                                 |

---

### `session_intervals`

Mỗi row là 1 khung thời gian (~30 phút) trong buổi. Admin tạo thủ công.

| Column               | Type        | Nullable | Default            | Ghi chú                              |
| -------------------- | ----------- | -------- | ------------------ | ------------------------------------ |
| `id`                 | uuid        | NO       | uuid_generate_v4() | PK                                   |
| `session_id`         | uuid        | YES      |                    | FK → sessions.id                     |
| `start_time`         | timestamptz | NO       |                    |                                      |
| `end_time`           | timestamptz | NO       |                    |                                      |
| `idx`                | integer     | NO       |                    | Thứ tự interval trong buổi (0-based) |
| `active_court_count` | integer     | YES      | 1                  | Số sân đang dùng trong khung này     |
| `created_at`         | timestamptz | YES      | now()              |                                      |

---

### `interval_presence`

Điểm danh: ai có mặt trong từng interval.

| Column        | Type        | Nullable | Default            | Ghi chú                   |
| ------------- | ----------- | -------- | ------------------ | ------------------------- |
| `id`          | uuid        | NO       | uuid_generate_v4() | PK                        |
| `interval_id` | uuid        | YES      |                    | FK → session_intervals.id |
| `member_id`   | uuid        | YES      |                    | FK → members.id           |
| `is_present`  | boolean     | YES      | true               | true = có mặt             |
| `created_at`  | timestamptz | YES      | now()              |                           |

---

### `session_registrations`

Danh sách member đăng ký tham gia buổi.

| Column       | Type        | Nullable | Default            | Ghi chú          |
| ------------ | ----------- | -------- | ------------------ | ---------------- |
| `id`         | uuid        | NO       | uuid_generate_v4() | PK               |
| `session_id` | uuid        | YES      |                    | FK → sessions.id |
| `member_id`  | uuid        | YES      |                    | FK → members.id  |
| `created_at` | timestamptz | YES      | now()              |                  |

> `is_registered_not_attended` đã được remove. Trạng thái có mặt/vắng hiện chỉ dựa trên `interval_presence.is_present`.

---

### `session_extra_charges`

Phụ phí riêng cho từng thành viên trong buổi (VD: mua cầu riêng, phí khác).

| Column       | Type        | Nullable | Default            | Ghi chú               |
| ------------ | ----------- | -------- | ------------------ | --------------------- |
| `id`         | uuid        | NO       | uuid_generate_v4() | PK                    |
| `session_id` | uuid        | YES      |                    | FK → sessions.id      |
| `member_id`  | uuid        | YES      |                    | FK → members.id       |
| `amount`     | numeric     | NO       |                    | Số tiền phụ phí (VND) |
| `note`       | text        | YES      |                    | Ghi chú lý do         |
| `created_at` | timestamptz | YES      | now()              |                       |

---

### `session_costs_snapshot`

Kết quả tính tiền đã được "lock". Mỗi row = chi phí của 1 member trong 1 buổi.

| Column               | Type        | Nullable | Default            | Ghi chú                                            |
| -------------------- | ----------- | -------- | ------------------ | -------------------------------------------------- |
| `id`                 | uuid        | NO       | uuid_generate_v4() | PK                                                 |
| `session_id`         | uuid        | YES      |                    | FK → sessions.id                                   |
| `member_id`          | uuid        | YES      |                    | FK → members.id                                    |
| `final_amount`       | numeric     | NO       |                    | Tổng tiền phải trả (đã làm tròn 1k)                |
| `court_fee_amount`   | numeric     | YES      | 0                  | Phần tiền sân                                      |
| `shuttle_fee_amount` | numeric     | YES      | 0                  | Phần tiền cầu                                      |
| `extra_fee_amount`   | numeric     | YES      | 0                  | Phần phụ phí                                       |
| `paid_amount`        | numeric     | YES      | 0                  | Đã trả bao nhiêu                                   |
| `payment_code`       | text        | YES      |                    | UNIQUE. Prefix: CL... (single)                     |
| `status`             | text        | YES      | 'pending'          | **⚠️ text (không phải enum)**: pending/partial/paid |
| `created_at`         | timestamptz | YES      | now()              |                                                    |

**Derived:**

- `remaining = final_amount - paid_amount`

---

### `session_payments`

Log từng lần thanh toán thực tế (mỗi transaction = 1 row).

| Column           | Type        | Nullable | Default            | Ghi chú                        |
| ---------------- | ----------- | -------- | ------------------ | ------------------------------ |
| `id`             | uuid        | NO       | uuid_generate_v4() | PK                             |
| `snapshot_id`    | uuid        | YES      |                    | FK → session_costs_snapshot.id |
| `amount`         | numeric     | NO       |                    | Số tiền của transaction này    |
| `transaction_id` | text        | YES      |                    | UNIQUE. ID từ ngân hàng        |
| `raw_content`    | text        | YES      |                    | Raw data từ webhook ngân hàng  |
| `payment_method` | text        | YES      | 'transfer'         | Phương thức thanh toán         |
| `created_at`     | timestamptz | YES      | now()              |                                |

---

### `group_payment_requests`

QR group — gom nhiều snapshot thành 1 mã thanh toán.

| Column         | Type        | Nullable | Default            | Ghi chú                                   |
| -------------- | ----------- | -------- | ------------------ | ----------------------------------------- |
| `id`           | uuid        | NO       | uuid_generate_v4() | PK                                        |
| `group_code`   | text        | NO       |                    | UNIQUE. Prefix: GR...                     |
| `snapshot_ids` | uuid[]      | NO       |                    | **⚠️ Không có FK** — array of snapshot IDs |
| `total_amount` | numeric     | NO       |                    | Tổng tiền lúc tạo QR                      |
| `fingerprint`  | text        | YES      |                    | Hash để detect duplicate                  |
| `expires_at`   | timestamptz | YES      | now()+1day         | Thời hạn QR                               |
| `created_at`   | timestamptz | YES      | now()              |                                           |

---

### `bank_config`

Config ngân hàng. **Hiện tại bảng này RỖNG.**  
Thông tin ngân hàng đang hardcode ở FE trong `src/types/index.ts`:

```typescript
export const BANK_INFO = {
  BANK_ID: 'TPB',         // TPBank
  ACCOUNT_NO: '10003392871',
  TEMPLATE: 'compact2',
}
```

| Column           | Type    | Nullable | Ghi chú             |
| ---------------- | ------- | -------- | ------------------- |
| `id`             | uuid    | NO       | PK                  |
| `bank_id`        | text    | NO       | Mã ngân hàng VietQR |
| `account_number` | text    | NO       |                     |
| `account_name`   | text    | NO       |                     |
| `template`       | text    | YES      | VietQR template     |
| `is_active`      | boolean | YES      |                     |

---

### `session_court_bookings`

Lịch thuê sân cụ thể. **Ít dùng** (chỉ có 1 row trong DB).

| Column       | Type        | Ghi chú          |
| ------------ | ----------- | ---------------- |
| `id`         | uuid        | PK               |
| `session_id` | uuid        | FK → sessions.id |
| `court_name` | text        | Tên sân          |
| `start_time` | timestamptz |                  |
| `end_time`   | timestamptz |                  |

---

## Enums (Postgres TYPE)

```sql
-- session_status
CREATE TYPE session_status AS ENUM ('open', 'waiting_for_payment', 'done', 'cancelled');

-- user_role  
CREATE TYPE user_role AS ENUM ('admin', 'member');
```

---

## Views

### `view_session_summary`

Tổng hợp số liệu cho từng session (dùng ở Dashboard).

**Computed columns:**

- `total_court_cost` — tính từ `session_intervals.active_court_count × price_per_hour/2`
- `total_extra_cost` — SUM từ `session_extra_charges`
- `total_members` — COUNT từ `session_registrations`
- `total_collected` — SUM paid_amount từ `session_costs_snapshot`

### `view_member_session_details`

Chi tiết từng buổi nợ của 1 member. Dùng ở trang Member Detail.

**Columns chính:** `snapshot_id, member_id, session_id, session_title, start_time, final_amount, paid_amount, remaining_amount, status, payment_code`
