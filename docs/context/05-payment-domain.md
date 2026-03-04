# Payment Domain

> **Dùng file này khi:** Làm việc với tính năng QR, thanh toán, polling, group payment, webhook.

---

## Tổng quan Payment Flow

```
[Session: waiting_for_payment]
  ↓
Admin/Member chọn người cần thu tiền
  ↓
┌─────────────────────┬─────────────────────────────┐
│ Single QR (1 người) │ Group QR (nhiều người/buổi) │
│ code: CL...         │ code: GR...                 │
└────────┬────────────┴──────────┬──────────────────┘
         └──────────┬────────────┘
              Trang /pay?code=X&amount=Y (PUBLIC)
                    ↓
              Hiển thị QR VietQR
                    ↓
              FE polling check_qr_status() mỗi 2s
                    ↓
         ┌──────────────────────────────┐
         │ Banking webhook detect code  │
         │ hoặc Admin confirm thủ công  │
         └──────────────────────────────┘
                    ↓
              paid_amount cập nhật
              status = 'partial' | 'paid'
                    ↓
         [Trigger check_session_completion]
         Nếu tất cả 'paid' → session.status = 'done'
```

---

## QR Generation

### VietQR URL format

```
https://img.vietqr.io/image/{BANK_ID}-{ACCOUNT_NO}-{TEMPLATE}.png
  ?amount={amount}
  &addInfo={payment_code}  ← payment_code là "nội dung chuyển khoản"
```

**Config hiện tại (hardcode ở FE):**

```typescript
BANK_ID: 'TPB'           // TPBank
ACCOUNT_NO: '10003392871'
TEMPLATE: 'compact2'
```

> ⚠️ Config đang duplicate ở 2 nơi: `src/types/index.ts (BANK_INFO)` và `PaymentView.vue + PaymentQRModal.vue`

---

## Single Payment (code: `CL...`)

**Tạo khi:** Admin finalize session → mỗi member tự động được tạo 1 `payment_code` dạng `CL` + 6 ký tự uppercase.

**Flow:**

```
Admin bấm icon QR bên cạnh tên member
  → PaymentQRModal mở ra với code = snapshot.payment_code, amount = remaining_amount
  → FE start polling check_qr_status(code)
  → Khi success → emit('success') → reload session data
```

**Hoặc** share link: `/pay?code=CLXXXXXX&amount=150000`

---

## Group Payment (code: `GR...`)

**Dùng khi:** Một người trả cho nhiều người cùng buổi, hoặc 1 người trả nhiều buổi.

**RPC:** `create_group_payment(p_snapshot_ids: uuid[]) → { group_code, total_amount }`

**Logic chống spam (fingerprint):**

```
1. Sort snapshot_ids
2. fingerprint = md5(join(sorted_ids, ','))
3. Nếu có group_code với fingerprint này còn hạn (expires_at > now()) → REUSE (không tạo mới)
4. Nếu không → tạo code mới = 'GR' + random 6 chars
5. group_payment_requests.expires_at = now() + 1 day
```

> Khi tái sử dụng, `total_amount` được cập nhật lại theo số nợ hiện tại (đề phòng admin sửa giá).

---

## Manual Payment (Admin confirm thủ công)

**Component:** `ManualPaymentModal.vue`  
**RPC:** `add_manual_payment(p_snapshot_id, p_amount, p_note)`

**Dùng khi:** Member trả tiền mặt, hoặc chuyển khoản nhưng webhook không catch được.

```
RPC add_manual_payment:
1. INSERT INTO session_payments (snapshot_id, amount, transaction_id='CASH-{epoch}', payment_method='cash')
2. v_new_paid = current_paid + p_amount
3. UPDATE session_costs_snapshot:
   - paid_amount = v_new_paid
   - status = 'paid' nếu v_new_paid >= final_amount, else 'partial'
```

> `transaction_id` format cho cash: `CASH-{unix_timestamp}` — đảm bảo UNIQUE.

---

## Payment Polling

**Composable:** `src/composables/usePaymentPolling.ts`

```typescript
const { data, startPolling, stopPolling } = usePaymentPolling(code, intervalMs = 2000)

// data shape:
interface PollResult {
  found: boolean
  total: number    // Số tiền mục tiêu
  paid: number     // Đã trả
  success: boolean // remaining <= 1000đ
  details: PaymentMemberDetail[]
}
```

**Lifecycle:**

- `startPolling()` → gọi ngay lập tức + setInterval mỗi 2s
- Khi `data.success = true` → `stopPolling()` tự động
- `onUnmounted` → `stopPolling()` để tránh memory leak
- `PaymentQRModal` watch `isOpen` → start/stop polling theo

---

## Trigger: `check_session_completion`

**Loại:** AFTER UPDATE trigger trên `session_costs_snapshot`

```sql
-- Logic:
IF NEW.status = 'paid' THEN
  IF (còn_unpaid_count = 0 trong session này) THEN
    UPDATE sessions SET status = 'done'
    WHERE id = NEW.session_id AND status = 'waiting_for_payment'
  END IF
END IF
```

> Session tự động chuyển `done` khi **tất cả** snapshots trong session đều `paid`. Không cần admin confirm thêm.

---

## Trigger: `prevent_change_on_locked_session`

Chặn INSERT/UPDATE/DELETE trên:

- `interval_presence`
- `session_registrations`

Khi `sessions.status != 'open'`. Raise EXCEPTION nếu vi phạm.

---

## Payment View (`/pay`) — Trang Public

**URL:** `/pay?code=CLXXXXXX&amount=150000`

**Không yêu cầu login.** Member có thể share link này cho người khác.

**Features:**

- Hiển thị QR VietQR với đúng amount và nội dung chuyển khoản
- Copy code vào clipboard
- Share via Web Share API (cả QR image nếu browser hỗ trợ)
- Polling real-time trạng thái thanh toán (dùng `check_qr_status` trực tiếp trong view, không qua composable tại đây — chỉ hiển thị thụ động)

---

## RPC tổng hợp liên quan đến Payment

| RPC                    | Args                              | Mô tả                                               |
| ---------------------- | --------------------------------- | --------------------------------------------------- |
| `finalize_session`     | `p_session_id`                    | Tính tiền + tạo snapshots + set waiting_for_payment |
| `check_qr_status`      | `p_code`                          | Polling status (single/group)                       |
| `create_group_payment` | `p_snapshot_ids[]`                | Tạo/reuse group QR                                  |
| `add_manual_payment`   | `p_snapshot_id, p_amount, p_note` | Confirm trả tiền thủ công                           |

---

## Edge Cases

1. **Member trả dư:** `paid_amount > final_amount` → status = 'paid'. Số dư không được hoàn tự động.
2. **Group QR khi 1 người đã paid:** `remaining` giảm, progress bar tăng. Người còn lại vẫn có thể trả qua group QR.
3. **Webhook delay:** Polling 2s có thể miss nếu webhook chậm. FE sẽ catch ở poll tiếp theo.
4. **Group QR hết hạn (1 ngày):** `create_group_payment` gọi lại → tạo code mới (fingerprint cũ đã expire).
