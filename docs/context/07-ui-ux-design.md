# UI/UX Design Decisions

> **Dùng file này khi:** Implement UI mới, refactor layout, thêm component, hoặc cần biết design intent của từng trang.

---

## Design Principles

| Nguyên tắc                 | Chi tiết                                                                                    |
| -------------------------- | ------------------------------------------------------------------------------------------- |
| **Mobile-first**           | Thiết kế cho mobile trước, desktop là bonus. Admin có thể dùng desktop khi cần quản lý nặng |
| **Bảng nhiều cột**         | Dùng horizontal scroll trên mobile, KHÔNG ẩn cột quan trọng                                 |
| **Vai trò = UX khác nhau** | Admin thấy thêm action buttons; member thấy read-only hoặc info cá nhân                     |
| **Ít nhấp = tốt hơn**      | QR, điểm danh, thêm member đều cần nhanh                                                    |

---

## Navigation (Bottom Nav Bar)

**Approach:** Bottom navigation bar cho mobile — pattern chuẩn của mobile app.

```
┌─────────────────────────────────────────┐
│            Content area                  │
│                                          │
│                                          │
└──────────────────────────────────────────┘
│  🏠 Home  │  📅 Sessions │  👥 Members  │
└──────────────────────────────────────────┘
```

**Tab items:**

| Tab             | Icon | Route       | Ai thấy          |
| --------------- | ---- | ----------- | ---------------- |
| Home            | 🏠    | `/`         | Tất cả           |
| Sessions        | 📅    | `/sessions` | Tất cả (nội dung lọc theo quyền) |
| Members         | 👥    | `/members`  | Tất cả           |
| (Login/Profile) | 👤    | `/login`    | Top-right corner |

> **Cập nhật 2026-09-14:** tab `/sessions` hiện cho mọi người, không ẩn theo `isAdmin`. Guest/member không đăng nhập chỉ thấy buổi đã `waiting_for_payment`/`done` (lọc ở tầng query); admin thấy tất cả kể cả `open`. Xem `10-ui-ux-audit-2026-09.md` mục 1.2/2.8.

---

## Trang: Home (`/`)

**Mục đích:** Trang đầu vào cho cả admin và member (non-login).

### Layout (Admin view)

```
┌─────────────────────────────┐
│  💰 Tổng chưa thu: 1.250.000đ │  ← Summary card
│  [+ Tạo buổi mới]           │  ← Quick action (admin only)
├─────────────────────────────┤
│  📅 Buổi gần nhất (5-10)    │  ← Session list compact
│  • T3/04/03 - Chờ thu       │
│  • T2/03/03 - Hoàn tất      │
├─────────────────────────────┤
│  💳 Bảng nợ tất cả member   │  ← HomeDebtTable
│  Tên       Nợ    Buổi chưa  │
│  Nguyễn A  150k  2          │
│  ...                         │
└─────────────────────────────┘
```

### Layout (Member / Non-login view)

- Danh sách buổi đã finalized (read-only)
- Không thấy bảng nợ tổng hợp
- Không thấy Quick action tạo buổi

### Cột ẩn/hiện theo màn hình (HomeDebtTable)

| Cột                 | Mobile | Desktop |
| ------------------- | ------ | ------- |
| Tên member          | ✅      | ✅       |
| Tổng nợ             | ✅      | ✅       |
| Số buổi chưa trả    | ✅      | ✅       |
| Actions (QR/detail) | ✅      | ✅       |

---

## Trang: Dashboard (`/sessions`) — Admin only

**Mục đích:** Danh sách toàn bộ buổi, admin quản lý.

### Features

- Filter theo status: `open` | `waiting_for_payment` | `done` | `cancelled` | All
- Search theo tên buổi hoặc ngày
- Phân trang (pagination)
- Nút "+ Tạo buổi mới" → `/create-session`
- **Member non-login:** Chỉ thấy session đã `finalized` (status != 'open')

### Card/row mỗi session

```
┌────────────────────────────────────────┐
│ T3 04/03  CLB Cầu Lông Quận 7         │
│ 18:00-20:00  •  [Chờ thu] badge       │
│ 15 người  •  Thu được: 1.200.000đ     │
│               [Xem chi tiết →]         │
└────────────────────────────────────────┘
```

