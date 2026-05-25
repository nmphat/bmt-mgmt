<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '@/lib/supabase'
import type {
  SessionSummary,
  Interval,
  SessionRegistration,
  MemberCost,
  Member,
  GroupPaymentData,
} from '@/types'
import { format } from 'date-fns'
import { vi, enUS } from 'date-fns/locale'
import { useLangStore } from '@/stores/lang'
import {
  ChevronLeft,
  RefreshCcw,
  UserX,
  UserPlus,
  Trash2,
  Loader2,
  X,
  Edit,
  Save,
  Lock,
  CreditCard,
  QrCode,
  Check,
} from 'lucide-vue-next'
import PaymentQRModal from '@/components/PaymentQRModal.vue'
import ManualPaymentModal from '@/components/ManualPaymentModal.vue'
import { useAuthStore } from '@/stores/auth'
import type { RealtimeChannel } from '@supabase/supabase-js'
import { useToast } from 'vue-toastification'
import type { CostSnapshot } from '@/types'
import { BANK_INFO } from '@/types'

const route = useRoute()
const authStore = useAuthStore()
const langStore = useLangStore()
const toast = useToast()
const t = computed(() => langStore.t)
const dateLocale = computed(() => (langStore.currentLang === 'vi' ? vi : enUS))
const sessionId = route.params.id as string

const session = ref<SessionSummary | null>(null)
const intervals = ref<Interval[]>([])
const registrations = ref<SessionRegistration[]>([])
const allMembers = ref<Member[]>([])
const selectedMemberIds = ref<string[]>([])
const isRegistering = ref(false)
const showMemberDropdown = ref(false)
const dropdownRef = ref<HTMLElement | null>(null)
const presence = ref<Record<string, Record<string, boolean>>>({}) // memberId -> intervalId -> isPresent
const costs = ref<MemberCost[]>([])
const getBreakdown = (memberId: string) => {
  return costs.value.find((c) => c.member_id === memberId)
}
const snapshots = ref<(CostSnapshot & { display_name: string })[]>([])
const loading = ref(true)
const finalizeLoading = ref(false)
const showQRModal = ref(false)
const showCashModal = ref(false)
const selectedMemberId = ref<string | null>(null)
const selectedSnapshot = computed(() => {
  if (!selectedMemberId.value) return null
  return snapshots.value.find((s) => s.member_id === selectedMemberId.value) || null
})
const isPaymentSuccess = computed(() => {
  if (groupPaymentData.value) {
    // Check if all selected members in the group are paid
    const selectedSnapshots = snapshots.value.filter((s) =>
      selectedSnapshotIds.value.includes(s.id),
    )
    return selectedSnapshots.length > 0 && selectedSnapshots.every((s) => s.status === 'paid')
  }
  return selectedSnapshot.value?.status === 'paid'
})
const selectedSnapshotMemberName = ref('')
const isEditingSession = ref(false)
const isSavingSession = ref(false)
const selectedSnapshotIds = ref<string[]>([])
const groupPaymentData = ref<GroupPaymentData | null>(null)
const isCreatingGroupPayment = ref(false)
const isFetching = ref(false)
const pendingRefresh = ref<null | 'full' | 'costs'>(null)
const activeSection = ref('overview-section')
const lastStatusForActiveSection = ref<string | null>(null)

type SessionSectionId = 'overview-section' | 'attendance-section' | 'costs-section' | 'payments-section'

const getDefaultActiveSection = (status?: string): SessionSectionId => {
  if (status === 'open') return 'attendance-section'
  if (status === 'waiting_for_payment' || status === 'done') return 'payments-section'
  return 'overview-section'
}

const sectionTabs = computed<{ id: SessionSectionId; label: string; ariaLabel: string }[]>(() => [
  { id: 'overview-section', label: t.value('session.overview'), ariaLabel: t.value('session.overview') },
  { id: 'attendance-section', label: t.value('session.attendance'), ariaLabel: t.value('session.attendance') },
  { id: 'costs-section', label: t.value('session.costs'), ariaLabel: t.value('session.costs') },
  { id: 'payments-section', label: t.value('session.payments'), ariaLabel: t.value('session.payments') },
])

function scrollToSection(sectionId: SessionSectionId) {
  activeSection.value = sectionId
  document.getElementById(sectionId)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}

// Cache formatters for performance
const currencyFormatters: { [key: string]: Intl.NumberFormat } = {
  vi: new Intl.NumberFormat('vi-VN', {
    style: 'currency',
    currency: 'VND',
    maximumFractionDigits: 0,
  }),
  en: new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'VND',
    maximumFractionDigits: 0,
  }),
}

const sessionForm = ref({
  title: '',
  status: 'open' as 'open' | 'waiting_for_payment' | 'done' | 'cancelled',
  court_fee_total: 0,
  shuttle_fee_total: 0,
})
let realtimeChannel: RealtimeChannel | null = null
let pollTimer: any = null

const availableMembers = computed(() => {
  const registeredIds = new Set(registrations.value.map((r) => r.member_id))
  return allMembers.value
    .filter((m) => !registeredIds.has(m.id) && m.is_active)
    .sort((a, b) => a.display_name.localeCompare(b.display_name, 'vi'))
})

const isSessionEditable = computed(() => authStore.isAdmin && session.value?.status === 'open')
const isReadOnlyViewer = computed(() => !authStore.isAdmin)
const isSessionFinalized = computed(
  () => session.value?.status === 'waiting_for_payment' || session.value?.status === 'done',
)
const isSessionCancelled = computed(() => session.value?.status === 'cancelled')
const attendanceLockMessage = computed(() => {
  if (isSessionCancelled.value) return t.value('session.cancelledSessionHint')
  if (isSessionFinalized.value) return t.value('session.lockedSessionHint')
  if (!authStore.isAuthenticated) return t.value('session.readOnlyHint')
  if (isReadOnlyViewer.value) return t.value('session.adminOnlyHint')
  return ''
})

const handleClickOutside = (event: MouseEvent) => {
  if (dropdownRef.value && !dropdownRef.value.contains(event.target as Node)) {
    showMemberDropdown.value = false
  }
}

