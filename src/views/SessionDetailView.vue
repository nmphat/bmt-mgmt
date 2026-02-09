<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '@/lib/supabase'
import type { SessionSummary, Interval, SessionRegistration, MemberCost, Member } from '@/types'
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
const selectedSnapshotMemberName = ref('')
const isEditingSession = ref(false)
const isSavingSession = ref(false)
const sessionForm = ref({
  title: '',
  status: 'draft' as 'draft' | 'active' | 'closed',
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

const handleClickOutside = (event: MouseEvent) => {
  if (dropdownRef.value && !dropdownRef.value.contains(event.target as Node)) {
    showMemberDropdown.value = false
  }
}

async function fetchData(refreshCostsOnly = false) {
  try {
    if (!refreshCostsOnly) loading.value = true

    // Fetch session summary (Always fetch this now to detect status changes)
    const { data: sessionData, error: sessionError } = await supabase
      .from('view_session_summary')
      .select('*')
      .eq('id', sessionId)
      .single()

    if (sessionError) throw sessionError
    session.value = sessionData

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

    if (session.value?.status === 'closed') {
      await fetchSnapshotData()
    }
    // Always fetch costs for breakdown/reference
    await fetchCosts()
  } catch (error) {
    console.error('Error fetching session details:', error)
  } finally {
    loading.value = false
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
  if (!authStore.isAuthenticated || !session.value) return
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

function openPaymentQR(snapshot: CostSnapshot, name: string) {
  selectedMemberId.value = snapshot.member_id
  selectedSnapshotMemberName.value = name
  showQRModal.value = true
}

function openCashPayment(snapshot: CostSnapshot, name: string) {
  selectedMemberId.value = snapshot.member_id
  selectedSnapshotMemberName.value = name
  showCashModal.value = true
}

async function saveSession() {
  if (!authStore.isAuthenticated) return

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
  if (!authStore.isAuthenticated) return

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
  if (!authStore.isAuthenticated) return

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
  return new Intl.NumberFormat(langStore.currentLang === 'vi' ? 'vi-VN' : 'en-US', {
    style: 'currency',
    currency: 'VND',
    maximumFractionDigits: 0,
  }).format(value)
}

const formatTime = (isoString: string) => {
  return format(new Date(isoString), 'HH:mm')
}

const formatSessionDate = (isoString: string) => {
  return format(new Date(isoString), 'EEEE, dd/MM/yyyy', { locale: dateLocale.value })
}

const getStatusLabel = (status: string) => {
  return t.value(`common.${status}`)
}

const surplus = computed(() => {
  if (!session.value || costs.value.length === 0) return 0

  const totalCollected = costs.value.reduce((sum, c) => sum + c.final_total, 0)
  // Note: session.court_fee_total and shuttle_fee_total might be string or number depending on DB driver, usually number in JS client
  const totalCost = (session.value.court_fee_total || 0) + (session.value.shuttle_fee_total || 0)

  return totalCollected - totalCost
})

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

onMounted(() => {
  fetchData()
  document.addEventListener('click', handleClickOutside)

  realtimeChannel = supabase
    .channel(`session-${sessionId}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'interval_presence' }, () =>
      fetchData(true),
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
          // Preserve display_name since it's not in the update payload
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
  <div class="max-w-full mx-auto px-4 sm:px-6 lg:px-8 py-6">
    <div class="mb-6 flex items-center justify-between">
      <router-link
        to="/"
        class="flex items-center text-indigo-600 hover:text-indigo-800 transition"
      >
        <ChevronLeft class="w-5 h-5 mr-1" />
        {{ t('common.backToHome') }}
      </router-link>
      <button @click="() => fetchData()" class="p-2 text-gray-500 hover:text-indigo-600 transition">
        <RefreshCcw class="w-5 h-5" :class="{ 'animate-spin': loading }" />
      </button>
    </div>

    <div v-if="loading && !session" class="flex justify-center py-12">
      <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
    </div>

    <div v-else-if="session">
      <div class="bg-white rounded-lg shadow-sm p-6 mb-8 border border-gray-100">
        <!-- Edit Mode -->
        <div v-if="isEditingSession && authStore.isAuthenticated" class="space-y-4">
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
                <option value="draft">{{ t('common.draft') }}</option>
                <option value="active">{{ t('common.active') }}</option>
                <option value="closed">{{ t('common.closed') }}</option>
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
        <div v-else class="flex justify-between items-start">
          <div>
            <div class="flex items-center gap-3 mb-2">
              <h1 class="text-3xl font-bold text-gray-900">{{ session.title }}</h1>
              <button
                v-if="authStore.isAuthenticated && session.status !== 'closed'"
                @click="isEditingSession = true"
                class="p-1 text-gray-400 hover:text-indigo-600 transition"
                :title="t('session.editSession')"
              >
                <Edit class="w-5 h-5" />
              </button>
            </div>
            <p class="text-gray-600 mb-4 capitalize">
              {{ formatSessionDate(session.session_date) }}
            </p>
            <div class="flex flex-wrap gap-6 text-base">
              <div>
                <span class="text-gray-500 block mb-1">{{ t('session.courtFee') }}</span>
                <span class="font-semibold text-gray-900">{{
                  formatCurrency(session.court_fee_total)
                }}</span>
              </div>
              <div>
                <span class="text-gray-500 block mb-1">{{ t('session.shuttleFee') }}</span>
                <span class="font-semibold text-gray-900">{{
                  formatCurrency(session.shuttle_fee_total)
                }}</span>
              </div>
              <div v-if="session.status === 'closed'">
                <span class="text-gray-500 block mb-1 font-bold text-indigo-600">{{
                  t('session.totalCollected')
                }}</span>
                <span class="font-bold text-indigo-700">{{
                  formatCurrency(
                    costs.length > 0
                      ? costs.reduce((sum, c) => sum + c.final_total, 0)
                      : snapshots.reduce((sum, s) => sum + s.final_amount, 0),
                  )
                }}</span>
              </div>
              <div>
                <span class="text-gray-500 block mb-1">{{ t('common.status') }}</span>
                <span
                  class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium capitalize"
                  :class="
                    session.status === 'closed'
                      ? 'bg-gray-100 text-gray-800'
                      : 'bg-green-100 text-green-800'
                  "
                >
                  {{ getStatusLabel(session.status) }}
                </span>
              </div>
            </div>
          </div>

          <div
            v-if="authStore.isAuthenticated && session.status === 'active'"
            class="flex items-center"
          >
            <button
              @click="finalizeSession"
              :disabled="finalizeLoading"
              class="flex items-center px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700 transition shadow-sm font-medium"
            >
              <Lock v-if="!finalizeLoading" class="w-4 h-4 mr-2" />
              <Loader2 v-else class="w-4 h-4 mr-2 animate-spin" />
              {{ t('session.finalize') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Snapshot View (Closed mode) -->
      <div
        v-if="session.status === 'closed'"
        class="bg-white rounded-lg shadow-sm overflow-hidden border border-gray-100 mb-8"
      >
        <div
          class="px-6 py-4 border-b border-gray-100 bg-gray-50 flex justify-between items-center"
        >
          <h2 class="text-xl font-semibold text-gray-900">{{ t('session.paymentTable') }}</h2>
        </div>
        <div class="overflow-x-auto">
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
                      <CreditCard class="w-4 h-4 mr-1.5" />
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
                <td colspan="5" class="px-6 py-4 text-right text-sm font-bold text-gray-700">
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

      <!-- Attendance Matrix -->
      <div class="bg-white rounded-lg shadow-sm mb-8 border border-gray-100">
        <div
          class="px-6 py-4 border-b border-gray-100 bg-gray-50 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4"
        >
          <div class="flex items-center gap-2">
            <h2 class="text-xl font-semibold text-gray-900">{{ t('session.attendanceMatrix') }}</h2>
            <span v-if="!authStore.isAuthenticated" class="text-xs text-gray-500 italic">{{
              t('session.readOnly')
            }}</span>
          </div>
          <!-- Add Members to Session -->
          <div
            v-if="authStore.isAuthenticated && session.status !== 'closed'"
            class="flex items-center gap-2 w-full sm:w-auto relative"
            ref="dropdownRef"
          >
            <div class="relative w-full sm:w-64">
              <button
                @click="showMemberDropdown = !showMemberDropdown"
                class="flex items-center justify-between w-full rounded-md border-gray-300 shadow-sm bg-white border px-3 py-1.5 text-sm cursor-pointer focus:ring-2 focus:ring-indigo-500 focus:outline-none"
              >
                <span v-if="selectedMemberIds.length === 0" class="text-gray-500">{{
                  t('session.selectMembers')
                }}</span>
                <span v-else class="text-gray-900 font-medium">{{
                  t('session.selectedCount', { count: selectedMemberIds.length })
                }}</span>
                <ChevronLeft
                  class="w-4 h-4 text-gray-400 transition-transform duration-200"
                  :class="showMemberDropdown ? 'rotate-90' : '-rotate-90'"
                />
              </button>
              <!-- Custom Checkbox Dropdown -->
              <div
                v-if="showMemberDropdown"
                class="absolute z-[60] left-0 right-0 mt-1 bg-white border border-gray-200 rounded-md shadow-lg max-h-60 overflow-y-auto animate-in fade-in zoom-in-95 duration-100"
              >
                <div
                  v-if="availableMembers.length === 0"
                  class="p-3 text-base text-gray-500 italic text-center"
                >
                  {{ t('session.noMoreMembers') }}
                </div>
                <label
                  v-for="m in availableMembers"
                  :key="m.id"
                  class="flex items-center px-3 py-2 hover:bg-indigo-50 cursor-pointer transition select-none"
                >
                  <input
                    type="checkbox"
                    :value="m.id"
                    v-model="selectedMemberIds"
                    class="h-4 w-4 text-indigo-600 rounded border-gray-300 mr-3"
                  />
                  <span class="text-base text-gray-700">{{ m.display_name }}</span>
                </label>
              </div>
            </div>
            <button
              @click="registerMembers"
              :disabled="selectedMemberIds.length === 0 || isRegistering"
              class="flex items-center px-4 py-1.5 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition disabled:opacity-50 whitespace-nowrap text-base font-medium shadow-sm"
            >
              <UserPlus v-if="!isRegistering" class="w-4 h-4 mr-1.5" />
              <Loader2 v-else class="w-4 h-4 mr-1.5 animate-spin" />
              {{ isRegistering ? t('common.loading') : t('session.register') }}
            </button>
          </div>
        </div>
        <div class="overflow-x-auto">
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
                  v-if="authStore.isAuthenticated && session.status !== 'closed'"
                  scope="col"
                  class="px-2 py-3 text-center text-sm font-medium text-gray-500 uppercase tracking-wider w-12"
                >
                  <span class="sr-only">Actions</span>
                </th>
                <th
                  v-if="authStore.isAuthenticated && session.status !== 'closed'"
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
                  v-if="authStore.isAuthenticated && session.status !== 'closed'"
                  class="px-2 py-4 whitespace-nowrap text-center"
                >
                  <button
                    @click="removeRegistration(reg.id, reg.member?.display_name || '')"
                    class="text-gray-300 hover:text-red-500 transition focus:outline-none"
                    :title="t('session.removeRegistrationTooltip')"
                  >
                    <Trash2 class="w-4 h-4 mx-auto" />
                  </button>
                </td>
                <td
                  v-if="authStore.isAuthenticated && session.status !== 'closed'"
                  class="px-2 py-4 whitespace-nowrap text-center"
                >
                  <button
                    @click="toggleAbsent(reg)"
                    class="text-gray-400 hover:text-red-600 transition focus:outline-none"
                    :class="{ 'text-red-600': reg.is_registered_not_attended }"
                    :title="t('session.markAbsentTooltip')"
                  >
                    <UserX class="w-5 h-5 mx-auto" />
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
                        !authStore.isAuthenticated ||
                        reg.is_registered_not_attended ||
                        session.status === 'closed'
                      "
                      class="h-5 w-5 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                    />
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Cost Summary (Live mode) -->
      <div
        v-if="session.status !== 'closed'"
        class="bg-white rounded-lg shadow-sm overflow-hidden border border-gray-100"
      >
        <div class="px-6 py-4 border-b border-gray-100 bg-gray-50">
          <h2 class="text-xl font-semibold text-gray-900">{{ t('session.costSummary') }} (Live)</h2>
        </div>
        <div class="overflow-x-auto">
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
    </div>
  </div>

  <PaymentQRModal
    :show="showQRModal"
    :snapshot="selectedSnapshot"
    :memberName="selectedSnapshotMemberName"
    @close="showQRModal = false"
  />

  <ManualPaymentModal
    :show="showCashModal"
    :snapshot="selectedSnapshot"
    :memberName="selectedSnapshotMemberName"
    @close="showCashModal = false"
    @success="fetchSnapshotData"
  />
</template>
