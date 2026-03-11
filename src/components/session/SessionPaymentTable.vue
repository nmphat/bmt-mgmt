<script setup lang="ts">
import { computed } from 'vue'
import { Check, QrCode } from 'lucide-vue-next'
import { useLangStore } from '@/stores/lang'
import { useAuthStore } from '@/stores/auth'
import type { CostSnapshot, MemberCost } from '@/types'

const props = defineProps<{
  snapshots: (CostSnapshot & { display_name: string })[]
  costs: MemberCost[]
  surplus: number
  selectedSnapshotIds: string[]
}>()

const emit = defineEmits<{
  'update:selectedSnapshotIds': [ids: string[]]
  openQR: [snapshot: CostSnapshot, name: string]
  openCash: [snapshot: CostSnapshot, name: string]
}>()

const langStore = useLangStore()
const authStore = useAuthStore()
const t = computed(() => langStore.t)

const selectedIds = computed({
  get: () => props.selectedSnapshotIds,
  set: (v) => emit('update:selectedSnapshotIds', v),
})

const currencyFormatter = new Intl.NumberFormat('vi-VN', {
  style: 'currency',
  currency: 'VND',
  maximumFractionDigits: 0,
})
const formatCurrency = (v: number) => currencyFormatter.format(v)

const getBreakdown = (memberId: string) => props.costs.find((c) => c.member_id === memberId)

const statusClass = (status: string) => ({
  'bg-green-100 text-green-800': status === 'paid',
  'bg-yellow-100 text-yellow-800': status === 'partial',
  'bg-gray-100 text-gray-800': status === 'pending',
})

const statusLabel = (status: string) =>
  status === 'paid'
    ? t.value('payment.paid')
    : status === 'partial'
      ? t.value('payment.partial')
      : t.value('payment.pending')
</script>