async function fetchData(refreshCostsOnly = false) {
  if (isFetching.value) {
    if (!refreshCostsOnly) {
      pendingRefresh.value = 'full'
    } else if (!pendingRefresh.value) {
      pendingRefresh.value = 'costs'
    }
    return
  }
  try {
    isFetching.value = true
    if (!refreshCostsOnly) loading.value = true

    // Fetch session summary (Always fetch this now to detect status changes)
    const { data: sessionData, error: sessionError } = await supabase
      .from('view_session_summary')
      .select('*')
      .eq('id', sessionId)
      .single()

    if (sessionError) throw sessionError
    session.value = sessionData

    if (sessionData && lastStatusForActiveSection.value !== sessionData.status) {
      activeSection.value = getDefaultActiveSection(sessionData.status)
      lastStatusForActiveSection.value = sessionData.status
    }

    if (sessionData) {
      sessionForm.value = {
        title: sessionData.title,
        status: sessionData.status,
        court_fee_total: sessionData.court_fee_total,
        shuttle_fee_total: sessionData.shuttle_fee_total,
      }
    }

    if (!refreshCostsOnly) {
      // Fetch intervals
      const { data: intervalsData } = await supabase
        .from('session_intervals')
        .select('*')
        .eq('session_id', sessionId)
        .order('idx', { ascending: true })
      intervals.value = intervalsData || []

      // Fetch all members for registration dropdown
      const { data: membersData } = await supabase
        .from('members')
        .select('*')
        .order('display_name', { ascending: true })
      allMembers.value = membersData || []
    }

    // Fetch registrations (with member details)
    const { data: regsData } = await supabase
      .from('session_registrations')
      .select('*, member:members(*)')
      .eq('session_id', sessionId)

    const sortedRegs = (regsData || []) as SessionRegistration[]
    sortedRegs.sort((a, b) =>
      (a.member?.display_name || '').localeCompare(b.member?.display_name || '', 'vi'),
    )
    registrations.value = sortedRegs

    // Fetch presence
    const { data: presenceData } = await supabase
      .from('interval_presence')
      .select('*')
      .in(
        'interval_id',
        intervals.value.map((i) => i.id),
      )

    // Initialize presence matrix
    const matrix: Record<string, Record<string, boolean>> = {}
    for (const reg of registrations.value) {
      const memberMatrix: Record<string, boolean> = {}
      for (const interval of intervals.value) {
        memberMatrix[interval.id] = false
      }
      matrix[reg.member_id] = memberMatrix
    }

    if (presenceData) {
      for (const p of presenceData) {
        const memberMatrix = matrix[p.member_id]
        if (memberMatrix) {
          memberMatrix[p.interval_id] = p.is_present
        }
      }
    }
    presence.value = matrix

    if (session.value?.status === 'waiting_for_payment' || session.value?.status === 'done') {
      await fetchSnapshotData()
    }
    // Always fetch costs for breakdown/reference
    await fetchCosts()
  } catch (error) {
    console.error('Error fetching session details:', error)
  } finally {
    isFetching.value = false
    loading.value = false
    const queuedRefresh = pendingRefresh.value
    pendingRefresh.value = null
    if (queuedRefresh) {
      await fetchData(queuedRefresh === 'costs')
    }
  }
}

async function fetchSnapshotData() {
  const { data, error } = await supabase
    .from('session_costs_snapshot')
    .select('*, member:members(display_name)')
    .eq('session_id', sessionId)

  if (error) {
    console.error('Error fetching snapshots:', error)
    return
  }

  const sortedSnapshots = (data || []).map((s: any) => ({
    ...s,
    display_name: s.member?.display_name || t.value('common.unknown'), // Need to add 'unknown' to messages.ts
  })) as (CostSnapshot & { display_name: string })[]

  sortedSnapshots.sort((a, b) => a.display_name.localeCompare(b.display_name, 'vi'))
  snapshots.value = sortedSnapshots
}

async function finalizeSession() {
  if (!isSessionEditable.value) return
  if (!session.value) return
  if (!confirm(t.value('session.finalizeConfirm'))) return

  try {
    finalizeLoading.value = true
    const { error } = await supabase.rpc('finalize_session', { p_session_id: sessionId })

    if (error) throw error

    toast.success(t.value('toast.sessionFinalized'))
    await fetchData()
  } catch (error: any) {
    console.error('Error finalizing session:', error)
    toast.error(error.message || t.value('session.finalizeError'))
  } finally {
    finalizeLoading.value = false
  }
}

// Preserve existing sessions.update mutations for edit/cancel flows.
async function cancelSession() {
  if (!isSessionEditable.value) return
  if (!session.value) return
  if (!confirm(t.value('session.cancelConfirm'))) return

  try {
    const { error } = await supabase
      .from('sessions')
      .update({ status: 'cancelled' })
      .eq('id', sessionId)

    if (error) throw error
    toast.success(t.value('toast.sessionCancelled'))
    await fetchData()
  } catch (error: any) {
    console.error('Error cancelling session:', error)
    toast.error(error.message || t.value('session.cancelError'))
  }
}

function openPaymentQR(snapshot: CostSnapshot, name: string) {
  selectedMemberId.value = snapshot.member_id
  selectedSnapshotMemberName.value = name
  showQRModal.value = true
}

function openCashPayment(snapshot: CostSnapshot, name: string) {
  if (!authStore.isAdmin) return
  selectedMemberId.value = snapshot.member_id
  selectedSnapshotMemberName.value = name
  showCashModal.value = true
}

async function saveSession() {
  if (!isSessionEditable.value) return

  try {
    isSavingSession.value = true
    const { error } = await supabase
      .from('sessions')
      .update({
        title: sessionForm.value.title,
        status: sessionForm.value.status,
        court_fee_total: sessionForm.value.court_fee_total,
        shuttle_fee_total: sessionForm.value.shuttle_fee_total,
        updated_at: new Date().toISOString(),
      })
      .eq('id', sessionId)

    if (error) throw error

    toast.success(t.value('toast.sessionUpdated'))
    isEditingSession.value = false
    await fetchData()
  } catch (error: any) {
    console.error('Error updating session:', error)
    toast.error(error.message || t.value('session.updateError'))
  } finally {
    isSavingSession.value = false
  }
}

async function registerMembers() {
  if (!isSessionEditable.value) return
  if (selectedMemberIds.value.length === 0) return

  try {
    isRegistering.value = true

    // Call RPC for each selected member
    const promises = selectedMemberIds.value.map((memberId) =>
      supabase.rpc('add_member_to_session_full_presence', {
        p_session_id: sessionId,
        p_member_id: memberId,
      }),
    )

    const results = await Promise.all(promises)
    const errors = results.filter((r) => r.error).map((r) => r.error)

    if (errors.length > 0) {
      console.error('Some registrations failed:', errors)
      toast.error(t.value('toast.registrationPartialFailure'))
    } else {
      toast.success(t.value('toast.memberRegistered', { count: selectedMemberIds.value.length }))
    }

    selectedMemberIds.value = []
    showMemberDropdown.value = false
    await fetchData(true)
  } catch (error: any) {
    toast.error(
      error.message || t.value('toast.error', { message: t.value('session.registerError') }),
    )
  } finally {
    isRegistering.value = false
  }
}

async function removeRegistration(regId: string, name: string) {
  if (!isSessionEditable.value) return
  if (!confirm(t.value('session.removeConfirm', { name }))) return

  try {
    const { error } = await supabase.from('session_registrations').delete().eq('id', regId)

    if (error) throw error

    toast.success(t.value('toast.registrationRemoved'))
    await fetchData(true)
  } catch (error: any) {
    toast.error(error.message || t.value('session.removeError'))
  }
}

