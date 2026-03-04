# Badminton Management System — Project Overview

> **Dùng file này làm "anchor" khi bắt đầu prompt cho AI.** Nó tóm tắt toàn bộ dự án để AI có context nhanh nhất.

## 1. Mô tả dự án

Hệ thống quản lý CLB Cầu Lông nội bộ (~1 admin, 10-30 members), gồm:

- Quản lý buổi đánh (sessions)
- Điểm danh theo từng khung giờ (interval-based attendance)
- Tính tiền tự động (tiền sân + tiền cầu + phụ phí) theo thuật toán proportional
- Thu tiền qua VietQR (auto-detect via banking webhook + confirm thủ công)

**Trạng thái:** Đang phát triển tích cực. Trang Create Session đang rework. Auto-payment hoạt động ổn.
**Approach:** Requirement → Tưởng tượng UI → Sửa BE → Implement FE

## 2. Tech Stack

| Layer        | Technology                                  |
| ------------ | ------------------------------------------- |
| Frontend     | Vue 3 (Composition API) + TypeScript + Vite |
| State        | Pinia                                       |
| Routing      | Vue Router 4                                |
| Backend / DB | Supabase (PostgreSQL 17)                    |
| i18n         | vue-i18n, hỗ trợ `vi` và `en`               |
| Package mgr  | pnpm (workspace)                            |
| Deploy       | Vercel                                      |

**Supabase Project ID:** `bufpmpehugzysvmbjlub`  
**Region:** ap-south-1

## 3. Domain Map

```
docs/context/
├── 00-project-overview.md    ← File này (anchor)
├── 01-database-schema.md     ← Tất cả Tables, Columns, Enums, FK
├── 02-business-logic.md      ← RPCs & Views (logic tính tiền, QR check)
├── 03-auth-and-roles.md      ← Auth flow, roles, route guards
├── 04-session-domain.md      ← Session lifecycle, interval, điểm danh
├── 05-payment-domain.md      ← Payment flow, QR, polling, group payment
├── 06-frontend-arch.md       ← Vue components, stores, composables, routing
├── 07-ui-ux-design.md        ← Design intent từng trang, mobile approach
└── 08-bugs-and-roadmap.md    ← Bugs đã biết, pending features, roadmap
```

## 3b. Prompt Guide — Đính kèm docs nào khi hỏi AI?

| Task                           | Đính kèm                           |
| ------------------------------ | ---------------------------------- |
| Viết SQL, migration, RLS       | `00` + `01`                        |
| Sửa/thêm RPC, logic tính tiền  | `00` + `01` + `02`                 |
| Tính năng liên quan payment/QR | `00` + `02` + `05`                 |
| Tính năng session/điểm danh    | `00` + `04`                        |
| Implement UI component mới     | `00` + `06` + `07`                 |
| Fix bug cụ thể                 | `00` + doc domain liên quan + `08` |
| Lên kế hoạch tính năng mới     | `00` + `07` + `08`                 |

## 4. Luồng nghiệp vụ chính (End-to-End)

```
[Admin] Tạo Session (RPC create_session_with_bookings)
   → Tự động tạo session_intervals (30p chunks)
   → active_court_count mỗi interval tính từ court bookings overlap
   ↓
[Admin] Thêm members vào session (batch_add_members_to_session)
   → Auto tick điểm danh present=true cho tất cả intervals hiện có
   ↓
[Admin] Điểm danh trong buổi → cập nhật interval_presence
   ↓
[Admin] Đóng buổi → RPC finalize_session()
   → calculate_session_costs() tính tiền từng người
   → Ghi session_costs_snapshot (idempotent — ON CONFLICT DO UPDATE)
   → session.status = 'waiting_for_payment'
   ↓
[Admin / Member] Tạo QR code (single CL... hoặc group GR...)
   ↓
[Member] Quét QR → trang /pay (public, không cần login)
         → FE polling check_qr_status() mỗi 2s
   ↓
[Banking webhook / Admin manual] Confirm payment
        → add_manual_payment() hoặc auto từ webhook
        → cập nhật paid_amount, status = 'partial' | 'paid'
   ↓
[Trigger check_session_completion] Khi tất cả paid
        → session.status = 'done' tự động
```

## 5. Enum & Status Values quan trọng

### session_status (Postgres enum)

| Value                 | Ý nghĩa                                            |
| --------------------- | -------------------------------------------------- |
| `open`                | Buổi đang diễn ra, có thể thêm member và điểm danh |
| `waiting_for_payment` | Đã chốt chi phí, đang chờ thu tiền                 |
| `done`                | Tất cả đã thanh toán                               |
| `cancelled`           | Buổi bị hủy                                        |

### user_role (Postgres enum)

| Value    | Ý nghĩa                                |
| -------- | -------------------------------------- |
| `admin`  | Quản trị: toàn quyền                   |
| `member` | Thành viên: chỉ xem thông tin bản thân |

### snapshot.status (text — KHÔNG phải enum)

| Value     | Ý nghĩa           |
| --------- | ----------------- |
| `pending` | Chưa trả đồng nào |
| `partial` | Trả một phần      |
| `paid`    | Đã trả đủ         |

### payment_code prefix

| Prefix  | Loại                                                     |
| ------- | -------------------------------------------------------- |
| `CL...` | Single — 1 người, 1 buổi                                 |
| `GR...` | Group — nhiều người cùng 1 buổi, hoặc 1 người nhiều buổi |

## 6. Known Issues / Technical Debt

> Chi tiết đầy đủ xem [08-bugs-and-roadmap.md](./08-bugs-and-roadmap.md)

| Priority | Issue                                                             |
| -------- | ----------------------------------------------------------------- |
| 🔴 BUG    | Tính tiền sai sau khi thêm weighted interval + extra charges      |
| 🔴 BUG    | Mobile layout vỡ trên các bảng                                    |
| 🟡 BUG    | Create Session form đang rối (đang rework)                        |
| 🟡 DEBT   | `bank_config` rỗng, BANK_INFO hardcode ở 3 nơi trong FE           |
| 🟡 DEBT   | `snapshot.status` là `text` thay vì Postgres enum                 |
| 🟢 DEBT   | `is_permanent` field chưa dùng, `counter.ts` boilerplate chưa xóa |