### Cột responsive

| Info         | Mobile (card) | Desktop (table) |
| ------------ | ------------- | --------------- |
| Tên + ngày   | ✅             | ✅               |
| Giờ          | compact       | ✅               |
| Status badge | ✅             | ✅               |
| Số người     | ẩn            | ✅               |
| Tiền đã thu  | ẩn            | ✅               |
| Action       | ✅             | ✅               |

---

## Trang: Create Session (`/create-session`) — Admin only

> ⚠️ **Đang được rework.** Đây là thiết kế mục tiêu.

### Form fields

```
┌─────────────────────────────┐
│ Tên buổi *                  │
│ [CLB Cầu Lông T3 04/03    ] │
├─────────────────────────────┤
│ Ngày *        Giờ (từ - đến)│
│ [04/03/2026] [18:00 - 20:00]│
├─────────────────────────────┤
│ Giá sân/giờ *   Tiền cầu   │
│ [200.000đ    ] [120.000đ  ] │
├─────────────────────────────┤
│ ══ Danh sách sân ══         │
│ + Thêm sân                  │
│ ┌─────────────────────────┐ │
│ │ Sân 1  [18:00] → [20:00]│ │
│ │ Sân 2  [18:00] → [19:00]│ │ ← Sân 2 về sớm 1 tiếng
│ └─────────────────────────┘ │
├─────────────────────────────┤
│ [Hủy]          [Tạo buổi →]│
└─────────────────────────────┘
```

### Logic court → interval

- Hệ thống tự tạo intervals 30p từ `session.start_time` → `session.end_time`
- Mỗi interval có `active_court_count` = số sân có booking overlap với khung đó
- Ví dụ: Sân 1 (18-20), Sân 2 (18-19) →
  - Interval 18:00-18:30: `active_court_count = 2`
  - Interval 18:30-19:00: `active_court_count = 2`
  - Interval 19:00-19:30: `active_court_count = 1` ← Sân 2 đã về
  - Interval 19:30-20:00: `active_court_count = 1`

---

## Trang: Session Detail (`/session/:id`)

**Ai xem được gì:**

- **Admin:** Full access — sửa, điểm danh, finalize, payment
- **Member (login hoặc không):** Xem full thông tin của **session đã finalized** (status != 'open'). Session đang open thì không thấy.

### Sections (Admin, status = open)

```
┌─────────────────────────────┐
│ [← Quay lại] CLB T3 04/03  │
│ 18:00 - 20:00  [open] badge │
├─────────────────────────────┤
│ ══ THÀNH VIÊN ══            │
│ [+ Thêm member dropdown]    │
│ Nguyễn A  [x]               │
│ Trần B    [x]               │
├─────────────────────────────┤
│ ══ ĐIỂM DANH ══             │
│  (presence grid)            │
│  ← horizontal scroll →      │
│  Tên   |18:00|18:30|19:00|  │
│  A     | ✅  | ✅  | ✅  |  │
│  B     | ✅  | ❌  | ✅  |  │
│  C(ghost)| —  | —  | —  |  │
├─────────────────────────────┤
│ ══ CHI PHÍ DỰ KIẾN ══       │
│ (bảng preview luôn hiển)    │
│ Tên    Sân  Cầu  Phụ  Tổng  │
│ A      80k  40k   0   120k  │
│ B      40k  20k   0   60k   │
│ C(g)   40k   0k   0   40k   │
├─────────────────────────────┤
│ ══ PHỤ PHÍ ══               │
│ [SessionExtraCharges comp]  │
├─────────────────────────────┤
│ [Chốt & Tính tiền →]        │
└─────────────────────────────┘
```

### Sections (Admin, status = waiting_for_payment)

```
├─────────────────────────────┤
│ ══ THANH TOÁN ══            │
│ Tên    Tổng   Còn nợ  Trạng │
│ A      120k   120k  [QR][✓] │
│ B       60k    30k  [QR][✓] │◀ partial paid
│ C        40k    0   [paid]  │
│                              │
│ [Tạo QR nhóm (chọn nhiều)] │
└─────────────────────────────┘
```