async function fetchCosts() {
  const { data, error } = await supabase.rpc('calculate_session_costs', { p_session_id: sessionId })
  if (!error && data) {
    const sortedCosts = [...data] as MemberCost[]
    sortedCosts.sort((a, b) => a.display_name.localeCompare(b.display_name, 'vi'))
    costs.value = sortedCosts
  }
}

async function togglePresence(memberId: string, intervalId: string) {
  if (!isSessionEditable.value) return

  const registration = registrations.value.find((r) => r.member_id === memberId)
  if (registration?.is_registered_not_attended === true) return

  const currentMemberPresence = presence.value[memberId]
  if (!currentMemberPresence) return

  const newValue = !currentMemberPresence[intervalId]

  // Optimistic update
  if (presence.value[memberId]) {
    presence.value[memberId][intervalId] = newValue
  }

  const { error } = await supabase.from('interval_presence').upsert(
    {
      interval_id: intervalId,
      member_id: memberId,
      is_present: newValue,
    },
    { onConflict: 'interval_id, member_id' },
  )

  if (error) {
    // Revert on error
    if (presence.value[memberId]) {
      presence.value[memberId][intervalId] = !newValue
    }
    console.error('Error toggling presence:', error)
  } else {
    // Recalculate costs is handled by realtime subscription or manual refresh,
    // but to be snappy we can call it here too.
    // However, let's rely on the method called after fetch or realtime for now to avoid race conditions.
    // Actually, calling fetchCosts here ensures the user sees the price update immediately after their action.
    await fetchCosts()
  }
}

async function toggleAbsent(reg: SessionRegistration) {
  if (!isSessionEditable.value) return

  const newValue = !reg.is_registered_not_attended

  // Optimistic update
  reg.is_registered_not_attended = newValue

  const { error } = await supabase
    .from('session_registrations')
    .update({ is_registered_not_attended: newValue })
    .eq('id', reg.id)

  if (error) {
    reg.is_registered_not_attended = !newValue
    console.error('Error updating status:', error)
  } else {
    await fetchCosts()
  }
}

const formatCurrency = (value: number) => {
  const formatter = currencyFormatters[langStore.currentLang] || currencyFormatters.vi
  return formatter!.format(value)
}

const formatTime = (isoString: string) => {
  return format(new Date(isoString), 'HH:mm')
}

const presentIntervalCount = (memberId: string) => {
  return Object.values(presence.value[memberId] || {}).filter(Boolean).length
}

const formatSessionDate = (isoString: string) => {
  return format(new Date(isoString), 'EEEE, dd/MM/yyyy', { locale: dateLocale.value })
}

const getStatusLabel = (status: string) => {
  return t.value(`common.${status}`)
}

const getStatusChipClass = (status: string) =>
  status === 'done'
    ? 'bg-green-100 text-green-800'
    : status === 'waiting_for_payment'
      ? 'bg-orange-100 text-orange-800'
      : status === 'cancelled'
        ? 'bg-gray-100 text-gray-800'
        : 'bg-blue-100 text-blue-800'

const totalCollected = computed(() => {
  if (costs.value.length > 0) {
    return costs.value.reduce((sum, c) => sum + c.final_total, 0)
  }

  return snapshots.value.reduce((sum, s) => sum + s.final_amount, 0)
})

const overviewMessage = computed(() => {
  if (isSessionCancelled.value) return t.value('session.cancelledSessionHint')
  if (isSessionFinalized.value) return t.value('session.lockedSessionHint')
  if (!authStore.isAuthenticated) return t.value('session.readOnlyHint')
  if (isReadOnlyViewer.value) return t.value('session.adminOnlyHint')
  return ''
})

const sessionTimeRange = computed(() => {
  if (intervals.value.length === 0) return ''

  const firstInterval = intervals.value[0]
  const lastInterval = intervals.value[intervals.value.length - 1]
  if (!firstInterval || !lastInterval) return ''

  return `${formatTime(firstInterval.start_time)} - ${formatTime(lastInterval.end_time)}`
})

const surplus = computed(() => {
  if (!session.value || costs.value.length === 0) return 0

  const totalCollected = costs.value.reduce((sum, c) => sum + c.final_total, 0)
  // Note: session.court_fee_total and shuttle_fee_total might be string or number depending on DB driver, usually number in JS client
  const totalCost = (session.value.court_fee_total || 0) + (session.value.shuttle_fee_total || 0)

  return totalCollected - totalCost
})

const totalSelectedAmount = computed(() => {
  return snapshots.value
    .filter((s) => selectedSnapshotIds.value.includes(s.id))
    .reduce((sum, s) => sum + (s.final_amount - s.paid_amount), 0)
})

async function handleCreateGroupPayment() {
  if (selectedSnapshotIds.value.length === 0) return

  try {
    isCreatingGroupPayment.value = true
    const { data, error } = await supabase.rpc('create_group_payment', {
      p_snapshot_ids: selectedSnapshotIds.value,
    })

    if (error) throw error

    groupPaymentData.value = {
      group_code: data.group_code,
      total_amount: data.total_amount,
      member_count: selectedSnapshotIds.value.length,
      members: snapshots.value
        .filter((s) => selectedSnapshotIds.value.includes(s.id))
        .map((s) => ({
          name: s.display_name,
          amount: s.final_amount - s.paid_amount,
        })),
    }

    selectedMemberId.value = null
    showQRModal.value = true
  } catch (error: any) {
    console.error('Error creating group payment:', error)
    toast.error(error.message || t.value('session.finalizeError'))
  } finally {
    isCreatingGroupPayment.value = false
  }
}

function handleCloseQR() {
  showQRModal.value = false
  groupPaymentData.value = null
  selectedSnapshotIds.value = []
}

function startPolling() {
  if (pollTimer) return
  pollTimer = setInterval(() => {
    fetchData(true)
  }, 10_000) // Poll every 10 seconds
}

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer)
    pollTimer = null
  }
}

