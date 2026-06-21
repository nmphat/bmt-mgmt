# Cash Payment on Home Page — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 💵 Cash button next to QR Pay on the home page debt table, with a modal for admin-only cash payment that auto-allocates across unpaid snapshots oldest-first.

**Architecture:** Client-side loop using existing `add_manual_payment` RPC. No DB migration. Re-fetches remaining_amount before each RPC call to guard against stale data. New `CashPaymentModal.vue` component follows same pattern as existing `ManualPaymentModal.vue`.

**Tech Stack:** Vue 3 + TypeScript + Tailwind CSS + Supabase (PostgREST RPC) + vue-toastification + lucide-vue-next

**Spec:** `docs/superpowers/specs/2026-06-21-cash-payment-home-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `src/components/CashPaymentModal.vue` | **Create** | Modal: fetch snapshots, allocate cash, loop RPC |
| `src/components/HomeDebtTable.vue` | **Modify** | Add cash button (mobile + desktop), emit `pay-cash`, add `isAdmin` prop |
| `src/views/HomePage.vue` | **Modify** | Wire cash flow: auth store, event handler, modal render |
| `src/locales/messages.ts` | **Modify** | Add 4 i18n keys (vi + en) |

---

### Task 1: Add i18n Keys to messages.ts

**Files:**
- Modify: `src/locales/messages.ts`

- [ ] **Step 1: Read current messages.ts to find exact insertion points**

Read `src/locales/messages.ts` and locate:
- Vietnamese `payment` object (around line 242-244)
- English `payment` object (around line 594-597)

- [ ] **Step 2: Add Vietnamese keys**

After the existing `cashPay: '💵 Tiền mặt',` line (around line 244), add:

```ts
cashAllocationTitle: 'Xác nhận thu tiền mặt',
cashAllocationSummary: 'Phân bổ {amount} cho {count} buổi',
cashPaymentSuccess: 'Đã thu tiền mặt thành công cho {count} buổi',
cashPaymentPartial: 'Đã thu {success}/{total} buổi. Lỗi: {error}',
```

- [ ] **Step 3: Add English keys**

After the existing `cashPay: '💵 Cash',` line (around line 597), add:

```ts
cashAllocationTitle: 'Confirm cash collection',
cashAllocationSummary: 'Allocate {amount} to {count} sessions',
cashPaymentSuccess: 'Cash payment recorded for {count} sessions',
cashPaymentPartial: 'Paid {success}/{total} sessions. Error: {error}',
```

- [ ] **Step 4: Verify TypeScript compiles**

Run: `cd /home/phat/bmt-mgmt && pnpm exec vue-tsc --noEmit`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add src/locales/messages.ts
git commit -m "feat(i18n): add cash payment allocation keys (vi+en)"
```

---

### Task 2: Modify HomeDebtTable.vue — Add Cash Button

**Files:**
- Modify: `src/components/HomeDebtTable.vue`

- [ ] **Step 1: Add isAdmin prop and pay-cash emit**

In `<script setup>`, update `defineProps` to add:

```ts
const props = defineProps<{
  members: MemberDebtSummary[]
  loading: boolean
  hasMore: boolean
  search: string
  errorMessage?: string
  isAdmin?: boolean  // NEW
}>()
```

Update `defineEmits` to add:

```ts
const emit = defineEmits<{
  (e: 'pay-single', memberId: string): void
  (e: 'pay-group', memberIds: string[]): void
  (e: 'pay-cash', memberId: string): void  // NEW
  (e: 'load-more'): void
  (e: 'update:search', value: string): void
}>()
```

- [ ] **Step 2: Add Cash button to mobile card layout**

Find the mobile card action buttons (around line 179, the `<div class="grid grid-cols-2 gap-2 ...">` block). Change `grid-cols-2` to `grid-cols-3` and add cash button after QR button:

