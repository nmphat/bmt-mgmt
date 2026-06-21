# Task 2: Add Cash Button to HomeDebtTable.vue

**Objective:** Add a 💵 Cash button next to the QR Pay button in HomeDebtTable, visible only to admins.

**Files:**
- Modify: `src/components/HomeDebtTable.vue`

**Spec:** `docs/superpowers/specs/2026-06-21-cash-payment-home-design.md` §3.2
**Plan:** `docs/superpowers/plans/2026-06-21-cash-payment-home.md` Task 2

---

## Steps

### Step 1: Add isAdmin prop and pay-cash emit

In `<script setup>`, update `defineProps` (around line 7) to add `isAdmin`:

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

Update `defineEmits` (around line 15) to add `pay-cash`:

```ts
const emit = defineEmits<{
  (e: 'pay-single', memberId: string): void
  (e: 'pay-group', memberIds: string[]): void
  (e: 'pay-cash', memberId: string): void  // NEW
  (e: 'load-more'): void
  (e: 'update:search', value: string): void
}>()
```

### Step 2: Add Cash button to mobile card layout

Find the mobile card action buttons (around line 179). Change `grid-cols-2` to `grid-cols-3` and add cash button:

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

### Step 3: Add Cash button to desktop table

Find the desktop table action cell (around line 281). Add cash button after QR Pay:

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

### Step 4: Verify TypeScript compiles

```bash
cd /home/phat/bmt-mgmt && pnpm exec vue-tsc --noEmit
```

Expected: No errors.

### Step 5: Commit

```bash
git add src/components/HomeDebtTable.vue
git commit -m "feat(debt): add cash button next to QR Pay (admin-only)"
```