**Cột bảng mobile (horizontal scroll):**

- Mobile: Tên | Tổng | Trạng thái | Action
- Desktop: Tên | Sân | Cầu | Phụ phí | Tổng | Đã trả | Còn nợ | Action

### Presence Grid — mobile handling

- Horizontal scroll container
- Cột member cố định (sticky left)
- Mỗi interval là 1 cột có thể scroll

---

## Trang: Member Detail (`/member/:id`)

**Ai xem:** Tất cả (member xem của mình, admin xem của bất kỳ ai).

### Layout

```
┌─────────────────────────────┐
│ Nguyễn Văn An               │
│ 💰 Tổng nợ: 370.000đ       │  ← Nổi bật
│ [Tạo QR thu tất cả]         │
├─────────────────────────────┤
│ ══ LỊCH SỬ BUỔI ══          │
│ ☐ T3 04/03  120k  [pending] │  ← Checkbox để chọn
│ ☑ T2 03/03  250k  [partial] │
│ ✓ T5 27/02  80k   [paid]    │
│                              │
│ [Tạo QR cho buổi đã chọn]  │  ← Chỉ hiện khi có checkbox checked
└─────────────────────────────┘
```

### Checkbox + Group QR flow

1. Member/Admin check một hoặc nhiều buổi còn nợ
2. Nút "Tạo QR (X buổi)" xuất hiện
3. Bấm → gọi `create_group_payment(snapshot_ids[])` → mở `PaymentQRModal`
4. QR hiển thị tổng số tiền của các buổi đã chọn

> Nếu chọn "Tất cả" → gọi luôn với toàn bộ pending snapshots của member đó.

### Attendance detail per session

- Expand từng row session → hiển thị từng interval + is_present

---

## Trang: Members (`/members`)

**Ai xem:** Tất cả (admin thấy thêm actions).

### Layout

```
┌─────────────────────────────┐
│ [Filter: Active ▼] [Search] │
├─────────────────────────────┤
│ Tên          Nợ    Status   │
│ Nguyễn A     370k  active   │
│ Trần B       0     active   │
│ Lê C         80k   inactive │
│                              │
│ [+ Thêm member] ← admin only│
└─────────────────────────────┘
```

- Bấm vào row → `/member/:id`
- Admin thấy nút Sửa / Ẩn member
- Filter: Active / Inactive / All

---

## Trang: Payment (`/pay`) — Public

**Ai xem:** Bất kỳ ai có link (không cần login).

### Layout

```
┌─────────────────────────────┐
│ Thanh toán CLB Cầu Lông     │
│ Mã: CLXXXXXX                │
│                              │
│   [QR Code image]           │
│   TPBank - 10003392871      │
│   Số tiền: 150.000đ         │
│                              │
│ [📋 Copy mã] [📤 Share]    │
│                              │
│ ── Trạng thái ──             │
│ ⏳ Chờ thanh toán...         │
│ Progress: 0 / 150.000đ      │
└─────────────────────────────┘
```

- Polling `check_qr_status` mỗi 2s
- Khi success: hiển thị ✅ animation → redirect hoặc thông báo

---

## Trang: Login (`/login`)

- Email + password form đơn giản
- Sau login: redirect về trang trước hoặc `/`

---

## Modal Components

### `PaymentQRModal`

- Dùng cho cả single (CL...) và group (GR...)
- Props: `code`, `amount`, `isOpen`
- Tự start/stop polling khi mở/đóng
- Auto-close khi `success = true`

### `ManualPaymentModal`

- Admin xác nhận thanh toán thủ công
- Input: số tiền (default = remaining), note
- Gọi RPC `add_manual_payment`

### `MemberUnpaidSessionsModal`

- Hiển thị danh sách buổi chưa trả của 1 member
- Có thể tạo group QR từ đây

---

## Component Notes

### Responsive bảng — quy tắc chung

```
Mobile (< 640px):
  - Horizontal scroll: wrapper có overflow-x-auto
  - Sticky first column (tên member/session)
  - Ẩn cột breakdown (Sân, Cầu) — chỉ hiện Tổng
  - Dùng class: hidden sm:table-cell

Desktop (≥ 640px):
  - Hiện full columns
```

