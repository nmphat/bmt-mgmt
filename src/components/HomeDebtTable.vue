<script setup lang="ts">
import { ref, computed } from 'vue'
import type { MemberDebtSummary } from '@/types'
import { useLangStore } from '@/stores/lang'
import { QrCode } from 'lucide-vue-next'
import { getShortName } from '@/utils/formatters'

const props = defineProps<{
  members: MemberDebtSummary[]
  loading: boolean
  hasMore: boolean
  search: string
  errorMessage?: string
}>()

const emit = defineEmits<{
  (e: 'pay-single', memberId: string): void
  (e: 'pay-group', memberIds: string[]): void
  (e: 'load-more'): void
  (e: 'update:search', value: string): void
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
  const visibleMemberIds = props.members.map((m) => m.member_id)
  const allVisibleSelected =
    visibleMemberIds.length > 0 &&
    visibleMemberIds.every((id) => selectedMemberIds.value.includes(id))

  if (allVisibleSelected) {
    selectedMemberIds.value = selectedMemberIds.value.filter((id) => !visibleMemberIds.includes(id))
  } else {
    selectedMemberIds.value = Array.from(new Set([...selectedMemberIds.value, ...visibleMemberIds]))
  }
}

const selectedMembers = computed(() =>
  props.members.filter((m) => selectedMemberIds.value.includes(m.member_id)),
)

const totalSelectedDebt = computed(() => {
  return selectedMembers.value.reduce((sum, m) => sum + m.total_debt, 0)
})

const allVisibleSelected = computed(() => {
  return (
    props.members.length > 0 &&
    props.members.every((member) => selectedMemberIds.value.includes(member.member_id))
  )
})

const handlePayGroup = () => {
  emit('pay-group', [...selectedMemberIds.value])
}
</script>

