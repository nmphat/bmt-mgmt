<script setup lang="ts">
import { computed } from 'vue'
import { useLangStore } from '@/stores/lang'
import type { MemberCost } from '@/types'

const props = defineProps<{
  costs: MemberCost[]
  surplus: number
}>()

const langStore = useLangStore()
const t = computed(() => langStore.t)

const currencyFormatter = new Intl.NumberFormat('vi-VN', {
  style: 'currency',
  currency: 'VND',
  maximumFractionDigits: 0,
})
const formatCurrency = (v: number) => currencyFormatter.format(v)
</script>

<template>
  <div class="bg-white rounded-lg shadow-sm border border-gray-100 mb-6">
    <div class="px-4 md:px-6 py-4 border-b border-gray-100 bg-gray-50">
      <h2 class="text-lg md:text-xl font-semibold text-gray-900">
        {{ t('session.costSummary') }}
        <span class="text-xs font-normal text-gray-500 ml-1">({{ t('session.live') }})</span>
      </h2>
    </div>

    <!-- ── Mobile cards (< md) ── -->
    <div class="md:hidden divide-y divide-gray-100">
      <div v-for="cost in costs" :key="cost.member_id" class="p-4 flex flex-col gap-2">
        <!-- Name + total -->
        <div class="flex items-center justify-between">
          <span class="font-semibold text-gray-900">{{ cost.display_name }}</span>
          <span class="font-bold text-gray-900 text-base">{{
            formatCurrency(cost.final_total)
          }}</span>
        </div>
        <!-- Breakdown chips -->
        <div class="flex flex-wrap gap-2 text-xs text-gray-500">
          <span class="bg-gray-100 rounded px-2 py-0.5">
            {{ t('session.courtFee') }}: {{ formatCurrency(cost.total_court_fee) }}
          </span>
          <span class="bg-gray-100 rounded px-2 py-0.5">
            {{ t('session.shuttleFee') }}: {{ formatCurrency(cost.total_shuttle_fee) }}
          </span>
          <span v-if="cost.total_extra_fee" class="bg-gray-100 rounded px-2 py-0.5">
            {{ t('session.extraFee') }}: {{ formatCurrency(cost.total_extra_fee) }}
          </span>
          <span class="bg-gray-100 rounded px-2 py-0.5">
            {{ cost.intervals_count }} {{ t('session.numIntervals') }}
          </span>
        </div>
      </div>

      <!-- Surplus (mobile) -->
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
              {{ t('session.total') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-center text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('session.numIntervals') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-right text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('session.courtFee') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-right text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('session.shuttleFee') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-right text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('session.extraFee') }}
            </th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <tr v-for="cost in costs" :key="cost.member_id">
            <td class="px-6 py-4 whitespace-nowrap text-base font-medium text-gray-900">
              {{ cost.display_name }}
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-base text-right font-bold text-gray-900">
              {{ formatCurrency(cost.final_total) }}
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-base text-center text-gray-500">
              {{ cost.intervals_count }}
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-base text-right text-gray-500">
              {{ formatCurrency(cost.total_court_fee) }}
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-base text-right text-gray-500">
              {{ formatCurrency(cost.total_shuttle_fee) }}
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-base text-right text-gray-500">
              {{ formatCurrency(cost.total_extra_fee) }}
            </td>
          </tr>
          <!-- Surplus row -->
          <tr class="bg-gray-50">
            <td colspan="5" class="px-6 py-4 text-right text-base font-bold text-gray-700">
              {{ t('session.surplusFund') }}
            </td>
            <td class="px-6 py-4 text-right text-base font-bold text-green-600">
              {{ formatCurrency(surplus) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
