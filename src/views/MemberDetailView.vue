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
import Button from '@/components/ui/Button.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import IconButton from '@/components/ui/IconButton.vue'
import PageHeader from '@/components/ui/PageHeader.vue'
import PaymentStatusBadge from '@/components/ui/PaymentStatusBadge.vue'
import Spinner from '@/components/ui/Spinner.vue'
import TableHeaderCell from '@/components/ui/TableHeaderCell.vue'

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

function getTranslation(key: string, params: any = {}) {
  // Safe wrapper if needed, or just use t.value
  return t.value(key, params)
}

onMounted(fetchMemberDetails)
</script>

<template>
  <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <!-- Header -->
    <PageHeader layout="Back Title" :title="memberName" :subtitle="t('debt.history')" class="mb-6">
      <template #leading>
        <IconButton
          :icon="ArrowLeft"
          :label="t('common.back')"
          size="Default"
          shape="Round"
          variant="Ghost"
          @click="router.back()"
        />
      </template>
    </PageHeader>

    <!-- Debt Summary Card -->
    <div
      class="mb-8 flex flex-col gap-4 rounded-xl border border-line-divider bg-surface-card p-6 shadow-sm sm:flex-row sm:items-center sm:justify-between"
    >
      <div class="flex flex-col gap-1">
        <span class="text-sm font-bold text-fg-muted uppercase tracking-wider">{{
          t('debt.totalDebt')
        }}</span>
        <div class="flex items-baseline">
          <span
            class="text-3xl font-bold"
            :class="totalDebt > 0 ? 'text-fg-danger' : 'text-fg-primary'"
          >
            {{ formatCurrency(totalDebt) }}
          </span>
        </div>
      </div>
      <Button
        v-if="totalDebt > 0"
        size="Default"
        variant="Primary"
        :leading-icon="CreditCard"
        :aria-label="`${t('debt.payAll')}: ${memberName}`"
        @click="handlePayAll"
      >
        {{ t('debt.payAll') }}
      </Button>
    </div>

    <!-- Session History -->
    <div class="bg-surface-card shadow-sm rounded-xl border border-line-divider overflow-hidden">
      <div v-if="loading" class="p-8 flex justify-center">
        <Spinner size="32" />
      </div>
      <template v-else>
        <div class="md:hidden">
          <EmptyState v-if="sessions.length === 0" variant="Plain" align="Center">
            {{ t('debt.emptyBody') }}
          </EmptyState>
          <article
            v-for="session in visibleMobileSessions"
            :key="session.snapshot_id"
            class="group flex cursor-pointer flex-col gap-4 border-b border-line-subtle p-4 last:border-b-0 transition hover:bg-surface-subtle focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-line-focus"
            role="link"
            tabindex="0"
            :aria-label="t('dashboard.sessionCardAria', { title: session.session_title })"
            @click="openSessionDetail(session.session_id)"
            @keydown.enter.prevent="openSessionDetail(session.session_id)"
            @keydown.space.prevent="openSessionDetail(session.session_id)"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <h2
                  class="text-base font-bold text-fg-primary transition group-hover:text-fg-brand"
                >
                  {{ session.session_title }}
                </h2>
                <p class="mt-1 text-sm text-fg-muted">
                  {{
                    format(new Date(session.start_time), 'dd/MM/yyyy HH:mm', { locale: dateLocale })
                  }}
                </p>
              </div>
              <PaymentStatusBadge
                :status="
                  session.status === 'paid'
                    ? 'Paid'
                    : session.status === 'partial'
                      ? 'Partial'
                      : 'Pending'
                "
              />
            </div>

            <dl class="grid grid-cols-2 gap-3 text-sm">
              <div>
                <dt class="font-bold text-fg-muted">{{ t('session.time') }}</dt>
                <dd class="mt-1 text-fg-primary">
                  {{ sessionIntervalsMap[session.snapshot_id] || '-' }}
                </dd>
              </div>
              <div>
                <dt class="font-bold text-fg-muted">{{ t('debt.cost') }}</dt>
                <dd class="mt-1 text-right font-bold text-fg-primary">
                  {{ formatCurrency(session.final_amount) }}
                </dd>
              </div>
              <div>
                <dt class="font-bold text-fg-muted">{{ t('session.courtFee') }}</dt>
                <dd class="mt-1 text-fg-primary">{{ formatCurrency(session.court_fee_amount) }}</dd>
              </div>
              <div>
                <dt class="font-bold text-fg-muted">{{ t('session.shuttleFee') }}</dt>
                <dd class="mt-1 text-right text-fg-primary">
                  {{ formatCurrency(session.shuttle_fee_amount) }}
                </dd>
              </div>
              <div>
                <dt class="font-bold text-fg-muted">{{ t('debt.paid') }}</dt>
                <dd class="mt-1 text-fg-primary">{{ formatCurrency(session.paid_amount) }}</dd>
              </div>
              <div>
                <dt class="font-bold text-fg-muted">{{ t('debt.remaining') }}</dt>
                <dd
                  class="mt-1 text-right font-bold"
                  :class="session.remaining_amount > 0 ? 'text-fg-danger' : 'text-fg-primary'"
                >
                  {{ formatCurrency(session.remaining_amount) }}
                </dd>
              </div>
            </dl>

            <div class="flex justify-end">
              <Button
                v-if="session.status !== 'paid'"
                size="Default"
                variant="Primary"
                :leading-icon="QrCode"
                :title="t('payment.scanQR')"
                :aria-label="`${t('payment.scanQR')}: ${session.session_title}`"
                @click.stop="handleSinglePay(session)"
              >
                {{ t('debt.createPaymentQR') }}
              </Button>
            </div>
          </article>
          <div v-if="sessions.length > mobileSessionLimit" class="p-4">
            <Button
              size="Default"
              variant="Outline Brand"
              class="w-full"
              @click="showAllMobileSessions = !showAllMobileSessions"
            >
              {{
                showAllMobileSessions
                  ? t('debt.showFewerSessions')
                  : t('debt.showMoreSessions', { count: sessions.length - mobileSessionLimit })
              }}
            </Button>
          </div>
        </div>
        <div class="hidden overflow-x-auto md:block">
          <table class="min-w-full">
            <thead>
              <tr>
                <TableHeaderCell>{{ t('debt.sessionName') }}</TableHeaderCell>
                <TableHeaderCell align="Right">{{ t('debt.cost') }}</TableHeaderCell>
                <TableHeaderCell>{{ t('session.time') }}</TableHeaderCell>
                <TableHeaderCell align="Right">{{ t('session.courtFee') }}</TableHeaderCell>
                <TableHeaderCell align="Right">{{ t('session.shuttleFee') }}</TableHeaderCell>
                <TableHeaderCell align="Right">{{ t('debt.remaining') }}</TableHeaderCell>
                <TableHeaderCell align="Center">{{ t('debt.status') }}</TableHeaderCell>
                <TableHeaderCell align="Center">{{ t('debt.action') }}</TableHeaderCell>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="session in sessions"
                :key="session.snapshot_id"
                class="group cursor-pointer border-b border-line-divider last:border-b-0 hover:bg-surface-subtle focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-line-focus"
                role="link"
                tabindex="0"
                :aria-label="t('dashboard.sessionCardAria', { title: session.session_title })"
                @click="openSessionDetail(session.session_id)"
                @keydown.enter.prevent="openSessionDetail(session.session_id)"
                @keydown.space.prevent="openSessionDetail(session.session_id)"
              >
                <td class="px-6 py-4 whitespace-nowrap text-base">
                  <div class="font-bold text-fg-primary transition group-hover:text-fg-brand">
                    {{ session.session_title }}
                  </div>
                  <div class="text-sm text-fg-muted">
                    {{
                      format(new Date(session.start_time), 'dd/MM/yyyy HH:mm', {
                        locale: dateLocale,
                      })
                    }}
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-base text-fg-muted">
                  {{ formatCurrency(session.final_amount) }}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-left text-base text-fg-muted">
                  {{ sessionIntervalsMap[session.snapshot_id] || '-' }}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-base text-fg-muted">
                  {{ formatCurrency(session.court_fee_amount) }}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-base text-fg-muted">
                  {{ formatCurrency(session.shuttle_fee_amount) }}
                </td>
                <td
                  class="px-6 py-4 whitespace-nowrap text-right text-base font-bold"
                  :class="session.remaining_amount > 0 ? 'text-fg-danger' : 'text-fg-primary'"
                >
                  {{ formatCurrency(session.remaining_amount) }}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-center">
                  <PaymentStatusBadge
                    :status="
                      session.status === 'paid'
                        ? 'Paid'
                        : session.status === 'partial'
                          ? 'Partial'
                          : 'Pending'
                    "
                  />
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-center">
                  <IconButton
                    v-if="session.status !== 'paid'"
                    :icon="QrCode"
                    :label="`${t('payment.scanQR')}: ${session.session_title}`"
                    :title="t('payment.scanQR')"
                    size="Default"
                    shape="Round"
                    variant="Outline"
                    @click.stop="handleSinglePay(session)"
                  />
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
