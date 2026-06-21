# Task 1: Add i18n Keys to messages.ts

**Objective:** Add 4 new Vietnamese and 4 new English i18n keys for the cash payment allocation flow.

**Files:**
- Modify: `src/locales/messages.ts`

**Spec:** `docs/superpowers/specs/2026-06-21-cash-payment-home-design.md` §3.4
**Plan:** `docs/superpowers/plans/2026-06-21-cash-payment-home.md` Task 1

---

## Steps

### Step 1: Read messages.ts to find insertion points

Read `src/locales/messages.ts` and locate:
- Vietnamese `payment` object — find line with `cashPay: '💵 Tiền mặt',` (around line 244)
- English `payment` object — find line with `cashPay: '💵 Cash',` (around line 597)

### Step 2: Add Vietnamese keys

After the `cashPay: '💵 Tiền mặt',` line, insert:

```ts
cashAllocationTitle: 'Xác nhận thu tiền mặt',
cashAllocationSummary: 'Phân bổ {amount} cho {count} buổi',
cashPaymentSuccess: 'Đã thu tiền mặt thành công cho {count} buổi',
cashPaymentPartial: 'Đã thu {success}/{total} buổi. Lỗi: {error}',
```

### Step 3: Add English keys

After the `cashPay: '💵 Cash',` line, insert:

```ts
cashAllocationTitle: 'Confirm cash collection',
cashAllocationSummary: 'Allocate {amount} to {count} sessions',
cashPaymentSuccess: 'Cash payment recorded for {count} sessions',
cashPaymentPartial: 'Paid {success}/{total} sessions. Error: {error}',
```

### Step 4: Verify TypeScript compiles

```bash
cd /home/phat/bmt-mgmt && pnpm exec vue-tsc --noEmit
```

Expected: No errors.

### Step 5: Commit

```bash
git add src/locales/messages.ts
git commit -m "feat(i18n): add cash payment allocation keys (vi+en)"
```
