<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import type { MemberDebtSummary, GroupPaymentData } from '@/types'
import { useLangStore } from '@/stores/lang'
import { User, CreditCard } from 'lucide-vue-next'
import PaymentQRModal from '@/components/PaymentQRModal.vue'
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
const pageSize = 12
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

async function handlePayAll(memberId: string) {
  try {
    // 1. Get all unpaid snapshot IDs for this member
    const { data, error } = await supabase
      .from('view_member_session_details')
      .select('snapshot_id, final_amount, session_title')
      .eq('member_id', memberId)
      .neq('status', 'paid')

    if (error) throw error

    if (!data || data.length === 0) {
      toast.info(t.value('debt.noDebt'))
      return
    }

    const ids = data.map((d) => d.snapshot_id)

    // 2. Call create_group_payment RPC
    const { data: groupData, error: rpcError } = await supabase.rpc('create_group_payment', {
      p_snapshot_ids: ids,
    })

    if (rpcError) throw rpcError

    selectedGroupPayment.value = groupData
    showPaymentModal.value = true
  } catch (error: any) {
    console.error('Error creating payment:', error)
    toast.error(error.message || 'Failed to create payment')
  }
}

const formatCurrency = (value: number) => {
  return new Intl.NumberFormat(langStore.currentLang === 'vi' ? 'vi-VN' : 'en-US', {
    style: 'currency',
    currency: 'VND',
    maximumFractionDigits: 0,
  }).format(value)
}

onMounted(fetchDebts)
</script>

<template>
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <div class="flex justify-between items-center mb-6">
      <h1 class="text-2xl font-bold text-gray-900">{{ t('debt.title') }}</h1>
    </div>

    <!-- Loading State -->
    <div v-if="loading && members.length === 0" class="flex justify-center py-12">
      <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
    </div>

    <!-- Empty State -->
    <div v-else-if="members.length === 0" class="text-center py-12 bg-white rounded-lg shadow">
      <p class="text-gray-500">{{ t('debt.noDebt') }}</p>
    </div>

    <!-- Grid -->
    <div v-else class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      <div
        v-for="member in members"
        :key="member.member_id"
        class="bg-white rounded-lg shadow hover:shadow-md transition p-5 border border-gray-100 flex flex-col"
      >
        <div class="flex items-center mb-4">
          <div
            class="w-10 h-10 rounded-full bg-indigo-100 flex items-center justify-center text-indigo-600 font-bold mr-3"
          >
            {{ member.display_name.charAt(0).toUpperCase() }}
          </div>
          <div>
            <h3 class="text-lg font-semibold text-gray-900 line-clamp-1">
              {{ member.display_name }}
            </h3>
            <p class="text-sm text-gray-500">
              {{ t('debt.fromSessions', { count: member.unpaid_session_count }) }}
            </p>
          </div>
        </div>

        <div class="mb-4">
          <span class="text-xs text-gray-500 uppercase font-semibold">{{
            t('debt.totalDebt')
          }}</span>
          <p class="text-2xl font-bold text-red-600">{{ formatCurrency(member.total_debt) }}</p>
        </div>

        <div class="mt-auto grid grid-cols-2 gap-2">
          <router-link
            :to="`/member/${member.member_id}`"
            class="px-3 py-2 text-center text-sm font-medium text-gray-700 bg-gray-50 rounded-md hover:bg-gray-100 transition border border-gray-200"
          >
            {{ t('debt.viewDetails') }}
          </router-link>
          <button
            @click="handlePayAll(member.member_id)"
            class="px-3 py-2 text-center text-sm font-medium text-white bg-indigo-600 rounded-md hover:bg-indigo-700 transition flex justify-center items-center"
          >
            <CreditCard class="w-4 h-4 mr-1" />
            {{ t('payment.pay') }}
          </button>
        </div>
      </div>
    </div>

    <!-- Load More -->
    <div v-if="hasMore" class="mt-8 text-center">
      <button
        @click="loadMore"
        :disabled="loading"
        class="px-6 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50"
      >
        {{ loading ? t('common.loading') : t('common.view') + ' ' + t('common.more') }}
      </button>
    </div>

    <PaymentQRModal
      :show="showPaymentModal"
      :snapshot="null"
      :group-data="selectedGroupPayment"
      member-name=""
      @close="showPaymentModal = false"
    />
  </div>
</template>