```html
<div class="grid grid-cols-3 gap-2 border-t border-gray-100 px-4 py-3">
  <router-link
    :to="`/member/${member.member_id}`"
    class="inline-flex min-h-11 items-center justify-center whitespace-nowrap rounded-lg border border-indigo-100 bg-white px-3 text-sm font-bold text-indigo-600 transition hover:bg-indigo-50 focus:outline-none focus:ring-2 focus:ring-indigo-500"
  >
    {{ t('debt.details') }}
  </router-link>
  <button
    @click="emit('pay-single', member.member_id)"
    class="inline-flex min-h-11 items-center justify-center gap-2 whitespace-nowrap rounded-lg bg-indigo-600 px-3 text-sm font-bold text-white shadow-sm transition hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
  >
    <QrCode class="h-4 w-4" />
    <span>{{ t('debt.createPaymentQR') }}</span>
  </button>
  <button
    v-if="isAdmin"
    @click="emit('pay-cash', member.member_id)"
    class="inline-flex min-h-11 items-center justify-center gap-2 whitespace-nowrap rounded-lg border border-green-600 bg-white px-3 text-sm font-bold text-green-600 transition hover:bg-green-50 focus:outline-none focus:ring-2 focus:ring-green-500"
  >
    <span>{{ t('payment.cashPay') }}</span>
  </button>
</div>
```

- [ ] **Step 3: Add Cash button to desktop table**

Find the desktop table action cell (around line 281-288, the `<td>` with QR Pay button). Add cash button after it:

```html
<td class="whitespace-nowrap px-6 py-4 text-center text-sm font-medium">
  <button
    @click="emit('pay-single', member.member_id)"
    class="inline-flex items-center rounded-md bg-indigo-50 px-3 py-1 text-indigo-600 transition hover:bg-indigo-100 hover:text-indigo-900"
  >
    <QrCode class="mr-1 h-4 w-4" />
    {{ t('payment.qrPay') }}
  </button>
  <button
    v-if="isAdmin"
    @click="emit('pay-cash', member.member_id)"
    class="ml-2 inline-flex items-center rounded-md border border-green-600 bg-white px-3 py-1 text-green-600 transition hover:bg-green-50 hover:text-green-900"
  >
    {{ t('payment.cashPay') }}
  </button>
</td>
```

- [ ] **Step 4: Verify TypeScript compiles**

Run: `cd /home/phat/bmt-mgmt && pnpm exec vue-tsc --noEmit`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add src/components/HomeDebtTable.vue
git commit -m "feat(debt): add cash button next to QR Pay (admin-only)"
```

---

### Task 3: Create CashPaymentModal.vue Component

**Files:**
- Create: `src/components/CashPaymentModal.vue`

- [ ] **Step 1: Create the component file**

Create `src/components/CashPaymentModal.vue` with the following complete implementation:

```vue
<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import { useToast } from 'vue-toastification'
import { useLangStore } from '@/stores/lang'
import { DollarSign, Loader2, X, CheckCircle, AlertTriangle } from 'lucide-vue-next'

interface UnpaidSnapshot {
  snapshot_id: string
  session_title: string
  start_time: string
  remaining_amount: number
}

const props = defineProps<{
  show: boolean
  memberId: string
  memberName: string
  totalDebt: number
}>()

const emit = defineEmits(['close', 'success'])
const toast = useToast()
const langStore = useLangStore()
const t = computed(() => langStore.t)

const snapshots = ref<UnpaidSnapshot[]>([])
const amount = ref(0)
const isSubmitting = ref(false)
const loadingSnapshots = ref(false)
const currentStep = ref<'preview' | 'confirm'>('preview')

const formatCurrency = (value: number) => {
  return new Intl.NumberFormat(langStore.currentLang === 'vi' ? 'vi-VN' : 'en-US', {
    style: 'currency',
    currency: 'VND',
    maximumFractionDigits: 0,
  }).format(value)
}

const allocationPreview = computed(() => {
  let remaining = amount.value
  return snapshots.value.map((s) => {
    const alloc = Math.min(s.remaining_amount, remaining)
    remaining = Math.max(0, remaining - alloc)
    return { ...s, allocated: alloc }
  })
})

const totalAllocated = computed(() =>
  allocationPreview.value.reduce((sum, s) => sum + s.allocated, 0),
)