function initRealtime() {
  if (realtimeChannel) {
    supabase.removeChannel(realtimeChannel)
  }

  const intervalIds = intervals.value.map((i) => i.id)
  if (intervalIds.length === 0) return

  realtimeChannel = supabase
    .channel(`session-${sessionId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'interval_presence',
        filter: `interval_id=in.(${intervalIds.join(',')})`,
      },
      () => fetchData(true),
    )
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'session_registrations',
        filter: `session_id=eq.${sessionId}`,
      },
      () => fetchData(true),
    )
    .on(
      'postgres_changes',
      {
        event: 'UPDATE',
        schema: 'public',
        table: 'session_costs_snapshot',
        filter: `session_id=eq.${sessionId}`,
      },
      (payload) => {
        const updatedSnapshot = payload.new as CostSnapshot
        const index = snapshots.value.findIndex((s) => s.id === updatedSnapshot.id)
        if (index !== -1 && snapshots.value[index]) {
          const oldDisplayName = snapshots.value[index].display_name
          snapshots.value[index] = {
            ...snapshots.value[index],
            ...updatedSnapshot,
            display_name: oldDisplayName,
          }
        }
      },
    )
    .subscribe()
}

onMounted(async () => {
  await fetchData()
  initRealtime()
  document.addEventListener('click', handleClickOutside)
  startPolling()
})

onUnmounted(() => {
  stopPolling()
  document.removeEventListener('click', handleClickOutside)
  if (realtimeChannel) {
    supabase.removeChannel(realtimeChannel)
  }
})
</script>

<template>
  <div class="mx-auto max-w-full px-4 py-4 pb-[calc(148px+env(safe-area-inset-bottom))] sm:px-6 md:py-6 md:pb-8 lg:px-8">

    <div v-if="loading && !session" class="flex justify-center py-12">
      <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
    </div>

    <div v-else-if="session" class="space-y-4">
      <section
          id="overview-section"
          class="scroll-mt-32 rounded-2xl border border-gray-200 bg-white p-4 shadow-sm sm:p-6 md:scroll-mt-24"
        >
          <div class="mb-4 flex items-center justify-between gap-3">
            <router-link
              to="/"
              class="inline-flex min-h-11 items-center gap-1 rounded-xl px-2 text-sm font-bold text-indigo-600 transition hover:bg-indigo-50 hover:text-indigo-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
            >
              <ChevronLeft class="h-5 w-5" aria-hidden="true" />
              {{ t('common.backToHome') }}
            </router-link>
            <button
              type="button"
              @click="() => fetchData()"
              class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-xl border border-gray-200 text-gray-600 transition hover:border-indigo-200 hover:bg-indigo-50 hover:text-indigo-600 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
              :aria-label="t('session.refreshSession')"
              :title="t('session.refreshSession')"
            >
              <RefreshCcw class="h-5 w-5" :class="{ 'animate-spin': loading }" aria-hidden="true" />
              <span class="sr-only">{{ t('session.refreshSession') }}</span>
            </button>
          </div>

          <!-- Edit Mode -->
        <div v-if="isEditingSession && authStore.isAdmin" class="space-y-4">
          <div class="flex justify-between items-center mb-2">
            <h2 class="text-xl font-bold text-gray-900">{{ t('session.editSession') }}</h2>
            <button @click="isEditingSession = false" class="text-gray-400 hover:text-gray-600">
              <X class="w-5 h-5" />
            </button>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700">{{
                t('session.title')
              }}</label>
              <input
                v-model="sessionForm.title"
                type="text"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">{{
                t('common.status')
              }}</label>
              <select
                v-model="sessionForm.status"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
              >
                <option value="open">{{ t('common.open') }}</option>
                <option value="waiting_for_payment">{{ t('common.waiting_for_payment') }}</option>
                <option value="done">{{ t('common.done') }}</option>
                <option value="cancelled">{{ t('common.cancelled') }}</option>
              </select>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">{{
                t('session.courtFee')
              }}</label>
              <input
                v-model.number="sessionForm.court_fee_total"
                type="number"
                step="1000"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">{{
                t('session.shuttleFee')
              }}</label>
              <input
                v-model.number="sessionForm.shuttle_fee_total"
                type="number"
                step="1000"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
              />
            </div>
          </div>
          <div class="flex justify-end gap-3 pt-2 border-t border-gray-50 mt-4">
            <button
              @click="isEditingSession = false"
              class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 transition"
            >
              {{ t('common.cancel') }}
            </button>
            <button
              @click="saveSession"
              :disabled="isSavingSession"
              class="flex items-center px-4 py-2 text-sm font-medium text-white bg-indigo-600 rounded-md hover:bg-indigo-700 transition disabled:opacity-50"
            >
              <Save v-if="!isSavingSession" class="w-4 h-4 mr-2" />
              <Loader2 v-else class="w-4 h-4 mr-2 animate-spin" />
              {{ t('common.save') }}
            </button>
          </div>
        </div>

        <!-- View Mode -->
          <div v-else class="space-y-5">
            <div class="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
              <div class="min-w-0">
                <div class="mb-2 flex items-start gap-3">
                  <h1 class="text-2xl font-bold leading-tight text-gray-900 md:text-3xl">{{ session.title }}</h1>
                  <button
                    v-if="isSessionEditable"
                    type="button"
                    @click="isEditingSession = true"
                    class="inline-flex min-h-11 min-w-11 shrink-0 items-center justify-center rounded-xl text-gray-400 transition hover:bg-indigo-50 hover:text-indigo-600 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
                    :title="t('session.editSession')"
                    :aria-label="t('session.editSession')"
                  >
                    <Edit class="h-5 w-5" aria-hidden="true" />
                  </button>
                </div>
                <p class="text-sm font-medium capitalize text-gray-600 md:text-base">
                  {{ formatSessionDate(session.session_date) }}
                  <span v-if="sessionTimeRange"> · {{ sessionTimeRange }}</span>
                </p>
              </div>

              <span
                class="inline-flex w-fit items-center rounded-full px-3 py-1 text-sm font-bold capitalize"
                :class="getStatusChipClass(session.status)"
              >
                {{ getStatusLabel(session.status) }}
              </span>
            </div>

            <div class="grid grid-cols-1 gap-3 text-base sm:grid-cols-2 lg:grid-cols-4">
              <div class="rounded-xl bg-gray-50 p-3">
                <span class="mb-1 block text-sm font-bold text-gray-500">{{ t('session.courtFee') }}</span>
                <span class="font-semibold text-gray-900">{{ formatCurrency(session.court_fee_total) }}</span>
              </div>
              <div class="rounded-xl bg-gray-50 p-3">
                <span class="mb-1 block text-sm font-bold text-gray-500">{{ t('session.shuttleFee') }}</span>
                <span class="font-semibold text-gray-900">{{ formatCurrency(session.shuttle_fee_total) }}</span>
              </div>
              <div
                v-if="session.status === 'waiting_for_payment' || session.status === 'done'"
                class="rounded-xl bg-indigo-50 p-3"
              >
                <span class="mb-1 block text-sm font-bold text-indigo-700">{{ t('session.totalCollected') }}</span>
                <span class="font-bold text-indigo-700">{{ formatCurrency(totalCollected) }}</span>
              </div>
            </div>

            <div
              v-if="overviewMessage"
              class="rounded-xl border border-gray-200 bg-gray-50 px-4 py-3 text-sm font-medium text-gray-700"
            >
              {{ overviewMessage }}
            </div>

            <div v-if="isSessionEditable" class="flex flex-col gap-2 sm:flex-row sm:justify-end">
              <button
                type="button"
                @click="cancelSession"
                class="inline-flex min-h-11 items-center justify-center rounded-xl bg-gray-600 px-4 py-2 text-sm font-bold text-white shadow-sm transition hover:bg-gray-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-600"
              >
                🚫 {{ t('session.cancelSession') }}
              </button>
              <button
                type="button"
                @click="finalizeSession"
                :disabled="finalizeLoading"
                class="inline-flex min-h-11 items-center justify-center rounded-xl bg-indigo-600 px-4 py-2 text-sm font-bold text-white shadow-sm transition hover:bg-indigo-700 disabled:opacity-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
              >
                <Lock v-if="!finalizeLoading" class="mr-2 h-4 w-4" aria-hidden="true" />
                <Loader2 v-else class="mr-2 h-4 w-4 animate-spin" aria-hidden="true" />
                {{ t('session.finalize') }}
              </button>
            </div>
          </div>
        </section>

      <nav
        class="sticky top-16 z-30 -mx-4 my-4 overflow-x-auto border-y border-gray-200 bg-white/95 px-4 py-2 shadow-sm backdrop-blur md:hidden"
        :aria-label="t('session.cockpitNavLabel')"
      >
        <div class="flex min-w-max gap-2">
          <button
            v-for="tab in sectionTabs"
            :key="tab.id"
            type="button"
            class="min-h-11 rounded-full px-4 text-sm font-bold transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
            :class="
              activeSection === tab.id
                ? 'bg-indigo-600 text-white shadow-sm'
                : 'bg-gray-100 text-gray-700 hover:bg-indigo-50 hover:text-indigo-700'
            "
            :aria-label="tab.ariaLabel"
            :aria-controls="tab.id"
            :aria-current="activeSection === tab.id ? 'true' : undefined"
            @click="scrollToSection(tab.id)"
          >
            {{ tab.label }}
          </button>
        </div>
      </nav>
      <!-- Cancelled Banner -->
      <div
        v-if="isSessionCancelled"
        class="bg-gray-50 border-l-4 border-gray-400 p-4 mb-8"
      >
        <div class="flex">
          <div class="flex-shrink-0">
            <X class="h-5 w-5 text-gray-400" aria-hidden="true" />
          </div>
          <div class="ml-3">
            <p class="text-sm text-gray-700">
              {{ t('session.cancelledMessage') }}
            </p>
          </div>
        </div>
      </div>

      <!-- Attendance -->
      <section id="attendance-section" class="scroll-mt-32 rounded-2xl border border-gray-100 bg-white shadow-sm md:scroll-mt-24">
        <div
          class="px-6 py-4 border-b border-gray-100 bg-gray-50"
        >
          <h2 class="text-xl font-semibold text-gray-900">{{ t('session.attendance') }}</h2>
          <p v-if="attendanceLockMessage" class="mt-1 text-sm text-gray-600">
            <Lock class="inline h-4 w-4 align-[-2px] text-gray-400" aria-hidden="true" />
            {{
              attendanceLockMessage
            }}
          </p>
        </div>

        <!-- Add Members to Session -->
        <div class="border-b border-gray-100 p-4 sm:p-6">
          <div
            v-if="isSessionEditable"
            class="rounded-2xl border border-indigo-100 bg-indigo-50/60 p-4"
            ref="dropdownRef"
          >
            <div class="mb-3 flex items-center gap-2">
              <UserPlus class="h-5 w-5 text-indigo-600" aria-hidden="true" />
              <h3 class="text-base font-semibold text-gray-900">{{ t('session.addMembersTitle') }}</h3>
            </div>
            <div class="flex w-full flex-col gap-3 sm:flex-row sm:items-start">
              <div class="relative w-full sm:w-80">
                <button
                  type="button"
                  @click="showMemberDropdown = !showMemberDropdown"
                  class="flex min-h-11 w-full items-center justify-between rounded-xl border border-gray-300 bg-white px-4 py-2 text-left text-sm shadow-sm cursor-pointer focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
                >
                  <span v-if="selectedMemberIds.length === 0" class="text-gray-500">{{
                    t('session.selectMembers')
                  }}</span>
                  <span v-else class="font-medium text-gray-900">{{
                    t('session.selectedCount', { count: selectedMemberIds.length })
                  }}</span>
                  <ChevronLeft
                    class="h-4 w-4 text-gray-400 transition-transform duration-200"
                    :class="showMemberDropdown ? 'rotate-90' : '-rotate-90'"
                  />
                </button>
                <!-- Custom Checkbox Dropdown -->
                <div
                  v-if="showMemberDropdown"
                  class="absolute z-[60] left-0 right-0 mt-2 max-h-60 overflow-y-auto rounded-xl border border-gray-200 bg-white shadow-lg animate-in fade-in zoom-in-95 duration-100"
                >
                  <div
                    v-if="availableMembers.length === 0"
                    class="p-3 text-center text-base italic text-gray-500"
                  >
                    {{ t('session.noMoreMembers') }}
                  </div>
                  <label
                    v-for="m in availableMembers"
                    :key="m.id"
                    class="flex min-h-11 cursor-pointer select-none items-center px-3 py-2 transition hover:bg-indigo-50"
                  >
                    <input
                      type="checkbox"
                      :value="m.id"
                      v-model="selectedMemberIds"
                      class="mr-3 h-5 w-5 rounded border-gray-300 text-indigo-600 focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
                    />
                    <span class="text-base text-gray-700">{{ m.display_name }}</span>
                  </label>
                </div>
              </div>
              <button
                type="button"
                @click="registerMembers"
                :disabled="selectedMemberIds.length === 0 || isRegistering"
                class="flex min-h-11 items-center justify-center rounded-xl bg-indigo-600 px-4 py-2 text-base font-semibold text-white shadow-sm transition hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 sm:whitespace-nowrap"
              >
                <UserPlus v-if="!isRegistering" class="mr-1.5 h-4 w-4" />
                <Loader2 v-else class="mr-1.5 h-4 w-4 animate-spin" />
                {{ isRegistering ? t('common.loading') : t('session.register') }}
              </button>
            </div>
          </div>
          <div v-else-if="attendanceLockMessage" class="rounded-2xl border border-gray-200 bg-gray-50 p-4 text-sm text-gray-600">
            <Lock class="mr-1 inline h-4 w-4 align-[-2px] text-gray-400" aria-hidden="true" />
            {{ attendanceLockMessage }}
          </div>
        </div>
        <div class="space-y-4 p-4 md:hidden">
          <div
            v-if="registrations.length === 0"
            class="rounded-2xl border border-dashed border-gray-300 bg-gray-50 p-5 text-center text-sm text-gray-600"
          >
            {{ t('session.noRegisteredMembers') }}
          </div>
          <article
            v-for="reg in registrations"
            :key="reg.id"
            class="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm"
            :class="{ 'bg-gray-50 opacity-90': reg.is_registered_not_attended }"
          >
            <div class="flex items-start justify-between gap-3">
              <div>
                <h3 class="text-base font-semibold text-gray-900">
                  {{ reg.member?.display_name }}
                </h3>
                <p class="mt-1 text-sm font-medium text-gray-600">
                  {{ t('session.presentIntervals') }}:
                  <span class="tabular-nums text-gray-900">
                    {{ presentIntervalCount(reg.member_id) }}/{{ intervals.length }}
                  </span>
                </p>
              </div>
              <span
                v-if="reg.is_registered_not_attended"
                class="rounded-full bg-red-50 px-3 py-1 text-sm font-semibold text-red-600"
              >
                {{ t('session.absent') }}
              </span>
            </div>

            <p
              v-if="reg.is_registered_not_attended || attendanceLockMessage"
              class="mt-3 rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-sm text-gray-600"
            >
              <Lock class="mr-1 inline h-4 w-4 align-[-2px] text-gray-400" aria-hidden="true" />
              {{
                reg.is_registered_not_attended
                  ? t('session.absent')
                  : attendanceLockMessage
              }}
            </p>

            <div v-if="isSessionEditable" class="mt-4 grid grid-cols-2 gap-2">
              <button
                type="button"
                @click="toggleAbsent(reg)"
                class="flex min-h-11 items-center justify-center rounded-xl border px-3 py-2 text-sm font-semibold transition focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
                :class="
                  reg.is_registered_not_attended
                    ? 'border-red-200 bg-red-50 text-red-700'
                    : 'border-gray-300 bg-white text-gray-700 hover:border-red-200 hover:text-red-700'
                "
                :aria-pressed="reg.is_registered_not_attended ? 'true' : 'false'"
              >
                <UserX class="mr-1.5 h-4 w-4" aria-hidden="true" />
                {{ t('session.markAbsent') }}
              </button>
              <button
                type="button"
                @click="removeRegistration(reg.id, reg.member?.display_name || '')"
                class="flex min-h-11 items-center justify-center rounded-xl border border-red-200 bg-white px-3 py-2 text-sm font-semibold text-red-600 transition hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2"
              >
                <Trash2 class="mr-1.5 h-4 w-4" aria-hidden="true" />
                {{ t('common.remove') }}
              </button>
            </div>

            <div class="mt-4 space-y-2">
              <label
                v-for="interval in intervals"
                :key="interval.id"
                class="flex min-h-11 items-center justify-between gap-3 rounded-xl border border-gray-200 bg-gray-50 px-3 py-2"
                :class="{ 'opacity-70': !isSessionEditable || reg.is_registered_not_attended }"
              >
                <span class="text-sm font-medium text-gray-700">
                  {{ formatTime(interval.start_time) }} - {{ formatTime(interval.end_time) }}
                </span>
                <input
                  type="checkbox"
                  :checked="presence[reg.member_id]?.[interval.id] || false"
                  @change="togglePresence(reg.member_id, interval.id)"
                  :disabled="!isSessionEditable || reg.is_registered_not_attended"
                  class="h-6 w-6 rounded border-gray-300 text-indigo-600 focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
                  :aria-label="`${reg.member?.display_name || t('common.member')} ${formatTime(interval.start_time)} - ${formatTime(interval.end_time)}`"
                />
              </label>
            </div>
          </article>
        </div>
        <div class="hidden md:block overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th
                  scope="col"
                  class="sticky left-0 z-10 bg-gray-50 px-6 py-3 text-left text-sm font-medium text-gray-500 uppercase tracking-wider border-r border-gray-200 shadow-[2px_0_5px_rgba(0,0,0,0.05)] w-48"
                >
                  {{ t('common.member') }}
                </th>
                <th
                  v-if="isSessionEditable"
                  scope="col"
                  class="px-2 py-3 text-center text-sm font-medium text-gray-500 uppercase tracking-wider w-12"
                >
                  <span class="sr-only">{{ t('common.actions') }}</span>
                </th>
                <th
                  v-if="isSessionEditable"
                  scope="col"
                  class="px-2 py-3 text-center text-sm font-medium text-gray-500 uppercase tracking-wider w-16"
                >
                  {{ t('session.absent') }}
                </th>
                <th
                  v-for="interval in intervals"
                  :key="interval.id"
                  scope="col"
                  class="px-3 py-3 text-center text-sm font-medium text-gray-500 uppercase tracking-wider min-w-[100px]"
                >
                  {{ formatTime(interval.start_time) }} - {{ formatTime(interval.end_time) }}
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <tr
                v-for="reg in registrations"
                :key="reg.id"
                :class="{ 'opacity-60 bg-gray-50': reg.is_registered_not_attended }"
              >
                <td
                  class="sticky left-0 z-10 bg-white px-6 py-4 whitespace-nowrap text-base font-medium text-gray-900 border-r border-gray-200 shadow-[2px_0_5px_rgba(0,0,0,0.05)]"
                >
                  <div class="flex items-center">
                    {{ reg.member?.display_name }}
                    <span
                      v-if="reg.is_registered_not_attended"
                      class="ml-2 text-sm text-red-500 font-normal italic"
                      >({{ t('session.absent') }})</span
                    >
                  </div>
                </td>
                <td
                  v-if="isSessionEditable"
                  class="px-2 py-4 whitespace-nowrap text-center"
                >
                  <button
                    type="button"
                    @click="removeRegistration(reg.id, reg.member?.display_name || '')"
                    class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-xl text-gray-300 transition hover:text-red-500 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2"
                    :title="t('session.removeRegistrationTooltip')"
                  >
                    <Trash2 class="w-4 h-4" />
                  </button>
                </td>
                <td
                  v-if="isSessionEditable"
                  class="px-2 py-4 whitespace-nowrap text-center"
                >
                  <button
                    type="button"
                    @click="toggleAbsent(reg)"
                    class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-xl text-gray-400 transition hover:text-red-600 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
                    :class="{ 'text-red-600': reg.is_registered_not_attended }"
                    :title="t('session.markAbsentTooltip')"
                  >
                    <UserX class="w-5 h-5" />
                  </button>
                </td>
                <td
                  v-for="interval in intervals"
                  :key="interval.id"
                  class="px-3 py-4 whitespace-nowrap text-center"
                >
                  <div class="flex justify-center items-center h-full">
                    <input
                      type="checkbox"
                      :checked="presence[reg.member_id]?.[interval.id] || false"
                      @change="togglePresence(reg.member_id, interval.id)"
                      :disabled="
                        !isSessionEditable ||
                        reg.is_registered_not_attended ||
                        isSessionFinalized
                      "
                      class="h-6 w-6 cursor-pointer rounded border-gray-300 text-indigo-600 focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
                    />
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- Cost Summary (Live mode) -->
      <section
        id="costs-section"
        class="scroll-mt-32 rounded-2xl border border-gray-100 bg-white shadow-sm md:scroll-mt-24"
      >
        <div class="px-6 py-4 border-b border-gray-100 bg-gray-50">
          <h2 class="text-xl font-semibold text-gray-900">
            {{ t('session.costSummary') }}
            <span class="text-xs font-normal text-gray-500">({{ t('session.live') }})</span>
          </h2>
        </div>
        <div v-if="session.status !== 'waiting_for_payment' && session.status !== 'done'">
          <div
            v-if="costs.length === 0"
            class="p-6 text-sm text-gray-500 md:hidden"
          >
            {{ t('session.liveCostsEmpty') }}
          </div>
          <div v-else class="space-y-4 p-4 md:hidden">
            <div class="rounded-2xl border border-green-100 bg-green-50 p-4">
              <p class="text-sm font-bold text-green-800">{{ t('session.surplusFund') }}</p>
              <p class="mt-1 text-2xl font-bold text-green-700 tabular-nums">
                {{ formatCurrency(surplus) }}
              </p>
              <p class="mt-1 text-sm text-green-700">{{ t('session.live') }}</p>
            </div>

            <article
              v-for="cost in costs"
              :key="cost.member_id"
              class="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm"
            >
              <div class="flex items-start justify-between gap-3">
                <div>
                  <h3 class="text-base font-bold text-gray-900">
                    {{ cost.display_name }}
                  </h3>
                  <p class="mt-1 text-sm font-semibold text-gray-500">
                    {{ t('session.live') }}
                  </p>
                </div>
                <div class="text-right">
                  <p class="text-sm font-bold text-gray-500">{{ t('session.total') }}</p>
                  <p class="text-2xl font-bold text-indigo-700 tabular-nums">
                    {{ formatCurrency(cost.final_total) }}
                  </p>
                </div>
              </div>

              <dl class="mt-4 grid grid-cols-1 gap-3 text-sm">
                <div class="flex justify-between gap-3 rounded-xl bg-gray-50 px-3 py-2">
                  <dt class="font-bold text-gray-500">{{ t('session.numIntervals') }}</dt>
                  <dd class="font-semibold text-gray-900 tabular-nums">{{ cost.intervals_count }}</dd>
                </div>
                <div class="flex justify-between gap-3 rounded-xl bg-gray-50 px-3 py-2">
                  <dt class="font-bold text-gray-500">{{ t('session.courtFee') }}</dt>
                  <dd class="font-semibold text-gray-900 tabular-nums">
                    {{ formatCurrency(cost.total_court_fee) }}
                  </dd>
                </div>
                <div class="flex justify-between gap-3 rounded-xl bg-gray-50 px-3 py-2">
                  <dt class="font-bold text-gray-500">{{ t('session.shuttleFee') }}</dt>
                  <dd class="font-semibold text-gray-900 tabular-nums">
                    {{ formatCurrency(cost.total_shuttle_fee) }}
                  </dd>
                </div>
                <div class="flex justify-between gap-3 rounded-xl bg-green-50 px-3 py-2">
                  <dt class="font-bold text-green-800">{{ t('session.surplusFund') }}</dt>
                  <dd class="font-bold text-green-700 tabular-nums">
                    {{ formatCurrency(surplus) }}
                  </dd>
                </div>
              </dl>
            </article>
          </div>

          <div class="hidden overflow-x-auto md:block">
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
                  class="px-6 py-3 text-right text-sm font-medium text-gray-500 uppercase tracking-wider font-bold"
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
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <tr v-for="cost in costs" :key="cost.member_id">
                <td class="px-6 py-4 whitespace-nowrap text-base font-medium text-gray-900">
                  {{ cost.display_name }}
                </td>
                <td
                  class="px-6 py-4 whitespace-nowrap text-base text-right font-bold text-gray-900"
                >
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
              </tr>
              <!-- Surplus Row -->
              <tr class="bg-gray-50">
                <td colspan="4" class="px-6 py-4 text-right text-base font-bold text-gray-700">
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
        <div
          v-else
          class="p-6 text-sm text-gray-500"
        >
          {{ t('session.liveCostsEmpty') }}
        </div>
      </section>

      <!-- Snapshot View (Waiting/Done mode) -->
      <section
        id="payments-section"
        class="scroll-mt-32 rounded-2xl border border-gray-100 bg-white shadow-sm md:scroll-mt-24"
      >
        <div
          class="px-6 py-4 border-b border-gray-100 bg-gray-50 flex justify-between items-center"
        >
          <h2 class="text-xl font-semibold text-gray-900">{{ t('session.paymentTable') }}</h2>
        </div>
        <div v-if="isSessionFinalized">
          <div
            v-if="snapshots.length === 0"
            class="p-6 text-sm text-gray-500 md:hidden"
          >
            {{ t('session.paymentSnapshotsEmpty') }}
          </div>
          <div v-else class="space-y-4 p-4 md:hidden">
            <div class="rounded-2xl border border-green-100 bg-green-50 p-4">
              <p class="text-sm font-bold text-green-800">{{ t('session.surplusFund') }}</p>
              <p class="mt-1 text-2xl font-bold text-green-700 tabular-nums">
                {{ formatCurrency(surplus) }}
              </p>
            </div>

            <article
              v-for="snapshot in snapshots"
              :key="snapshot.id"
              class="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm"
            >
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <div class="flex items-start gap-3">
                    <label
                      v-if="snapshot.status !== 'paid' && authStore.isAuthenticated"
                      class="inline-flex min-h-11 min-w-11 shrink-0 items-center justify-center rounded-xl border border-indigo-100 bg-indigo-50"
                    >
                      <input
                        type="checkbox"
                        :value="snapshot.id"
                        v-model="selectedSnapshotIds"
                        class="h-5 w-5 rounded border-gray-300 text-indigo-600 focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
                        :aria-label="`${t('session.groupPaymentBar', { count: 1 })}: ${snapshot.display_name}`"
                      />
                    </label>
                    <div class="min-w-0">
                      <h3 class="truncate text-base font-bold uppercase text-gray-900">
                        {{ snapshot.display_name }}
                      </h3>
                      <span
                        class="mt-2 inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-bold"
                        :class="{
                          'bg-green-100 text-green-800': snapshot.status === 'paid',
                          'bg-yellow-100 text-yellow-800': snapshot.status === 'partial',
                          'bg-gray-100 text-gray-800': snapshot.status === 'pending',
                        }"
                      >
                        {{
                          snapshot.status === 'paid'
                            ? t('payment.paid')
                            : snapshot.status === 'partial'
                              ? t('payment.partial')
                              : t('payment.pending')
                        }}
                      </span>
                    </div>
                  </div>
                </div>
                <div class="text-right">
                  <p class="text-sm font-bold text-gray-500">{{ t('session.mustPay') }}</p>
                  <p class="text-2xl font-bold text-indigo-700 tabular-nums">
                    {{ formatCurrency(snapshot.final_amount) }}
                  </p>
                </div>
              </div>

              <dl class="mt-4 grid grid-cols-1 gap-3 text-sm">
                <div class="flex justify-between gap-3 rounded-xl bg-gray-50 px-3 py-2">
                  <dt class="font-bold text-gray-500">{{ t('payment.paid') }}</dt>
                  <dd class="font-bold text-green-600 tabular-nums">
                    {{ formatCurrency(snapshot.paid_amount) }}
                  </dd>
                </div>
                <div class="flex justify-between gap-3 rounded-xl bg-gray-50 px-3 py-2">
                  <dt class="font-bold text-gray-500">{{ t('session.intervalsAbbr') }}</dt>
                  <dd class="font-semibold text-gray-900 tabular-nums">
                    {{ getBreakdown(snapshot.member_id)?.intervals_count || 0 }}
                  </dd>
                </div>
                <div class="flex justify-between gap-3 rounded-xl bg-gray-50 px-3 py-2">
                  <dt class="font-bold text-gray-500">{{ t('session.courtFee') }}</dt>
                  <dd class="font-semibold text-gray-900 tabular-nums">
                    {{ formatCurrency(getBreakdown(snapshot.member_id)?.total_court_fee || 0) }}
                  </dd>
                </div>
                <div class="flex justify-between gap-3 rounded-xl bg-gray-50 px-3 py-2">
                  <dt class="font-bold text-gray-500">{{ t('session.shuttleFee') }}</dt>
                  <dd class="font-semibold text-gray-900 tabular-nums">
                    {{ formatCurrency(getBreakdown(snapshot.member_id)?.total_shuttle_fee || 0) }}
                  </dd>
                </div>
                <div class="flex justify-between gap-3 rounded-xl bg-green-50 px-3 py-2">
                  <dt class="font-bold text-green-800">{{ t('session.surplusFund') }}</dt>
                  <dd class="font-bold text-green-700 tabular-nums">
                    {{ formatCurrency(surplus) }}
                  </dd>
                </div>
              </dl>

              <div
                v-if="snapshot.status !== 'paid'"
                class="mt-4 grid grid-cols-1 gap-2 sm:grid-cols-2"
              >
                <button
                  type="button"
                  @click="openPaymentQR(snapshot, snapshot.display_name)"
                  class="inline-flex min-h-11 items-center justify-center rounded-xl border border-indigo-600 px-4 py-2 text-sm font-bold text-indigo-600 transition hover:bg-indigo-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
                >
                  <QrCode class="mr-1.5 h-4 w-4" aria-hidden="true" />
                  {{ t('payment.qrPay') }}
                </button>
                <button
                  v-if="authStore.isAdmin"
                  type="button"
                  @click="openCashPayment(snapshot, snapshot.display_name)"
                  class="inline-flex min-h-11 items-center justify-center rounded-xl border border-green-600 px-4 py-2 text-sm font-bold text-green-600 transition hover:bg-green-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-green-600"
                >
                  {{ t('payment.cashPay') }}
                </button>
              </div>
              <div
                v-else
                class="mt-4 flex min-h-11 items-center justify-center rounded-xl bg-green-50 text-sm font-bold text-green-600"
              >
                <Check class="mr-1.5 h-5 w-5" aria-hidden="true" />
                {{ t('payment.done') }}
              </div>
            </article>
          </div>

          <div class="hidden overflow-x-auto md:block">
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
                  class="px-6 py-3 text-right text-sm font-medium text-gray-500 uppercase tracking-wider font-bold"
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
                    v-model="selectedSnapshotIds"
                    class="h-5 w-5 text-indigo-600 border-gray-300 rounded focus:ring-indigo-500 cursor-pointer"
                  />
                  <Check v-else class="w-5 h-5 text-green-500 mx-auto" />
                </td>
                <td
                  class="px-6 py-4 whitespace-nowrap text-base font-medium text-gray-900 uppercase"
                >
                  {{ snapshot.display_name }}
                </td>
                <td
                  class="px-6 py-4 whitespace-nowrap text-base text-right font-bold text-indigo-700"
                >
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
                <td
                  class="px-6 py-4 whitespace-nowrap text-base text-right text-green-600 font-bold"
                >
                  {{ formatCurrency(snapshot.paid_amount) }}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-center">
                  <span
                    class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"
                    :class="{
                      'bg-green-100 text-green-800': snapshot.status === 'paid',
                      'bg-yellow-100 text-yellow-800': snapshot.status === 'partial',
                      'bg-gray-100 text-gray-800': snapshot.status === 'pending',
                    }"
                  >
                    {{
                      snapshot.status === 'paid'
                        ? t('payment.paid')
                        : snapshot.status === 'partial'
                          ? t('payment.partial')
                          : t('payment.pending')
                    }}
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-center">
                  <div class="flex flex-col gap-1.5 items-center">
                    <button
                      v-if="snapshot.status !== 'paid'"
                      @click="openPaymentQR(snapshot, snapshot.display_name)"
                      class="inline-flex items-center px-3 py-1.5 border border-indigo-600 text-indigo-600 rounded-md hover:bg-indigo-50 transition text-sm font-medium w-full justify-center"
                    >
                      <QrCode class="w-4 h-4 mr-1.5" />
                      {{ t('payment.qrPay') }}
                    </button>
                    <button
                      v-if="snapshot.status !== 'paid' && authStore.isAdmin"
                      @click="openCashPayment(snapshot, snapshot.display_name)"
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
              <!-- Surplus Row -->
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
        <div v-else class="p-6 text-sm text-gray-500">{{ t('session.paymentSnapshotsEmpty') }}</div>
      </section>

    </div>

    <!-- Floating Action Bar for Group Payment -->
    <Transition
      enter-active-class="transition duration-300 ease-out"
      enter-from-class="transform translate-y-full opacity-0"
      enter-to-class="transform translate-y-0 opacity-100"
      leave-active-class="transition duration-200 ease-in"
      leave-from-class="transform translate-y-0 opacity-100"
      leave-to-class="transform translate-y-full opacity-0"
    >
      <div
        v-if="selectedSnapshotIds.length > 0"
        class="fixed bottom-[calc(92px+env(safe-area-inset-bottom))] left-1/2 z-50 w-[calc(100%-2rem)] max-w-2xl -translate-x-1/2 md:bottom-8"
      >
        <div
          class="bg-indigo-600 text-white rounded-2xl shadow-2xl p-4 flex items-center justify-between border border-indigo-500/50 backdrop-blur-md"
        >
          <div class="flex flex-col">
            <span class="text-sm font-medium opacity-90">{{
              t('session.groupPaymentBar', { count: selectedSnapshotIds.length })
            }}</span>
            <span class="text-xl font-extrabold">{{
              t('session.totalSelected', { amount: formatCurrency(totalSelectedAmount) })
            }}</span>
          </div>
          <button
            @click="handleCreateGroupPayment"
            :disabled="isCreatingGroupPayment"
            class="flex min-h-11 items-center rounded-xl bg-white px-6 py-2.5 font-bold text-indigo-600 shadow-sm transition hover:bg-indigo-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white active:scale-95 disabled:opacity-50"
          >
            <Loader2 v-if="isCreatingGroupPayment" class="w-5 h-5 mr-2 animate-spin" />
            <QrCode v-else class="w-5 h-5 mr-2" />
            {{ t('session.groupPayButton') }}
          </button>
        </div>
      </div>
    </Transition>
  </div>

  <PaymentQRModal
    :show="showQRModal"
    :snapshot="selectedSnapshot"
    :memberName="selectedSnapshotMemberName"
    :groupData="groupPaymentData"
    :isPaid="isPaymentSuccess"
    @close="handleCloseQR"
    @payment-complete="fetchData"
  />

  <ManualPaymentModal
    :show="showCashModal"
    :snapshot="selectedSnapshot"
    :memberName="selectedSnapshotMemberName"
    @close="showCashModal = false"
    @success="fetchSnapshotData"
  />
</template>
