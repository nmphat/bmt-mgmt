<script setup lang="ts">
import { ref, computed } from 'vue'
import type { MemberDebtSummary } from '@/types'
import { useLangStore } from '@/stores/lang'
import { QrCode } from 'lucide-vue-next'
import Alert from '@/components/ui/Alert.vue'
import Avatar from '@/components/ui/Avatar.vue'
import Button from '@/components/ui/Button.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import CountPill from '@/components/ui/CountPill.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import Input from '@/components/ui/Input.vue'
import Spinner from '@/components/ui/Spinner.vue'
import TableHeaderCell from '@/components/ui/TableHeaderCell.vue'

const props = defineProps<{
  members: MemberDebtSummary[]
  loading: boolean
  hasMore: boolean
  search: string
  errorMessage?: string
  isAdmin?: boolean
}>()

const emit = defineEmits<{
  (e: 'pay-single', memberId: string): void
  (e: 'pay-group', memberIds: string[]): void
  (e: 'pay-cash', memberId: string): void
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
      <Input
        id="debt-search"
        type="search"
        size="Large"
        :model-value="search"
        :placeholder="t('debt.searchPlaceholder')"
        class="w-full"
        @update:model-value="emit('update:search', $event as string)"
      />
    </div>

    <Alert v-if="errorMessage" tone="Danger" size="Default" variant="Box" class="mb-4">
      {{ errorMessage }}
    </Alert>

    <!-- Mobile View (Card Layout) -->
    <div class="block md:hidden space-y-3">
      <template v-if="loading && members.length === 0">
        <div
          v-for="index in 3"
          :key="`debt-skeleton-${index}`"
          data-ds="Debt Card Skeleton"
          data-ds-style="Default"
          class="flex animate-pulse items-start gap-3 rounded-xl border border-line-divider bg-surface-card p-4 shadow-sm"
        >
          <div
            data-ds="Skeleton Block"
            data-ds-shape="Checkbox"
            class="size-6 shrink-0 rounded-sm border border-line-divider bg-surface-muted"
          ></div>
          <div class="flex flex-1 flex-col gap-3">
            <div
              data-ds="Skeleton Block"
              data-ds-shape="Line S"
              class="h-4 w-1/2 rounded-sm bg-surface-muted"
            ></div>
            <div
              data-ds="Skeleton Block"
              data-ds-shape="Line L"
              class="h-8 w-2/3 rounded-sm bg-surface-muted"
            ></div>
            <div
              data-ds="Skeleton Block"
              data-ds-shape="Line S"
              class="h-4 w-1/3 rounded-sm bg-surface-muted"
            ></div>
          </div>
          <div
            data-ds="Skeleton Block"
            data-ds-shape="Button"
            class="h-11 w-20 shrink-0 rounded-xl bg-surface-muted"
          ></div>
        </div>
      </template>

      <EmptyState
        v-else-if="members.length === 0"
        variant="Dashed"
        align="Center"
        :heading="t('debt.emptyHeading')"
      >
        {{ t('debt.emptyBody') }}
      </EmptyState>

      <div
        v-for="member in members"
        :key="member.member_id"
        data-ds="Debt Card"
        :data-ds-selected="String(selectedMemberIds.includes(member.member_id))"
        class="overflow-hidden rounded-xl border shadow-sm transition"
        :class="
          selectedMemberIds.includes(member.member_id)
            ? 'border-line-brand bg-surface-brand-subtle'
            : 'border-line-divider bg-surface-card'
        "
      >
        <div
          class="flex cursor-pointer items-start gap-3 p-4 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-line-focus"
          role="button"
          tabindex="0"
          :aria-pressed="selectedMemberIds.includes(member.member_id)"
          @click="toggleSelection(member.member_id)"
          @keydown.enter.prevent="toggleSelection(member.member_id)"
          @keydown.space.prevent="toggleSelection(member.member_id)"
        >
          <div class="flex-shrink-0 pt-1" @click.stop>
            <Checkbox
              size="24"
              :aria-label="t('debt.selectedCount', { count: 1 })"
              :model-value="selectedMemberIds.includes(member.member_id)"
              @update:model-value="toggleSelection(member.member_id)"
            />
          </div>

          <div class="flex min-w-0 flex-1 flex-col gap-3">
            <div class="flex items-center gap-2">
              <Avatar size="32" :initial="member.display_name.charAt(0).toUpperCase()" />
              <span
                class="min-w-0 flex-1 break-words text-base font-bold leading-snug text-fg-primary"
                :title="member.display_name"
              >
                {{ member.display_name }}
              </span>
            </div>

            <div class="text-3xl font-bold text-fg-primary tabular-nums">
              {{ formatCurrency(member.total_debt) }}
            </div>
            <div class="text-sm font-bold text-fg-muted">
              {{ t('debt.unpaidSessionCount', { count: member.unpaid_session_count }) }}
            </div>
          </div>
        </div>

        <div class="grid grid-cols-3 gap-2 border-t border-line-divider px-4 py-3">
          <Button
            as="RouterLink"
            :to="`/member/${member.member_id}`"
            size="Default"
            variant="Outline Brand"
            class="whitespace-nowrap"
          >
            {{ t('debt.details') }}
          </Button>
          <Button
            size="Default"
            variant="Primary"
            :leading-icon="QrCode"
            class="whitespace-nowrap"
            @click="emit('pay-single', member.member_id)"
          >
            <span>{{ t('debt.createPaymentQR') }}</span>
          </Button>
          <Button
            v-if="isAdmin"
            size="Default"
            variant="Outline Success"
            class="whitespace-nowrap"
            @click="emit('pay-cash', member.member_id)"
          >
            <span>{{ t('payment.cashPay') }}</span>
          </Button>
        </div>
      </div>
    </div>

    <div
      class="hidden overflow-x-auto rounded-lg border border-line-divider bg-surface-card shadow-sm md:block"
    >
      <table class="min-w-full">
        <thead>
          <tr class="border-b border-line-divider">
            <TableHeaderCell content="Checkbox" align="Left">
              <Checkbox size="16" :model-value="allVisibleSelected" @change="toggleAll" />
            </TableHeaderCell>
            <TableHeaderCell align="Left">{{ t('common.member') }}</TableHeaderCell>
            <TableHeaderCell align="Center">{{ t('debt.unpaidSessions') }}</TableHeaderCell>
            <TableHeaderCell align="Right">{{ t('debt.totalDebt') }}</TableHeaderCell>
            <TableHeaderCell align="Center">{{ t('debt.action') }}</TableHeaderCell>
          </tr>
        </thead>
        <tbody>
          <tr
            v-if="loading && members.length === 0"
            data-ds="Debt Table Row"
            data-ds-kind="Loading"
            data-ds-selected="false"
            class="border-b border-line-divider last:border-b-0"
          >
            <td colspan="5" class="px-6 py-12 text-center">
              <div class="flex justify-center">
                <Spinner size="32" />
              </div>
            </td>
          </tr>
          <tr
            v-else-if="members.length === 0"
            data-ds="Debt Table Row"
            data-ds-kind="Empty"
            data-ds-selected="false"
            class="border-b border-line-divider last:border-b-0"
          >
            <td colspan="5" class="px-6 py-4">
              <EmptyState variant="Plain" align="Center" :heading="t('debt.emptyHeading')">
                {{ t('debt.emptyBody') }}
              </EmptyState>
            </td>
          </tr>
          <tr
            v-for="member in members"
            :key="member.member_id"
            data-ds="Debt Table Row"
            data-ds-kind="Data"
            :data-ds-selected="String(selectedMemberIds.includes(member.member_id))"
            class="border-b border-line-divider last:border-b-0 hover:bg-surface-subtle"
          >
            <td class="whitespace-nowrap px-6 py-4 text-base">
              <Checkbox
                size="16"
                :model-value="selectedMemberIds.includes(member.member_id)"
                @update:model-value="toggleSelection(member.member_id)"
              />
            </td>
            <td class="whitespace-nowrap px-6 py-4 text-base">
              <router-link
                :to="`/member/${member.member_id}`"
                class="group flex items-center gap-3 rounded-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-line-focus focus-visible:ring-offset-2"
              >
                <Avatar size="32" :initial="member.display_name.charAt(0).toUpperCase()" />
                <span class="font-medium text-fg-primary transition group-hover:text-fg-brand">{{
                  member.display_name
                }}</span>
              </router-link>
            </td>
            <td class="whitespace-nowrap px-6 py-4 text-center text-base">
              <CountPill>{{ member.unpaid_session_count }}</CountPill>
            </td>
            <td class="whitespace-nowrap px-6 py-4 text-right text-base font-bold text-fg-danger">
              {{ formatCurrency(member.total_debt) }}
            </td>
            <td class="whitespace-nowrap px-6 py-4 text-base">
              <div class="flex items-center justify-center gap-2">
                <Button
                  size="Small"
                  variant="Outline Brand"
                  :leading-icon="QrCode"
                  @click="emit('pay-single', member.member_id)"
                >
                  {{ t('payment.qrPay') }}
                </Button>
                <Button
                  v-if="isAdmin"
                  size="Small"
                  variant="Outline Success"
                  @click="emit('pay-cash', member.member_id)"
                >
                  {{ t('payment.cashPay') }}
                </Button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Load More -->
    <div v-if="hasMore" class="mt-4 text-center">
      <Button size="Default" variant="Secondary" :disabled="loading" @click="emit('load-more')">
        {{ loading ? t('common.loading') : t('debt.loadMore') }}
      </Button>
    </div>

    <!-- Floating Action Bar -->
    <div
      v-if="selectedMemberIds.length > 0"
      data-ds="Floating Selection Bar"
      data-ds-style="Light"
      class="fixed left-4 right-4 z-50 rounded-xl border border-line-brand-muted bg-surface-card px-4 py-3 shadow-xl md:left-1/2 md:right-auto md:w-auto md:-translate-x-1/2 md:rounded-full"
    >
      <div class="flex items-center justify-between gap-4">
        <div class="flex flex-col">
          <span class="text-sm font-bold text-fg-brand">
            {{ t('debt.selectedCount', { count: selectedMemberIds.length }) }}
          </span>
          <span class="text-base font-bold text-fg-primary">
            {{ t('debt.selectedTotal', { amount: formatCurrency(totalSelectedDebt) }) }}
          </span>
        </div>
        <Button
          size="Default"
          variant="Primary"
          :leading-icon="QrCode"
          class="whitespace-nowrap"
          @click="handlePayGroup"
        >
          {{ t('debt.createGroupQR') }}
        </Button>
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