<template>
  <div class="bg-white rounded-lg shadow-sm border border-gray-100 mb-6">
    <div class="px-4 md:px-6 py-4 border-b border-gray-100 bg-gray-50">
      <h2 class="text-lg md:text-xl font-semibold text-gray-900">
        {{ t('session.paymentTable') }}
      </h2>
    </div>

    <!-- ── Mobile cards (< md) ── -->
    <div class="md:hidden divide-y divide-gray-100">
      <div
        v-for="snapshot in snapshots"
        :key="snapshot.id"
        class="p-4 flex flex-col gap-3"
        :class="{ 'bg-green-50/40': snapshot.status === 'paid' }"
      >
        <!-- Row 1: checkbox / check + name + badge -->
        <div class="flex items-center gap-3">
          <input
            v-if="authStore.isAuthenticated && snapshot.status !== 'paid'"
            type="checkbox"
            :value="snapshot.id"
            v-model="selectedIds"
            class="h-5 w-5 text-indigo-600 border-gray-300 rounded focus:ring-indigo-500"
          />
          <Check v-else-if="snapshot.status === 'paid'" class="w-5 h-5 text-green-500 shrink-0" />

          <span class="font-semibold text-gray-900 uppercase flex-1">
            {{ snapshot.display_name }}
          </span>
          <span
            class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium"
            :class="statusClass(snapshot.status)"
          >
            {{ statusLabel(snapshot.status) }}
          </span>
        </div>

        <!-- Row 2: amounts -->
        <div class="flex flex-wrap gap-x-6 gap-y-1 text-sm">
          <div>
            <span class="text-gray-500">{{ t('session.mustPay') }}: </span>
            <span class="font-bold text-indigo-700">{{
              formatCurrency(snapshot.final_amount)
            }}</span>
          </div>
          <div>
            <span class="text-gray-500">{{ t('payment.paid') }}: </span>
            <span class="font-semibold text-green-600">{{
              formatCurrency(snapshot.paid_amount)
            }}</span>
          </div>
          <div v-if="snapshot.status !== 'paid'">
            <span class="text-gray-500">{{ t('payment.remaining') ?? 'Còn' }}: </span>
            <span class="font-semibold text-red-600">
              {{ formatCurrency(snapshot.final_amount - snapshot.paid_amount) }}
            </span>
          </div>
        </div>

        <!-- Row 3: breakdown chips -->
        <div class="flex flex-wrap gap-2 text-xs text-gray-500">
          <span class="bg-gray-100 rounded px-2 py-0.5">
            {{ t('session.courtFee') }}:
            {{ formatCurrency(getBreakdown(snapshot.member_id)?.total_court_fee || 0) }}
          </span>
          <span class="bg-gray-100 rounded px-2 py-0.5">
            {{ t('session.shuttleFee') }}:
            {{ formatCurrency(getBreakdown(snapshot.member_id)?.total_shuttle_fee || 0) }}
          </span>
          <span
            v-if="getBreakdown(snapshot.member_id)?.total_extra_fee"
            class="bg-gray-100 rounded px-2 py-0.5"
          >
            {{ t('session.extraFee') }}:
            {{ formatCurrency(getBreakdown(snapshot.member_id)?.total_extra_fee || 0) }}
          </span>
          <span class="bg-gray-100 rounded px-2 py-0.5">
            {{ getBreakdown(snapshot.member_id)?.intervals_count || 0 }} intervals
          </span>
        </div>

        <!-- Row 4: action buttons -->
        <div v-if="snapshot.status !== 'paid'" class="flex gap-2">
          <button
            @click="$emit('openQR', snapshot, snapshot.display_name)"
            class="flex-1 flex items-center justify-center px-3 py-2 border border-indigo-600 text-indigo-600 rounded-md hover:bg-indigo-50 transition text-sm font-medium"
          >
            <QrCode class="w-4 h-4 mr-1.5" />
            {{ t('payment.qrPay') }}
          </button>
          <button
            v-if="authStore.isAdmin"
            @click="$emit('openCash', snapshot, snapshot.display_name)"
            class="flex-1 flex items-center justify-center px-3 py-2 border border-green-600 text-green-600 rounded-md hover:bg-green-50 transition text-sm font-medium"
          >
            {{ t('payment.cashPay') }}
          </button>
        </div>
        <div v-else class="flex items-center text-green-500 text-sm font-medium gap-1">
          <Check class="w-4 h-4" /> {{ t('payment.done') }}
        </div>
      </div>

      <!-- Surplus row (mobile) -->
      <div class="px-4 py-3 bg-gray-50 flex justify-between items-center text-sm">
        <span class="font-bold text-gray-700">{{ t('session.surplusFund') }}</span>
        <span class="font-bold text-green-600">{{ formatCurrency(surplus) }}</span>
      </div>
    </div>

    <!-- ── Desktop table (≥ md) ── -->
    <div class="hidden md:block overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th v-if="authStore.isAuthenticated" scope="col" class="px-3 py-3 w-10"></th>
            <th
              scope="col"
              class="px-6 py-3 text-left text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('common.member') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-right text-sm font-bold text-gray-500 uppercase tracking-wider"
            >
              {{ t('session.mustPay') }}
            </th>
            <th
              scope="col"
              class="px-3 py-3 text-center text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('session.intervalsAbbr') }}
            </th>
            <th
              scope="col"
              class="px-4 py-3 text-right text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('session.courtFee') }}
            </th>
            <th
              scope="col"
              class="px-4 py-3 text-right text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('session.shuttleFee') }}
            </th>
            <th
              scope="col"
              class="px-4 py-3 text-right text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('session.extraFee') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-right text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('payment.paid') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-center text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('common.status') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-center text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('session.pay') }}
            </th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <tr v-for="snapshot in snapshots" :key="snapshot.id">
            <td v-if="authStore.isAuthenticated" class="px-3 py-4 text-center">
              <input
                v-if="snapshot.status !== 'paid'"
                type="checkbox"
                :value="snapshot.id"
                v-model="selectedIds"
                class="h-5 w-5 text-indigo-600 border-gray-300 rounded focus:ring-indigo-500 cursor-pointer"
              />
              <Check v-else class="w-5 h-5 text-green-500 mx-auto" />
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-base font-medium text-gray-900 uppercase">
              {{ snapshot.display_name }}
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-base text-right font-bold text-indigo-700">
              {{ formatCurrency(snapshot.final_amount) }}
            </td>
            <td class="px-3 py-4 whitespace-nowrap text-sm text-center text-gray-500">
              {{ getBreakdown(snapshot.member_id)?.intervals_count || 0 }}
            </td>
            <td class="px-4 py-4 whitespace-nowrap text-xs text-right text-gray-500">
              {{ formatCurrency(getBreakdown(snapshot.member_id)?.total_court_fee || 0) }}
            </td>
            <td class="px-4 py-4 whitespace-nowrap text-xs text-right text-gray-500">
              {{ formatCurrency(getBreakdown(snapshot.member_id)?.total_shuttle_fee || 0) }}
            </td>
            <td class="px-4 py-4 whitespace-nowrap text-xs text-right text-gray-500">
              {{ formatCurrency(getBreakdown(snapshot.member_id)?.total_extra_fee || 0) }}
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-base text-right text-green-600 font-bold">
              {{ formatCurrency(snapshot.paid_amount) }}
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-center">
              <span
                class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"
                :class="statusClass(snapshot.status)"
              >
                {{ statusLabel(snapshot.status) }}
              </span>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-center">
              <div class="flex flex-col gap-1.5 items-center">
                <button
                  v-if="snapshot.status !== 'paid'"
                  @click="$emit('openQR', snapshot, snapshot.display_name)"
                  class="inline-flex items-center px-3 py-1.5 border border-indigo-600 text-indigo-600 rounded-md hover:bg-indigo-50 transition text-sm font-medium w-full justify-center"
                >
                  <QrCode class="w-4 h-4 mr-1.5" />
                  {{ t('payment.qrPay') }}
                </button>
                <button
                  v-if="snapshot.status !== 'paid' && authStore.isAdmin"
                  @click="$emit('openCash', snapshot, snapshot.display_name)"
                  class="inline-flex items-center px-3 py-1.5 border border-green-600 text-green-600 rounded-md hover:bg-green-50 transition text-sm font-medium w-full justify-center"
                >
                  {{ t('payment.cashPay') }}
                </button>
                <span
                  v-else-if="snapshot.status === 'paid'"
                  class="text-green-500 flex items-center justify-center"
                >
                  <Check class="w-5 h-5 mr-1" />
                  <span class="text-sm font-medium">{{ t('payment.done') }}</span>
                </span>
              </div>
            </td>
          </tr>
          <!-- Surplus row -->
          <tr class="bg-gray-50 border-t-2 border-gray-100">
            <td
              :colspan="authStore.isAuthenticated ? 6 : 5"
              class="px-6 py-4 text-right text-sm font-bold text-gray-700"
            >
              {{ t('session.surplusFund') }}
            </td>
            <td class="px-6 py-4 text-right text-base font-bold text-green-600">
              {{ formatCurrency(surplus) }}
            </td>
            <td colspan="2"></td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