watch(
  () => props.show,
  async (show) => {
    if (show) {
      currentStep.value = 'preview'
      await fetchSnapshots()
      amount.value = props.totalDebt
    }
  },
)

async function fetchSnapshots() {
  loadingSnapshots.value = true
  try {
    const { data, error } = await supabase
      .from('view_member_session_details')
      .select('snapshot_id, session_title, start_time, remaining_amount')
      .eq('member_id', props.memberId)
      .gt('remaining_amount', 0)
      .order('start_time', { ascending: true })

    if (error) throw error
    snapshots.value = (data as UnpaidSnapshot[]) || []
  } catch (error: any) {
    console.error('Error fetching snapshots:', error)
    toast.error(t.value('toast.error', { message: error.message }))
  } finally {
    loadingSnapshots.value = false
  }
}

function proceedToConfirm() {
  if (isNaN(amount.value) || amount.value <= 0) {
    toast.error(t.value('payment.amountPositiveError'))
    return
  }
  if (snapshots.value.length === 0) {
    toast.info(t.value('debt.noDebt'))
    return
  }
  currentStep.value = 'confirm'
}

async function handleConfirm() {
  isSubmitting.value = true
  let remainingInput = amount.value
  const paidSnapshotIds: string[] = []
  let failedCount = 0

  try {
    for (const snapshot of snapshots.value) {
      if (remainingInput <= 0) break

      // Re-fetch remaining_amount to guard against stale data
      const { data: freshSnapshot, error: fetchError } = await supabase
        .from('session_costs_snapshot')
        .select('paid_amount, final_amount')
        .eq('id', snapshot.snapshot_id)
        .single()

      if (fetchError || !freshSnapshot) {
        failedCount++
        continue
      }

      const freshRemaining =
        (freshSnapshot.final_amount || 0) - (freshSnapshot.paid_amount || 0)
      if (freshRemaining <= 0) continue // Already paid by another admin

      const payment = Math.min(freshRemaining, remainingInput)
      if (payment <= 0) continue

      const { error: rpcError } = await supabase.rpc('add_manual_payment', {
        p_snapshot_id: snapshot.snapshot_id,
        p_amount: payment,
        p_note: t.value('payment.cash'),
      })

      if (rpcError) {
        failedCount++
        continue
      }

      remainingInput -= payment
      paidSnapshotIds.push(snapshot.snapshot_id)
    }

    if (failedCount === 0) {
      toast.success(
        t.value('payment.cashPaymentSuccess', { count: paidSnapshotIds.length }),
      )
    } else {
      toast.warning(
        t.value('payment.cashPaymentPartial', {
          success: paidSnapshotIds.length,
          total: snapshots.value.length,
          error: failedCount,
        }),
      )
    }

    if (paidSnapshotIds.length > 0) {
      emit('success')
    }
    emit('close')
  } catch (error: any) {
    console.error('Error in cash payment loop:', error)
    toast.error(t.value('toast.error', { message: error.message }))
  } finally {
    isSubmitting.value = false
  }
}

function handleClose() {
  if (isSubmitting.value) return
  emit('close')
}
</script>

