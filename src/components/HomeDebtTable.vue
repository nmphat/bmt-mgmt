<script setup lang="ts">
import { ref, computed } from 'vue'
import type { MemberDebtSummary } from '@/types'
import { useLangStore } from '@/stores/lang'
import { CreditCard } from 'lucide-vue-next'

const props = defineProps<{
  members: MemberDebtSummary[]
  loading: boolean
  hasMore: boolean
}>()

const emit = defineEmits<{
  (e: 'pay-single', memberId: string): void
  (e: 'pay-group', memberIds: string[]): void
  (e: 'load-more'): void
}>()

const langStore = useLangStore()
const t = computed(() => langStore.t)

const selectedMemberIds = ref<string[]>([])

const formatCurrency = (value: number) => {
  return new Intl.NumberFormat(langStore.currentLang === 'vi' ? 'vi-VN' : 'en-US', {
    style: 'currency',
    currency: 'VND',
    maximumFractionDigits: 0,
  }).format(value)
}

const toggleSelection = (memberId: string) => {
  if (selectedMemberIds.value.includes(memberId)) {
    selectedMemberIds.value = selectedMemberIds.value.filter((id) => id !== memberId)
  } else {
    selectedMemberIds.value.push(memberId)
  }
}

const toggleAll = () => {
  if (selectedMemberIds.value.length === props.members.length) {
    selectedMemberIds.value = []
  } else {
    selectedMemberIds.value = props.members.map((m) => m.member_id)
  }
}

const totalSelectedDebt = computed(() => {
  return props.members
    .filter((m) => selectedMemberIds.value.includes(m.member_id))
    .reduce((sum, m) => sum + m.total_debt, 0)
})

const handlePayGroup = () => {
  emit('pay-group', selectedMemberIds.value)
}
</script>

<template>
  <div>
    <div class="overflow-x-auto bg-white rounded-lg shadow border border-gray-200">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th scope="col" class="px-6 py-3 text-left">
              <input
                type="checkbox"
                :checked="selectedMemberIds.length === members.length && members.length > 0"
                @change="toggleAll"
                class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500 h-4 w-4 cursor-pointer"
              />
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('common.member') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('debt.unpaidSessions') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('debt.totalDebt') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('debt.action') }}
            </th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <tr v-if="loading && members.length === 0">
            <td colspan="5" class="px-6 py-12 text-center">
              <div class="flex justify-center">
                <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-indigo-600"></div>
              </div>
            </td>
          </tr>
          <tr v-else-if="members.length === 0">
            <td colspan="5" class="px-6 py-12 text-center text-gray-500">
              {{ t('debt.noDebt') }}
            </td>
          </tr>
          <tr v-for="member in members" :key="member.member_id" class="hover:bg-gray-50">
            <td class="px-6 py-4 whitespace-nowrap">
              <input
                type="checkbox"
                :checked="selectedMemberIds.includes(member.member_id)"
                @change="toggleSelection(member.member_id)"
                class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500 h-4 w-4 cursor-pointer"
              />
            </td>
            <td class="px-6 py-4 whitespace-nowrap">
              <router-link :to="`/member/${member.member_id}`" class="flex items-center group">
                <div
                  class="w-8 h-8 rounded-full bg-indigo-100 flex items-center justify-center text-indigo-600 font-bold mr-3 group-hover:bg-indigo-200 transition"
                >
                  {{ member.display_name.charAt(0).toUpperCase() }}
                </div>
                <span
                  class="text-sm font-medium text-gray-900 group-hover:text-indigo-600 transition"
                  >{{ member.display_name }}</span
                >
              </router-link>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-center text-sm text-gray-500">
              <span
                class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800"
              >
                {{ member.unpaid_session_count }}
              </span>
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-bold text-red-600">
              {{ formatCurrency(member.total_debt) }}
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-center text-sm font-medium">
              <button
                @click="emit('pay-single', member.member_id)"
                class="text-indigo-600 hover:text-indigo-900 bg-indigo-50 px-3 py-1 rounded-md hover:bg-indigo-100 transition inline-flex items-center"
              >
                <CreditCard class="w-4 h-4 mr-1" />
                {{ t('payment.pay') }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Load More -->
    <div v-if="hasMore" class="mt-4 text-center">
      <button
        @click="emit('load-more')"
        :disabled="loading"
        class="px-6 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50"
      >
        {{ loading ? t('common.loading') : t('common.view') + ' ' + t('common.more') }}
      </button>
    </div>

    <!-- Floating Action Bar -->
    <div
      v-if="selectedMemberIds.length > 0"
      class="fixed bottom-6 left-1/2 transform -translate-x-1/2 bg-gray-900 text-white px-6 py-3 rounded-full shadow-lg flex items-center gap-6 z-50 animate-fade-in-up"
    >
      <div class="flex flex-col">
        <span class="text-xs text-gray-400 uppercase tracking-wider font-semibold">
          {{ t('payment.paymentFor', { count: selectedMemberIds.length }) }}
        </span>
        <span class="font-bold text-lg text-green-400">
          {{ formatCurrency(totalSelectedDebt) }}
        </span>
      </div>
      <button
        @click="handlePayGroup"
        class="bg-indigo-600 hover:bg-indigo-500 text-white px-5 py-2 rounded-full font-medium transition shadow-md flex items-center"
      >
        <CreditCard class="w-4 h-4 mr-2" />
        {{ t('payment.createGroupQR') }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.animate-fade-in-up {
  animation: fadeInUp 0.3s ease-out;
}

@keyframes fadeInUp {
  from {
    opacity: 0;
    transform: translate(-50%, 20px);
  }
  to {
    opacity: 1;
    transform: translate(-50%, 0);
  }
}
</style>
