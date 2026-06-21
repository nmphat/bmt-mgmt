# Task 4: Wire Cash Flow in HomePage.vue

**Objective:** Connect HomeDebtTable cash button to CashPaymentModal via HomePage.vue event handling.

**Files:**
- Modify: `src/views/HomePage.vue`

**Spec:** `docs/superpowers/specs/2026-06-21-cash-payment-home-design.md` §3.3
**Plan:** `docs/superpowers/plans/2026-06-21-cash-payment-home.md` Task 4

---

## Steps

### Step 1: Add imports and auth store

At the top of `<script setup>` (after line 8), add imports:

```ts
import CashPaymentModal from '@/components/CashPaymentModal.vue'
import { useAuthStore } from '@/stores/auth'
```

After `const toast = useToast()` (around line 12), add:

```ts
const authStore = useAuthStore()
```

### Step 2: Add cash payment state

After `const groupPaymentCompleted = ref(false)` (around line 21), add:

```ts
const showCashModal = ref(false)
const selectedCashMember = ref<{ id: string; name: string; debt: number } | null>(null)
```

### Step 3: Add cash payment handler

After the `handlePaymentModalClose` function (around line 197), add:

```ts
function handleCashPay(memberId: string) {
  const member = members.value.find((m) => m.member_id === memberId)
  if (!member) return
  selectedCashMember.value = {
    id: member.member_id,
    name: member.display_name,
    debt: member.total_debt,
  }
  showCashModal.value = true
}

function handleCashModalClose() {
  showCashModal.value = false
  selectedCashMember.value = null
}

async function handleCashSuccess() {
  currentPage.value = 1
  await fetchDebts()
}
```

### Step 4: Update HomeDebtTable template

Find `<HomeDebtTable` in template (around line 208). Add `:is-admin` and `@pay-cash`:

```html
<HomeDebtTable
  :key="debtTableKey"
  :members="members"
  :loading="loading"
  :has-more="hasMore"
  :search="searchQuery"
  :error-message="errorMessage"
  :is-admin="authStore.isAdmin"
  @update:search="handleSearchChange"
  @pay-single="handleSinglePay"
  @pay-group="handleGroupPay"
  @pay-cash="handleCashPay"
  @load-more="loadMore"
/>
```

### Step 5: Add CashPaymentModal to template

After `<PaymentQRModal ... />` closing tag (around line 228), add:

```html
<CashPaymentModal
  v-if="selectedCashMember"
  :show="showCashModal"
  :member-id="selectedCashMember.id"
  :member-name="selectedCashMember.name"
  :total-debt="selectedCashMember.debt"
  @close="handleCashModalClose"
  @success="handleCashSuccess"
/>
```

### Step 6: Verify TypeScript compiles

```bash
cd /home/phat/bmt-mgmt && pnpm exec vue-tsc --noEmit
```

Expected: No errors.

### Step 7: Commit

```bash
git add src/views/HomePage.vue
git commit -m "feat(home): wire cash payment flow with CashPaymentModal"
```
