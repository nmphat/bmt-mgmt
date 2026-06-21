# Cash Payment on Home Page — Design Spec

> **Date:** 2026-06-21
> **Project:** bmt-mgmt (Vue 3 + Supabase)
> **Approach:** A — Client-side loop (no DB migration)

---

## 1. Overview

Add a **💵 Cash** button next to the existing **QR Pay** button on the home page debt table. When an admin clicks it, a modal opens showing all unpaid snapshots for that member (oldest session first). The admin enters a cash amount, and the system auto-allocates it across snapshots sequentially using the existing `add_manual_payment` RPC.

**Goal:** Allow admins to quickly record cash payments for a member's total debt from the home page, without navigating to individual sessions.

---

## 2. Current State

### Home Page (`HomeDebtTable.vue`)
- Shows member debt summary: name, total debt, unpaid session count
- **Mobile card**: "Details" link + "Create Payment QR" button
- **Desktop table**: checkbox, member name, unpaid count, debt amount, "QR Pay" button
- **Group selection**: floating action bar with "Create Group QR" for selected members
- **No cash button exists** — cash payment only available in SessionDetailView and SessionPaymentTable

### Existing Cash Payment Pattern (`ManualPaymentModal.vue`)
- Works on a **single snapshot** at a time
- Flow: entry (amount input) → review → confirm
- RPC: `add_manual_payment(p_snapshot_id, p_amount, p_note)`
- Transaction ID: `CASH-{epoch}` (server-generated)
- Payment method: `'cash'`
- Updates `session_costs_snapshot.paid_amount` and `status`

### Existing Data Sources
- `view_member_debt_summary` — member-level debt totals (used by HomePage)
- `view_member_session_details` — per-snapshot details with `session_id`, `start_time`, `remaining_amount` (used by MemberDetailView)
- `add_manual_payment` RPC — records a single cash payment

---

## 3. Proposed Changes

### 3.1 New Component: `CashPaymentModal.vue`

**Location:** `src/components/CashPaymentModal.vue`

**Props:**
```ts
{
  show: boolean
  memberId: string
  memberName: string
  totalDebt: number
}
```

**Emits:** `close`, `success`

**Behavior:**
1. On open, fetch unpaid snapshots from `view_member_session_details` where `member_id = memberId` and `remaining_amount > 0`, ordered by `start_time ASC` (oldest first)
2. Display: member name, total debt, list of snapshots (session title, date, remaining)
3. Input: amount field (default = total debt, min = 0, max = total debt)
4. Submit: loop through snapshots, call `add_manual_payment` for each:
   - **Re-fetch** `remaining_amount` for current snapshot before each RPC call (stale data guard)
   - Skip if `fetched_remaining <= 0` (already paid by another admin)
   - `payment = min(fetched_remaining, remainingInput)`
   - Skip if `payment <= 0`
   - Call `add_manual_payment(snapshot_id, payment, t('payment.cash'))`
   - Deduct from `remainingInput`
   - Track `paidSnapshotIds[]` for success reporting
   - Stop when `remainingInput <= 0` or no more snapshots
5. On full success: toast `cashPaymentSuccess` with count, emit `success`
6. On partial failure: toast `cashPaymentPartial` with success/total counts, emit `success` (to refresh debt table showing partial progress)

**UI:**
- Same modal pattern as `ManualPaymentModal.vue` (overlay, slide-up on mobile, centered on desktop)
- Green accent (cash theme) vs indigo (QR theme)
- Two-step: allocation preview → confirm

### 3.2 Modify: `HomeDebtTable.vue`

**Changes:**
- Add 💵 Cash button next to QR Pay button (both mobile card and desktop table)
- Cash button visible only when `authStore.isAdmin` is true
- Cash button style: green border/text (matching `SessionPaymentTable.vue` cash button pattern)
- Emit new event: `pay-cash(memberId: string)`

