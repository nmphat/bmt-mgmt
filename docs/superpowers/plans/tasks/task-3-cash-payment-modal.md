# Task 3: Create CashPaymentModal.vue Component

**Objective:** Create the CashPaymentModal component with stale-data guard, allocation preview, and 2-step flow.

**Files:**
- Create: `src/components/CashPaymentModal.vue`

**Spec:** `docs/superpowers/specs/2026-06-21-cash-payment-home-design.md` §3.1
**Plan:** `docs/superpowers/plans/2026-06-21-cash-payment-home.md` Task 3

---

## Steps

### Step 1: Create the component file

Create `src/components/CashPaymentModal.vue` with the complete implementation from the plan (Task 3, Step 1). The component includes:

- **Props:** `show`, `memberId`, `memberName`, `totalDebt`
- **Emits:** `close`, `success`
- **Data flow:** watch `show` → fetchSnapshots → preview → confirm → loop RPC
- **Stale-data guard:** Re-fetches `session_costs_snapshot` before each RPC call
- **Partial failure tracking:** `paidSnapshotIds[]` + `failedCount`
- **Success guard:** Only `emit('success')` when `paidSnapshotIds.length > 0`
- **Amount clamping:** `@blur` handler caps amount to `[0, totalDebt]` with NaN guard (`amount || 0`)
- **NaN guard:** `proceedToConfirm` checks `isNaN(amount.value)` before proceeding

Key implementation details:
- Interface `UnpaidSnapshot { snapshot_id, session_title, start_time, remaining_amount }`
- Query: `view_member_session_details` with `.eq('member_id', memberId).gt('remaining_amount', 0).order('start_time', { ascending: true })`
- RPC: `add_manual_payment(p_snapshot_id, p_amount, p_note)` with `t('payment.cash')` as note
- i18n keys used: `payment.manualTitle`, `payment.cashAllocationTitle`, `payment.cashAllocationSummary`, `payment.cashPaymentSuccess`, `payment.cashPaymentPartial`, `payment.amount`, `payment.cash`, `payment.confirmCash`, `payment.amountPositiveError`, `debt.noDebt`, `debt.totalDebt`, `common.back`, `toast.error`

### Step 2: Verify TypeScript compiles

```bash
cd /home/phat/bmt-mgmt && pnpm exec vue-tsc --noEmit
```

Expected: No errors.

### Step 3: Commit

```bash
git add src/components/CashPaymentModal.vue
git commit -m "feat(payment): add CashPaymentModal component with stale-data guard"
```
