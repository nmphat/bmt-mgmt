<script setup lang="ts">
import { ref, onMounted, computed, nextTick } from 'vue'
import { supabase } from '@/lib/supabase'
import type { MemberDebtSummary, GroupPaymentData } from '@/types'
import { useLangStore } from '@/stores/lang'
import PaymentQRModal from '@/components/PaymentQRModal.vue'
import HomeDebtTable from '@/components/HomeDebtTable.vue'
import { useToast } from 'vue-toastification'

const langStore = useLangStore()
const t = computed(() => langStore.t)
const toast = useToast()

const members = ref<MemberDebtSummary[]>([])
const loading = ref(true)
const errorMessage = ref('')
const searchQuery = ref('')
const showPaymentModal = ref(false)
const selectedGroupPayment = ref<GroupPaymentData | null>(null)
const debtTableKey = ref(0)
const groupPaymentCompleted = ref(false)
let paymentRefreshPromise: Promise<void> | null = null

// Pagination
const currentPage = ref(1)
const pageSize = 20
const totalCount = ref(0)
const hasMore = computed(() => currentPage.value * pageSize < totalCount.value)

async function fetchDebts() {
  try {
    loading.value = true
    errorMessage.value = ''
    const searchTerm = searchQuery.value.trim()

    // First get count while preserving the same member-name filter as the page query.
    let countQuery = supabase
      .from('view_member_debt_summary')
      .select('*', { count: 'exact', head: true })

    if (searchTerm) {
      countQuery = countQuery.ilike('display_name', `%${searchTerm}%`)
    }

    const { count, error: countError } = await countQuery

    if (countError) throw countError
    totalCount.value = count || 0

    // Get data for current page
    const from = (currentPage.value - 1) * pageSize
    const to = from + pageSize - 1

    let debtQuery = supabase
      .from('view_member_debt_summary')
      .select('*')
      .order('total_debt', { ascending: false })

    if (searchTerm) {
      debtQuery = debtQuery.ilike('display_name', `%${searchTerm}%`)
    }

    const { data, error } = await debtQuery.range(from, to)

    if (error) throw error

    if (currentPage.value === 1) {
      members.value = data || []
    } else {
      members.value = [...members.value, ...(data || [])]
    }
  } catch (error) {
    console.error('Error fetching debts:', error)
    errorMessage.value = t.value('debt.errorState')
    toast.error(t.value('debt.errorState'))
  } finally {
    loading.value = false
  }
}

async function handleSearchChange(value: string) {
  searchQuery.value = value
  currentPage.value = 1
  await fetchDebts()
}

async function loadMore() {
  currentPage.value++
  await fetchDebts()
}

async function handleSinglePay(memberId: string) {
  await createPaymentForMembers([memberId])
}

async function handleGroupPay(memberIds: string[]) {
  await createPaymentForMembers(memberIds)
}

async function createPaymentForMembers(memberIds: string[]) {
  try {
    // 1. Get all unpaid snapshot IDs for these members with details
    // We explicitly cast the response because Supabase query types can be tricky with joins
    const { data, error } = await supabase
      .from('session_costs_snapshot')
      .select(
        `
        id,
        final_amount,
        paid_amount,
        member_id,
        members (
          display_name
        )
      `,
      )
      .in('member_id', memberIds)
      .neq('status', 'paid')

    if (error) throw error

    if (!data || data.length === 0) {
      toast.info(t.value('debt.noDebt'))
      return
    }

    const snapshotIds: string[] = []
    const memberMap = new Map<string, { name: string; amount: number }>()

    // Use 'any' for row to avoid complex interaction with generated types for now
    data.forEach((row: any) => {
      snapshotIds.push(row.id)
      const amount = (row.final_amount || 0) - (row.paid_amount || 0)
      const name = row.members?.display_name || 'Unknown'

      if (memberMap.has(row.member_id)) {
        const current = memberMap.get(row.member_id)!
        current.amount += amount
      } else {
        memberMap.set(row.member_id, { name, amount })
      }
    })

    console.log('Snapshot IDs:', snapshotIds)

    // 2. Call create_group_payment RPC
    const { data: rpcResponse, error: rpcError } = await supabase.rpc('create_group_payment', {
      p_snapshot_ids: snapshotIds,
    })

    if (rpcError) throw rpcError

    console.log('Group Data (RPC):', rpcResponse)

    // 3. Construct full GroupPaymentData
    const groupData: GroupPaymentData = {
      group_code: rpcResponse.group_code,
      total_amount: rpcResponse.total_amount,
      snapshot_ids: snapshotIds,
      member_count: memberMap.size,
      members: Array.from(memberMap.values()),
    }

    selectedGroupPayment.value = groupData
    groupPaymentCompleted.value = false
    showPaymentModal.value = true
  } catch (error: any) {
    console.error('Error creating payment:', error)
    toast.error(error.message || t.value('debt.errorState'))
  }
}

function handlePaymentComplete() {
  // Refresh debt data after payment completes, but keep the sheet open so the
  // success state remains visible until the user explicitly closes it.
  currentPage.value = 1
  groupPaymentCompleted.value = true
  paymentRefreshPromise = fetchDebts().finally(() => {
    paymentRefreshPromise = null
  })
}

async function handlePaymentModalClose() {
  showPaymentModal.value = false
  await nextTick()

  const shouldClearCompletedSelection = groupPaymentCompleted.value
  if (paymentRefreshPromise) {
    await paymentRefreshPromise
  }

  selectedGroupPayment.value = null
  if (shouldClearCompletedSelection) {
    debtTableKey.value += 1
  }
  groupPaymentCompleted.value = false
}

onMounted(fetchDebts)
</script>

<template>
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <div class="flex justify-between items-center mb-6">
      <h1 class="text-2xl font-bold text-gray-900">{{ t('debt.title') }}</h1>
    </div>

    <HomeDebtTable
      :key="debtTableKey"
      :members="members"
      :loading="loading"
      :has-more="hasMore"
      :search="searchQuery"
      :error-message="errorMessage"
      @update:search="handleSearchChange"
      @pay-single="handleSinglePay"
      @pay-group="handleGroupPay"
      @load-more="loadMore"
    />

    <PaymentQRModal
      :show="showPaymentModal"
      :snapshot="null"
      :group-data="selectedGroupPayment"
      member-name=""
      @close="handlePaymentModalClose"
      @payment-complete="handlePaymentComplete"
    />
  </div>
</template>