<template>
  <div :class="selectedMemberIds.length > 0 ? 'pb-[148px]' : ''">
    <div class="mb-4">
      <label for="debt-search" class="sr-only">{{ t('debt.searchPlaceholder') }}</label>
      <input
        id="debt-search"
        type="search"
        :value="search"
        :placeholder="t('debt.searchPlaceholder')"
        class="min-h-12 w-full rounded-xl border border-gray-300 bg-white px-4 text-base text-gray-900 shadow-sm outline-none transition placeholder:text-gray-400 focus:border-indigo-600 focus:ring-2 focus:ring-indigo-600/20"
        @input="emit('update:search', ($event.target as HTMLInputElement).value)"
      />
    </div>

    <div
      v-if="errorMessage"
      class="mb-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm font-medium text-red-700"
      role="alert"
    >
      {{ errorMessage }}
    </div>

    <!-- Mobile View (Card Layout) -->
    <div class="block md:hidden space-y-3">
      <template v-if="loading && members.length === 0">
        <div
          v-for="index in 3"
          :key="`debt-skeleton-${index}`"
          class="animate-pulse rounded-2xl border border-gray-200 bg-white p-4 shadow-sm"
        >
          <div class="flex items-start gap-3">
            <div class="h-6 w-6 rounded border border-gray-200 bg-gray-100"></div>
            <div class="flex-1 space-y-3">
              <div class="h-4 w-1/2 rounded bg-gray-100"></div>
              <div class="h-8 w-2/3 rounded bg-gray-100"></div>
              <div class="h-4 w-1/3 rounded bg-gray-100"></div>
            </div>
            <div class="h-11 w-20 rounded-lg bg-gray-100"></div>
          </div>
        </div>
      </template>

      <div
        v-else-if="members.length === 0"
        class="rounded-2xl border border-dashed border-gray-300 bg-white px-4 py-10 text-center"
      >
        <h2 class="text-xl font-bold text-green-700">{{ t('debt.emptyHeading') }}</h2>
        <p class="mt-2 text-base text-gray-600">{{ t('debt.emptyBody') }}</p>
      </div>

      <div
        v-for="member in members"
        :key="member.member_id"
        class="overflow-hidden rounded-2xl border bg-white shadow-sm transition"
        :class="
          selectedMemberIds.includes(member.member_id)
            ? 'border-indigo-600 bg-indigo-50/40 ring-2 ring-indigo-600/20'
            : 'border-gray-200'
        "
      >
        <div
          class="flex cursor-pointer items-start gap-3 p-4"
          role="button"
          tabindex="0"
          :aria-pressed="selectedMemberIds.includes(member.member_id)"
          @click="toggleSelection(member.member_id)"
          @keydown.enter.prevent="toggleSelection(member.member_id)"
          @keydown.space.prevent="toggleSelection(member.member_id)"
        >
          <div class="flex-shrink-0 pt-1" @click.stop>
            <input
              type="checkbox"
              :aria-label="t('debt.selectedCount', { count: 1 })"
              :checked="selectedMemberIds.includes(member.member_id)"
              @change="toggleSelection(member.member_id)"
              class="h-6 w-6 cursor-pointer rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
            />
          </div>

          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <div
                class="flex h-8 w-8 items-center justify-center rounded-full bg-indigo-100 text-sm font-bold text-indigo-600"
              >
                {{ member.display_name.charAt(0).toUpperCase() }}
              </div>
              <span class="truncate text-base font-bold text-gray-900" :title="member.display_name">
                {{ getShortName(member.display_name) }}
              </span>
            </div>

            <div class="mt-3 text-[32px] font-bold leading-none text-gray-900 tabular-nums">
              {{ formatCurrency(member.total_debt) }}
            </div>
            <div class="mt-2 text-sm font-bold text-gray-500">
              {{ t('debt.unpaidSessionCount', { count: member.unpaid_session_count }) }}
            </div>
          </div>
        </div>

        <div class="flex items-center justify-between gap-3 border-t border-gray-100 px-4 py-3">
          <router-link
            :to="`/member/${member.member_id}`"
            class="inline-flex min-h-11 items-center justify-center rounded-lg border border-indigo-100 bg-white px-4 text-sm font-bold text-indigo-600 transition hover:bg-indigo-50 focus:outline-none focus:ring-2 focus:ring-indigo-500"
          >
            {{ t('debt.details') }}
          </router-link>
          <button
            @click="emit('pay-single', member.member_id)"
            class="inline-flex min-h-11 items-center justify-center gap-2 rounded-lg bg-indigo-600 px-4 text-sm font-bold text-white shadow-sm transition hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
          >
            <QrCode class="h-4 w-4" />
            <span>{{ t('debt.createPaymentQR') }}</span>
          </button>
        </div>
      </div>
    </div>

    <div class="hidden overflow-x-auto rounded-lg border border-gray-200 bg-white shadow md:block">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th scope="col" class="px-6 py-3 text-left">
              <input
                type="checkbox"
                :checked="allVisibleSelected"
                @change="toggleAll"
                class="h-4 w-4 cursor-pointer rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
              />
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500"
            >
              {{ t('common.member') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-center text-xs font-medium uppercase tracking-wider text-gray-500"
            >
              {{ t('debt.unpaidSessions') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500"
            >
              {{ t('debt.totalDebt') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-center text-xs font-medium uppercase tracking-wider text-gray-500"
            >
              {{ t('debt.action') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-200 bg-white">
          <tr v-if="loading && members.length === 0">
            <td colspan="5" class="px-6 py-12 text-center">
              <div class="flex justify-center">
                <div class="h-8 w-8 animate-spin rounded-full border-b-2 border-indigo-600"></div>
              </div>
            </td>
          </tr>
          <tr v-else-if="members.length === 0">
            <td colspan="5" class="px-6 py-12 text-center text-gray-500">
              <div class="font-bold text-gray-900">{{ t('debt.emptyHeading') }}</div>
              <div class="mt-1">{{ t('debt.emptyBody') }}</div>
            </td>
          </tr>
          <tr v-for="member in members" :key="member.member_id" class="hover:bg-gray-50">
            <td class="whitespace-nowrap px-6 py-4">
              <input
                type="checkbox"
                :checked="selectedMemberIds.includes(member.member_id)"
                @change="toggleSelection(member.member_id)"
                class="h-4 w-4 cursor-pointer rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
              />
            </td>
            <td class="whitespace-nowrap px-6 py-4">
              <router-link :to="`/member/${member.member_id}`" class="group flex items-center">
                <div
                  class="mr-3 flex h-8 w-8 items-center justify-center rounded-full bg-indigo-100 font-bold text-indigo-600 transition group-hover:bg-indigo-200"
                >
                  {{ member.display_name.charAt(0).toUpperCase() }}
                </div>
                <span
                  class="text-sm font-medium text-gray-900 transition group-hover:text-indigo-600"
                  >{{ member.display_name }}</span
                >
              </router-link>
            </td>
            <td class="whitespace-nowrap px-6 py-4 text-center text-sm text-gray-500">
              <span
                class="inline-flex items-center rounded-full bg-red-100 px-2.5 py-0.5 text-xs font-medium text-red-800"
              >
                {{ member.unpaid_session_count }}
              </span>
            </td>
            <td class="whitespace-nowrap px-6 py-4 text-right text-sm font-bold text-red-600">
              {{ formatCurrency(member.total_debt) }}
            </td>
            <td class="whitespace-nowrap px-6 py-4 text-center text-sm font-medium">
              <button
                @click="emit('pay-single', member.member_id)"
                class="inline-flex items-center rounded-md bg-indigo-50 px-3 py-1 text-indigo-600 transition hover:bg-indigo-100 hover:text-indigo-900"
              >
                <QrCode class="mr-1 h-4 w-4" />
                {{ t('payment.qrPay') }}
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
        class="min-h-11 rounded-md border border-gray-300 bg-white px-6 py-2 text-sm font-bold text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:opacity-50"
      >
        {{ loading ? t('common.loading') : t('debt.loadMore') }}
      </button>
    </div>

    <!-- Floating Action Bar -->
    <div
      v-if="selectedMemberIds.length > 0"
      class="fixed left-4 right-4 z-50 rounded-2xl border border-indigo-100 bg-white px-4 py-3 shadow-[0_12px_36px_rgba(15,23,42,0.2)] md:left-1/2 md:right-auto md:w-auto md:-translate-x-1/2 md:rounded-full"
    >
      <div class="flex items-center justify-between gap-4">
        <div class="flex flex-col">
          <span class="text-sm font-bold text-indigo-600">
            {{ t('debt.selectedCount', { count: selectedMemberIds.length }) }}
          </span>
          <span class="text-base font-bold text-gray-900">
            {{ t('debt.selectedTotal', { amount: formatCurrency(totalSelectedDebt) }) }}
          </span>
        </div>
        <button
          @click="handlePayGroup"
          class="inline-flex min-h-11 items-center whitespace-nowrap rounded-lg bg-indigo-600 px-4 text-sm font-bold text-white shadow-md transition hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
        >
          <QrCode class="mr-2 h-4 w-4" />
          {{ t('debt.createGroupQR') }}
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.fixed.left-4.right-4 {
  bottom: calc(92px + env(safe-area-inset-bottom));
}

@media (min-width: 768px) {
  .fixed.left-4.right-4 {
    bottom: 1.5rem;
  }
}
</style>