<template>
  <div
    v-if="show"
    class="fixed inset-0 z-50"
    aria-labelledby="cash-payment-title"
    role="dialog"
    aria-modal="true"
  >
    <div
      class="flex min-h-screen items-end justify-center px-0 text-center sm:items-center sm:px-4 sm:py-8"
    >
      <!-- Overlay -->
      <div
        class="fixed inset-0 bg-gray-500/75 transition-opacity"
        aria-hidden="true"
        @click="handleClose"
      ></div>

      <!-- Modal -->
      <div
        class="relative z-10 flex max-h-[88dvh] w-full flex-col overflow-hidden rounded-t-2xl bg-white text-left align-bottom shadow-xl transition-all sm:max-w-md sm:rounded-2xl"
      >
        <!-- Header -->
        <div class="shrink-0 border-b border-gray-100 bg-white px-4 py-4 sm:px-6">
          <div class="flex items-start justify-between gap-3">
            <h3
              class="flex items-center gap-2 text-[20px] font-bold leading-[1.2] text-gray-900"
              id="cash-payment-title"
            >
              <DollarSign class="h-6 w-6 text-green-600" />
              {{ currentStep === 'confirm' ? t('payment.cashAllocationTitle') : t('payment.manualTitle') }}
            </h3>
            <button
              type="button"
              @click="handleClose"
              :disabled="isSubmitting"
              class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-full text-gray-500 hover:bg-gray-100 hover:text-gray-700 focus:outline-none focus:ring-2 focus:ring-green-500 disabled:opacity-50"
            >
              <X class="h-5 w-5" />
            </button>
          </div>
        </div>

        <!-- Body -->
        <div class="flex-1 overflow-y-auto px-4 py-4 sm:px-6">
          <!-- Loading -->
          <div v-if="loadingSnapshots" class="flex items-center justify-center py-8">
            <Loader2 class="h-8 w-8 animate-spin text-green-600" />
          </div>

          <!-- No debt -->
          <div
            v-else-if="snapshots.length === 0"
            class="py-8 text-center text-gray-500"
          >
            {{ t('debt.noDebt') }}
          </div>

          <!-- Preview step -->
          <template v-else-if="currentStep === 'preview'">
            <div class="mb-4 rounded-lg bg-green-50 p-3 text-sm text-green-800">
              <strong>{{ memberName }}</strong> — {{ t('debt.totalDebt') }}:
              <strong class="text-green-700">{{ formatCurrency(totalDebt) }}</strong>
            </div>

            <!-- Amount input -->
            <div class="mb-4">
              <label class="mb-1 block text-sm font-bold text-gray-700">
                {{ t('payment.amount') }}
              </label>
              <input
                v-model.number="amount"
                type="number"
                :min="0"
                :max="totalDebt"
                @blur="amount = Math.min(Math.max(0, amount || 0), totalDebt)"
                class="w-full rounded-lg border border-gray-300 px-4 py-3 text-lg font-bold text-gray-900 focus:border-green-500 focus:ring-2 focus:ring-green-500/20"
              />
            </div>

            <!-- Allocation preview -->
            <div class="mb-2 text-sm font-bold text-gray-700">
              {{ t('payment.cashAllocationSummary', { amount: formatCurrency(totalAllocated), count: snapshots.length }) }}
            </div>
            <div class="space-y-2">
              <div
                v-for="s in allocationPreview"
                :key="s.snapshot_id"
                class="flex items-center justify-between rounded-lg border border-gray-200 px-3 py-2 text-sm"
              >
                <div class="min-w-0 flex-1">
                  <div class="truncate font-medium text-gray-900">{{ s.session_title }}</div>
                  <div class="text-xs text-gray-500">
                    {{ new Date(s.start_time).toLocaleDateString() }}
                  </div>
                </div>
                <div class="ml-3 text-right">
                  <div class="font-bold text-gray-900">{{ formatCurrency(s.allocated) }}</div>
                  <div class="text-xs text-gray-500">/ {{ formatCurrency(s.remaining_amount) }}</div>
                </div>
              </div>
            </div>
          </template>

          <!-- Confirm step -->
          <template v-else-if="currentStep === 'confirm'">
            <div class="space-y-4 py-4 text-center">
              <CheckCircle class="mx-auto h-12 w-12 text-green-500" />
              <p class="text-lg font-bold text-gray-900">
              {{ t('payment.cashAllocationSummary', { amount: formatCurrency(totalAllocated), count: snapshots.length }) }}
              </p>
              <p class="text-sm text-gray-500">
                {{ t('payment.cashAllocationTitle') }}
              </p>
            </div>
          </template>
        </div>

        <!-- Footer -->
        <div class="shrink-0 border-t border-gray-100 bg-white px-4 py-4 sm:px-6">
          <template v-if="currentStep === 'preview'">
            <button
              @click="proceedToConfirm"
              :disabled="amount <= 0 || snapshots.length === 0"
              class="flex w-full items-center justify-center gap-2 rounded-xl bg-green-600 px-4 py-3 text-base font-bold text-white shadow-sm transition hover:bg-green-500 focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-offset-2 disabled:opacity-50"
            >
              {{ t('payment.confirmCash') }}
            </button>
          </template>
          <template v-else>
            <div class="flex gap-3">
              <button
                @click="currentStep = 'preview'"
                :disabled="isSubmitting"
                class="flex-1 rounded-xl border border-gray-300 bg-white px-4 py-3 text-base font-bold text-gray-700 transition hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-green-500 disabled:opacity-50"
              >
                <AlertTriangle class="mr-1 inline h-4 w-4" />
                {{ t('common.back') }}
              </button>
              <button
                @click="handleConfirm"
                :disabled="isSubmitting"
                class="flex flex-1 items-center justify-center gap-2 rounded-xl bg-green-600 px-4 py-3 text-base font-bold text-white shadow-sm transition hover:bg-green-500 focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-offset-2 disabled:opacity-50"
              >
                <Loader2 v-if="isSubmitting" class="h-4 w-4 animate-spin" />
                {{ t('payment.confirmCash') }}
              </button>
            </div>
          </template>
        </div>
      </div>
    </div>
  </div>