**Mobile card (line ~186-192):**
```html
<div class="grid grid-cols-3 gap-2 ...">  <!-- was grid-cols-2 -->
  <router-link ...>Details</router-link>
  <button @click="emit('pay-single', ...)" ...>QR Pay</button>
  <button v-if="isAdmin" @click="emit('pay-cash', ...)" ...>💵 Cash</button>
</div>
```

**Desktop table (line ~281-288):**
```html
<td ...>
  <button @click="emit('pay-single', ...)" ...>QR Pay</button>
  <button v-if="isAdmin" @click="emit('pay-cash', ...)" ...>💵 Cash</button>
</td>
```

**New prop needed:**
```ts
isAdmin: boolean  // passed from HomePage
```

**New emit:**
```ts
(e: 'pay-cash', memberId: string): void
```

### 3.3 Modify: `HomePage.vue`

**Changes:**
- Import `CashPaymentModal`
- Import `useAuthStore` from `@/stores/auth` (not currently imported)
- Add `const authStore = useAuthStore()`
- Add state: `showCashModal`, `selectedCashMember` (id + name + debt)
- Handle `@pay-cash` event from HomeDebtTable
- Pass `:isAdmin="authStore.isAdmin"` prop to HomeDebtTable
- Render `CashPaymentModal` in template

### 3.4 Modify: `messages.ts`

**Add keys (only new ones — reuse existing `payment.cashPay` for button label):**
```ts
vi: {
  payment: {
    cashAllocationTitle: 'Xác nhận thu tiền mặt',
    cashAllocationSummary: 'Phân bổ {amount} cho {count} buổi',
    cashPaymentSuccess: 'Đã thu tiền mặt thành công cho {count} buổi',
    cashPaymentPartial: 'Đã thu {success}/{total} buổi. Lỗi: {error}',
  }
},
en: {
  payment: {
    cashAllocationTitle: 'Confirm cash collection',
    cashAllocationSummary: 'Allocate {amount} to {count} sessions',
    cashPaymentSuccess: 'Cash payment recorded for {count} sessions',
    cashPaymentPartial: 'Paid {success}/{total} sessions. Error: {error}',
  }
}
```

> Button label reuses existing `payment.cashPay` (line 244 vi / line 597 en).

---

## 4. Data Flow

```
HomePage
  ├── HomeDebtTable (isAdmin prop)
  │     ├── [QR Pay] → emit('pay-single') → createPaymentForMembers → PaymentQRModal
  │     └── [💵 Cash] → emit('pay-cash') → handleCashPay(memberId)
  │
  └── CashPaymentModal (show, memberId, memberName, totalDebt)
        ├── fetch unpaid snapshots (view_member_session_details)
        ├── allocate: loop add_manual_payment RPC
        └── emit('success') → fetchDebts() refresh
```

---

## 5. Edge Cases

| Case | Handling |
|------|----------|
| **Amount > total debt** | Cap at total debt, show warning toast |
| **Amount = 0** | Disable submit button |
| **Partial pay (amount < total debt)** | Allocate oldest-first, last snapshot gets partial |
| **RPC fails mid-loop** | Stop, toast error with success count, emit success (partial refresh) |
| **No unpaid snapshots** | Toast info "No debt", close modal |
| **Concurrent modification** | RPC has server-side check; if snapshot already paid, skip and continue |
| **Non-admin user** | Cash button hidden (v-if="isAdmin") |

---

## 6. No DB Changes

This approach requires **zero database changes**:
- Reuses `view_member_session_details` view (already exists)
- Reuses `add_manual_payment` RPC (already exists)
- No new tables, columns, functions, or triggers

---

## 7. Files Summary

| File | Action | Lines Changed (est.) |
|------|--------|---------------------|
| `src/components/CashPaymentModal.vue` | **Create** | ~200 |
| `src/components/HomeDebtTable.vue` | **Modify** | ~25 |
| `src/views/HomePage.vue` | **Modify** | ~30 |
| `src/locales/messages.ts` | **Modify** | ~10 |
