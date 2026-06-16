<script setup lang="ts">
import { ref, onMounted, computed, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '@/lib/supabase'
import type { MemberSessionDetail, GroupPaymentData } from '@/types'
import { useLangStore } from '@/stores/lang'
import { ArrowLeft, CreditCard, QrCode } from 'lucide-vue-next'
import PaymentQRModal from '@/components/PaymentQRModal.vue'
import { useToast } from 'vue-toastification'
import { format } from 'date-fns'
import { vi, enUS } from 'date-fns/locale'
import { mergeTimeIntervals } from '@/utils/time'

const route = useRoute()
const router = useRouter()
const langStore = useLangStore()
const t = computed(() => langStore.t)
const toast = useToast()
const dateLocale = computed(() => (langStore.currentLang === 'vi' ? vi : enUS))

const memberId = route.params.id as string
const memberName = ref('')
const totalDebt = ref(0)
const sessions = ref<MemberSessionDetail[]>([])
const loading = ref(true)
const showPaymentModal = ref(false)
const selectedSnapshot = ref<any>(null) // using any to bypass type mismatch if needed, or cast
const selectedGroupPayment = ref<GroupPaymentData | null>(null)
const sessionIntervalsMap = ref<Record<string, string>>({}) // snapshot_id -> time string
const showAllMobileSessions = ref(false)
const mobileSessionLimit = 4
const visibleMobileSessions = computed(() =>
  showAllMobileSessions.value ? sessions.value : sessions.value.slice(0, mobileSessionLimit),
)

async function fetchMemberDetails() {
  try {
    loading.value = true

    // 1. Get Member Name and Debt Summary
    const { data: memberData, error: memberError } = await supabase
      .from('view_member_debt_summary')
      .select('*')
      .eq('member_id', memberId)
    // .single() removed to avoid 406

    if (memberError) {
      // Handle case where member has no debt (might not be in view?)
      // Fallback to fetch name from members table
      const { data: profile, error: profileError } = await supabase
        .from('members')
        .select('display_name')
        .eq('id', memberId)
        .single()

      if (profileError) throw profileError
      memberName.value = profile.display_name
      totalDebt.value = 0
    } else {
      const data = memberData && memberData.length > 0 ? memberData[0] : null
      if (data) {
        memberName.value = data.display_name
        totalDebt.value = data.total_debt
      } else {
        // Fallback if array is empty
        const { data: profile, error: profileError } = await supabase
          .from('members')
          .select('display_name')
          .eq('id', memberId)
          .single()
        if (profileError) throw profileError
        memberName.value = profile.display_name
        totalDebt.value = 0
      }
    }

    // 2. Get Session History
    const { data: sessionData, error: sessionError } = await supabase
      .from('view_member_session_details')
      .select('*')
      .eq('member_id', memberId)
      .order('start_time', { ascending: false })

    if (sessionError) throw sessionError
    sessions.value = sessionData || []

    // 3. Fetch Intervals for these sessions
    await fetchIntervalsForSessions(sessions.value)
  } catch (error: any) {
    console.error('Error fetching member details:', error)
    toast.error(t.value('toast.error', { message: error.message }))
  } finally {
    loading.value = false
  }
}

async function fetchIntervalsForSessions(sessionsList: MemberSessionDetail[]) {
  if (sessionsList.length === 0) return

  // Ideally, we should have a view or RPC for this to avoid N+1 or complex joins
  // For now, let's fetch interval_presence joined with session_intervals for ALL relevant session IDs and this member
  // But wait, we need the specific intervals the USER attended in those sessions.

  const sessionIds = sessionsList.map((s) => s.session_id)

  const { data, error } = await supabase
    .from('interval_presence')
    .select('interval_id, is_present, session_intervals!inner(session_id, start_time, end_time)')
    .eq('member_id', memberId)
    .eq('is_present', true)
    .in('session_intervals.session_id', sessionIds)

  if (error) {
    console.error('Error fetching intervals:', error)
    return
  }

  // Group by session_id
  const grouped: Record<string, { start_time: string; end_time: string }[]> = {}

  interface PresenceInterval {
    interval_id: string
    is_present: boolean
    session_intervals: {
      session_id: string
      start_time: string
      end_time: string
    }
  }

  const presenceData = (data || []) as unknown as PresenceInterval[]

  presenceData.forEach((row) => {
    const sessionId = row.session_intervals.session_id
    if (!grouped[sessionId]) grouped[sessionId] = []

    grouped[sessionId].push({
      start_time: row.session_intervals.start_time,
      end_time: row.session_intervals.end_time,
    })
  })

  // Merge and map map to snapshot_id (which correlates to session_id indirectly,
  // but here we can just use session_id to lookup since we display per session)
  // Actually, sessionsList has session_id, so we can map easily.

  const map: Record<string, string> = {}
  sessionsList.forEach((s) => {
    const sessionIntervals = grouped[s.session_id]
    if (sessionIntervals && sessionIntervals.length > 0) {
      map[s.snapshot_id] = mergeTimeIntervals(sessionIntervals)
    } else {
      map[s.snapshot_id] = '-'
    }
  })

  sessionIntervalsMap.value = map
}

async function handlePayAll() {
  try {
    const unpaidSessions = sessions.value.filter((s) => s.status !== 'paid')
    if (unpaidSessions.length === 0) {
      toast.info(t.value('debt.noDebt'))
      return
    }

    const ids = unpaidSessions.map((s) => s.snapshot_id)

    const { data: groupData, error: rpcError } = await supabase.rpc('create_group_payment', {
      p_snapshot_ids: ids,
    })

    if (rpcError) throw rpcError

    selectedGroupPayment.value = {
      group_code: groupData.group_code,
      total_amount: groupData.total_amount,
      snapshot_ids: ids,
      member_count: 1,
      members: [
        {
          name: memberName.value,
          amount: unpaidSessions.reduce((sum, session) => sum + session.remaining_amount, 0),
        },
      ],
    }
    selectedSnapshot.value = null
    showPaymentModal.value = true
  } catch (error: any) {
    console.error('Error creating group payment:', error)
    toast.error(error.message)
  }
}

function handleSinglePay(session: MemberSessionDetail) {
  // Construct a snapshot-like object for the modal
  selectedSnapshot.value = {
    id: session.snapshot_id,
    payment_code: session.payment_code,
    final_amount: session.final_amount,
    paid_amount: session.paid_amount,
    member_id: memberId,
  }
  selectedGroupPayment.value = null
  showPaymentModal.value = true
}

function openSessionDetail(sessionId: string) {
  router.push(`/session/${sessionId}`)
}

async function handlePaymentModalClose() {
  showPaymentModal.value = false
  await nextTick()
  selectedSnapshot.value = null
  selectedGroupPayment.value = null
}

const formatCurrency = (value: number) => {
  return new Intl.NumberFormat(langStore.currentLang === 'vi' ? 'vi-VN' : 'en-US', {
    style: 'currency',
    currency: 'VND',
    maximumFractionDigits: 0,
  }).format(value)
}

function getStatusColor(status: string) {
  switch (status) {
    case 'paid':
      return 'bg-green-100 text-green-800'
    case 'partial':
      return 'bg-yellow-100 text-yellow-800'
    default:
      return 'bg-red-100 text-red-800'
  }
}

function getStatusLabel(status: string) {
  return t.value(`payment.${status}`)
}

function getTranslation(key: string, params: any = {}) {
  // Safe wrapper if needed, or just use t.value
  return t.value(key, params)
}

onMounted(fetchMemberDetails)
</script>

<template>
  <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <!-- Header -->
    <div class="flex items-center mb-6">
      <button
        type="button"
        @click="router.back()"
        class="mr-4 inline-flex min-h-11 min-w-11 items-center justify-center rounded-full text-gray-500 transition hover:bg-gray-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
        :aria-label="t('common.back')"
      >
        <ArrowLeft class="w-6 h-6" aria-hidden="true" />
      </button>
      <div>
        <h1 class="text-[20px] font-bold leading-[1.2] text-gray-900">{{ memberName }}</h1>
        <p class="text-sm text-gray-500">{{ t('debt.history') }}</p>
      </div>
    </div>

    <!-- Debt Summary Card -->
    <div
      class="bg-white rounded-xl shadow-sm border border-gray-200 p-6 mb-8 flex justify-between items-center"
    >
      <div>
        <span class="text-sm font-bold text-gray-500 uppercase tracking-wider">{{
          t('debt.totalDebt')
        }}</span>
        <div class="mt-1 flex items-baseline">
          <span
            class="text-[32px] font-bold leading-[1.05] text-gray-900"
            :class="{ 'text-red-600': totalDebt > 0 }"
          >
            {{ formatCurrency(totalDebt) }}
          </span>
        </div>
      </div>
      <button
        v-if="totalDebt > 0"
        type="button"
        @click="handlePayAll"
        class="flex min-h-11 items-center rounded-lg bg-indigo-600 px-4 py-2 font-bold text-white shadow transition hover:bg-indigo-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
        :aria-label="`${t('debt.payAll')}: ${memberName}`"
      >
        <CreditCard class="w-5 h-5 mr-2" aria-hidden="true" />
        {{ t('debt.payAll') }}
      </button>
    </div>

    <!-- Session History -->
    <div class="bg-white shadow-sm rounded-lg border border-gray-200 overflow-hidden">
      <div v-if="loading" class="p-8 flex justify-center">
        <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-indigo-600"></div>
      </div>
      <template v-else>
        <div class="md:hidden divide-y divide-gray-100">
          <div v-if="sessions.length === 0" class="p-6 text-center text-gray-500">
            {{ t('debt.emptyBody') }}
          </div>
          <article
            v-for="session in visibleMobileSessions"
            :key="session.snapshot_id"
            class="group cursor-pointer space-y-4 p-4 transition hover:bg-gray-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-indigo-600"
            role="link"
            tabindex="0"
            :aria-label="t('dashboard.sessionCardAria', { title: session.session_title })"
            @click="openSessionDetail(session.session_id)"
            @keydown.enter.prevent="openSessionDetail(session.session_id)"
            @keydown.space.prevent="openSessionDetail(session.session_id)"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <h2 class="text-base font-bold text-gray-900 transition group-hover:text-indigo-600">
                  {{ session.session_title }}
                </h2>
                <p class="mt-1 text-sm text-gray-500">
                  {{
                    format(new Date(session.start_time), 'dd/MM/yyyy HH:mm', { locale: dateLocale })
                  }}
                </p>
              </div>
              <span
                class="inline-flex shrink-0 rounded-full px-2 py-1 text-[14px] font-bold leading-[1.35]"
                :class="getStatusColor(session.status)"
              >
                {{ getStatusLabel(session.status) }}
              </span>
            </div>

            <dl class="grid grid-cols-2 gap-3 text-sm">
              <div>
                <dt class="font-bold text-gray-500">{{ t('session.time') }}</dt>
                <dd class="mt-1 text-gray-900">
                  {{ sessionIntervalsMap[session.snapshot_id] || '-' }}
                </dd>
              </div>
              <div>
                <dt class="font-bold text-gray-500">{{ t('debt.cost') }}</dt>
                <dd class="mt-1 text-right font-bold text-gray-900">
                  {{ formatCurrency(session.final_amount) }}
                </dd>
              </div>
              <div>
                <dt class="font-bold text-gray-500">{{ t('session.courtFee') }}</dt>
                <dd class="mt-1 text-gray-900">{{ formatCurrency(session.court_fee_amount) }}</dd>
              </div>
              <div>
                <dt class="font-bold text-gray-500">{{ t('session.shuttleFee') }}</dt>
                <dd class="mt-1 text-right text-gray-900">
                  {{ formatCurrency(session.shuttle_fee_amount) }}
                </dd>
              </div>
              <div>
                <dt class="font-bold text-gray-500">{{ t('debt.paid') }}</dt>
                <dd class="mt-1 text-gray-900">{{ formatCurrency(session.paid_amount) }}</dd>
              </div>
              <div>
                <dt class="font-bold text-gray-500">{{ t('debt.remaining') }}</dt>
                <dd
                  class="mt-1 text-right font-bold"
                  :class="session.remaining_amount > 0 ? 'text-red-600' : 'text-gray-900'"
                >
                  {{ formatCurrency(session.remaining_amount) }}
                </dd>
              </div>
            </dl>

            <div class="flex justify-end">
              <button
                v-if="session.status !== 'paid'"
                type="button"
                @click.stop="handleSinglePay(session)"
                class="inline-flex min-h-11 items-center gap-2 rounded-lg bg-indigo-600 px-4 text-sm font-bold text-white shadow-sm transition hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                :title="t('payment.scanQR')"
                :aria-label="`${t('payment.scanQR')}: ${session.session_title}`"
              >
                <QrCode class="w-5 h-5" aria-hidden="true" />
                {{ t('debt.createPaymentQR') }}
              </button>
            </div>
          </article>
          <div v-if="sessions.length > mobileSessionLimit" class="p-4">
            <button
              type="button"
              class="flex min-h-11 w-full items-center justify-center rounded-xl border border-gray-200 bg-white px-4 text-sm font-bold text-indigo-600 transition hover:bg-indigo-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
              @click="showAllMobileSessions = !showAllMobileSessions"
            >
              {{
                showAllMobileSessions
                  ? t('debt.showFewerSessions')
                  : t('debt.showMoreSessions', { count: sessions.length - mobileSessionLimit })
              }}
            </button>
          </div>
        </div>
        <div class="hidden overflow-x-auto md:block">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th
                  scope="col"
                  class="px-6 py-3 text-left text-[14px] font-bold leading-[1.35] text-gray-500 uppercase tracking-wider"
                >
                  {{ t('debt.sessionName') }}
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-right text-[14px] font-bold leading-[1.35] text-gray-500 uppercase tracking-wider"
                >
                  {{ t('debt.cost') }}
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-left text-[14px] font-bold leading-[1.35] text-gray-500 uppercase tracking-wider"
                >
                  {{ t('session.time') }}
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-right text-[14px] font-bold leading-[1.35] text-gray-500 uppercase tracking-wider"
                >
                  {{ t('session.courtFee') }}
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-right text-[14px] font-bold leading-[1.35] text-gray-500 uppercase tracking-wider"
                >
                  {{ t('session.shuttleFee') }}
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-right text-[14px] font-bold leading-[1.35] text-gray-500 uppercase tracking-wider"
                >
                  {{ t('debt.remaining') }}
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-center text-[14px] font-bold leading-[1.35] text-gray-500 uppercase tracking-wider"
                >
                  {{ t('debt.status') }}
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-center text-[14px] font-bold leading-[1.35] text-gray-500 uppercase tracking-wider"
                >
                  {{ t('debt.action') }}
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <tr
                v-for="session in sessions"
                :key="session.snapshot_id"
                class="group cursor-pointer hover:bg-gray-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-indigo-600"
                role="link"
                tabindex="0"
                :aria-label="t('dashboard.sessionCardAria', { title: session.session_title })"
                @click="openSessionDetail(session.session_id)"
                @keydown.enter.prevent="openSessionDetail(session.session_id)"
                @keydown.space.prevent="openSessionDetail(session.session_id)"
              >
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="text-sm font-bold text-gray-900 transition group-hover:text-indigo-600">
                    {{ session.session_title }}
                  </div>
                  <div class="text-[14px] leading-[1.35] text-gray-500">
                    {{
                      format(new Date(session.start_time), 'dd/MM/yyyy HH:mm', {
                        locale: dateLocale,
                      })
                    }}
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-sm text-gray-500">
                  {{ formatCurrency(session.final_amount) }}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-left text-sm text-gray-500">
                  {{ sessionIntervalsMap[session.snapshot_id] || '-' }}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-sm text-gray-500">
                  {{ formatCurrency(session.court_fee_amount) }}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-sm text-gray-500">
                  {{ formatCurrency(session.shuttle_fee_amount) }}
                </td>
                <td
                  class="px-6 py-4 whitespace-nowrap text-right text-sm font-bold"
                  :class="session.remaining_amount > 0 ? 'text-red-600' : 'text-gray-900'"
                >
                  {{ formatCurrency(session.remaining_amount) }}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-center">
                  <span
                    class="px-2 inline-flex text-[14px] leading-[1.35] font-bold rounded-full"
                    :class="getStatusColor(session.status)"
                  >
                    {{ getStatusLabel(session.status) }}
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-center text-sm font-bold">
                  <button
                    v-if="session.status !== 'paid'"
                    type="button"
                    @click.stop="handleSinglePay(session)"
                    class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-full bg-indigo-50 p-2 text-indigo-600 transition hover:bg-indigo-100 hover:text-indigo-900 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
                    :title="t('payment.scanQR')"
                    :aria-label="`${t('payment.scanQR')}: ${session.session_title}`"
                  >
                    <QrCode class="w-5 h-5" aria-hidden="true" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>
    </div>

    <PaymentQRModal
      :show="showPaymentModal"
      :snapshot="selectedSnapshot"
      :group-data="selectedGroupPayment"
      :member-name="memberName"
      @close="handlePaymentModalClose"
      @payment-complete="fetchMemberDetails"
    />
  </div>
</template>