</template>
```

- [ ] **Step 2: Verify TypeScript compiles**

Run: `cd /home/phat/bmt-mgmt && pnpm exec vue-tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add src/components/CashPaymentModal.vue
git commit -m "feat(payment): add CashPaymentModal component with stale-data guard"
```

---

### Task 4: Wire Cash Flow in HomePage.vue

**Files:**
- Modify: `src/views/HomePage.vue`

- [ ] **Step 1: Add imports and auth store**

At the top of `<script setup>`, add after existing imports:

```ts
import CashPaymentModal from '@/components/CashPaymentModal.vue'
import { useAuthStore } from '@/stores/auth'
```

After `const toast = useToast()`, add:

```ts
const authStore = useAuthStore()
```

- [ ] **Step 2: Add cash payment state**

After `const groupPaymentCompleted = ref(false)`, add:

```ts
const showCashModal = ref(false)
const selectedCashMember = ref<{ id: string; name: string; debt: number } | null>(null)
```

- [ ] **Step 3: Add cash payment handler**

After `handlePaymentModalClose` function, add:

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
  debtTableKey.value += 1
}
```

- [ ] **Step 4: Update HomeDebtTable template**

Find the `<HomeDebtTable` component in template. Add `isAdmin` prop and `@pay-cash` event:

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

- [ ] **Step 5: Add CashPaymentModal to template**

After the `<PaymentQRModal ... />` closing tag, add:

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

- [ ] **Step 6: Verify TypeScript compiles**

Run: `cd /home/phat/bmt-mgmt && pnpm exec vue-tsc --noEmit`
Expected: No errors

- [ ] **Step 7: Commit**

```bash
git add src/views/HomePage.vue
git commit -m "feat(home): wire cash payment flow with CashPaymentModal"
```

---

### Task 5: Final Verification

**Files:**
- Verify all modified files

- [ ] **Step 1: TypeScript check**

Run: `cd /home/phat/bmt-mgmt && pnpm exec vue-tsc --noEmit`
Expected: No errors

- [ ] **Step 2: Build check**

Run: `cd /home/phat/bmt-mgmt && pnpm run build`
Expected: Build succeeds

- [ ] **Step 3: Check for stale references**

Run: `cd /home/phat/bmt-mgmt && grep -rn "cashPayHome" src/`
Expected: No results (key was removed from spec)

- [ ] **Step 4: Verify i18n keys exist**

Run: `cd /home/phat/bmt-mgmt && grep -n "cashAllocationTitle\|cashPaymentSuccess\|cashPaymentPartial\|cashAllocationSummary" src/locales/messages.ts`
Expected: 8 matches (4 vi + 4 en)

- [ ] **Step 5: Verify isAdmin prop threaded correctly**

Run: `cd /home/phat/bmt-mgmt && grep -n "isAdmin" src/components/HomeDebtTable.vue`
Expected: matches in defineProps and v-if directives

- [ ] **Step 6: Final commit if needed**

```bash
git add -A
git commit -m "feat(payment): complete cash payment on home page"
```