### Ghost member display

- Badge hoặc icon đặc biệt để phân biệt ghost vs có mặt
- Tooltip giải thích "Đăng ký nhưng không điểm danh — vẫn tính tiền sân"

### Status badges

| Status                | Color     | Label        |
| --------------------- | --------- | ------------ |
| `open`                | green     | Đang mở      |
| `waiting_for_payment` | yellow    | Chờ thu      |
| `done`                | blue/gray | Hoàn tất     |
| `cancelled`           | red       | Đã hủy       |
| `pending` (snapshot)  | gray      | Chưa trả     |
| `partial` (snapshot)  | yellow    | Trả một phần |
| `paid` (snapshot)     | green     | Đã trả       |

---

## Design tokens (B-1, 2026-09-28)

- `src/assets/tokens.css` được sinh từ Figma variables bằng `tools/figma-sync/token_sync.py` trong kit. Không sửa tay; đổi màu/size trong Figma rồi sinh lại.
- Tên: `text/*` → `fg-*` (`text-fg-muted`), `surface/*` → `surface-*` (`bg-surface-card`), `border/*` → `line-*` (`border-line-input`), `status/*` → `status-*`. Control: `h-control-sm|md|lg` (36/44/48), `rounded-control`.
- `divider` và `input` là alias tạm của `line-divider` / `line-input`, bỏ khi B-1 xong.
- View và component chỉ dùng token, không dùng màu palette (`bg-green-600`, `text-gray-500`). `src/__tests__/designTokens.test.ts` chặn điều này; các file chưa chuyển nằm trong `PALETTE_ALLOWED`, mỗi slice của B-1 gỡ file của mình ra.

## Shared UI components (B-1)

Nằm trong `src/components/ui/`, mỗi file là một component set trong Figma. Prop = trục variant của Figma (giá trị đúng chuỗi Figma, trục `Style` → prop `variant`); root có `data-ds="<tên set>"` và `data-ds-<trục>` để figma-sync so khớp. Chỉ dùng token, không gọi Supabase.

- `Button` — nút chữ và link dạng nút: `size` Small/Default/Large (36/44/48), `variant` 9 kiểu; `loading` (spinner + `aria-busy`, không tự disable), `pressed` (Outline Danger), `leadingIcon`/`trailingIcon`, `as` (`button`, `a`, `RouterLink`).
- `IconButton` — nút chỉ có icon: `size` Small 32/Default 44, `shape` Round/Square, `variant` Ghost…/Outline; `label` bắt buộc (`aria-label`).
- `Input` — ô nhập, `v-model`: `size` Small/Default/Large, `suffix`; thuộc tính native (`id`, `type`, `min`, …) đi thẳng vào `<input>`.
- `Select` — `<select>` native với chevron, `v-model`, slot = các `<option>`.
- `Checkbox` — checkbox native, `v-model` (boolean hoặc mảng + `value`), `size` 16/20/24.
- `FieldLabel` — nhãn trên control: `variant` Default/Small/Caps/Muted.
- `FieldMessage` — chữ gợi ý/lỗi: `tone` Help/Error, `size`, `align` Left/Center.
- `FormField` — nhãn + control + message, gap 4; nối `for`/`id`, `aria-describedby`, `aria-invalid` (khi Error) qua slot prop `controlProps`.
- `Badge` — pill chung: `size` Default/Small, `tone` Info/Warning/Success/Danger/Neutral/Brand.
- `SessionStatusBadge` — trạng thái buổi: `status` Open/Waiting For Payment/Done/Cancelled; nhãn lấy từ `common.<status>`.
- `PageHeader` — tiêu đề trang: `layout` Title/Title Action/Back Title/Icon Title/Centered; slot `actions`, `leading`.
- `Alert` — hộp thông báo: `tone`, `size`, `variant` Box/Banner, `align`; Danger có `role="alert"`; slot `action`.
- `EmptyState` — trạng thái rỗng: `variant` Plain/Card/Dashed/Dashed Muted, `align`, `size`, `icon`, `heading`.
- `Spinner` — vòng loading: `size` 32/48, `tone` Brand/Success; `role="status"` + sr-only `common.loading`.
