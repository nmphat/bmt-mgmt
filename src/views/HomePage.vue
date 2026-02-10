<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
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
const showPaymentModal = ref(false)
const selectedGroupPayment = ref<GroupPaymentData | null>(null)

// Pagination
const currentPage = ref(1)
const pageSize = 20
const totalCount = ref(0)
const hasMore = computed(() => currentPage.value * pageSize < totalCount.value)

async function fetchDebts() {
  try {
    loading.value = true

    // First get count
    const { count, error: countError } = await supabase
      .from('view_member_debt_summary')
      .select('*', { count: 'exact', head: true })

    if (countError) throw countError
    totalCount.value = count || 0

    // Get data for current page
    const from = (currentPage.value - 1) * pageSize
    const to = from + pageSize - 1

    const { data, error } = await supabase
      .from('view_member_debt_summary')
      .select('*')
      .order('total_debt', { ascending: false })
      .range(from, to)

    if (error) throw error

    if (currentPage.value === 1) {
      members.value = data || []
    } else {
      members.value = [...members.value, ...(data || [])]
    }
  } catch (error) {
    console.error('Error fetching debts:', error)
  } finally {
    loading.value = false
  }
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
      member_count: memberMap.size,
      members: Array.from(memberMap.values()),
    }

    selectedGroupPayment.value = groupData
    showPaymentModal.value = true
  } catch (error: any) {
    console.error('Error creating payment:', error)
    toast.error(error.message || 'Failed to create payment')
  }
}

onMounted(fetchDebts)
</script>

<template>
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <div class="flex justify-between items-center mb-6">
      <h1 class="text-2xl font-bold text-gray-900">{{ t('debt.title') }}</h1>
    </div>

    <HomeDebtTable
      :members="members"
      :loading="loading"
      :has-more="hasMore"
      @pay-single="handleSinglePay"
      @pay-group="handleGroupPay"
      @load-more="loadMore"
    />

    <PaymentQRModal
      :show="showPaymentModal"
      :snapshot="null"
      :group-data="selectedGroupPayment"
      member-name=""
      @close="showPaymentModal = false"
    />
  </div>
</template>
