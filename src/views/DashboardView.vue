<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '@/lib/supabase'
import type { SessionSummary } from '@/types'
import { format } from 'date-fns'
import { vi, enUS } from 'date-fns/locale'
import { Plus, ChevronRight, Calendar, Users, Clock, Trash2, Square, CheckSquare } from 'lucide-vue-next'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { formatCurrency } from '@/utils/formatters'
import { useToast } from 'vue-toastification'

const authStore = useAuthStore()
const langStore = useLangStore()
const router = useRouter()
const toast = useToast()

const t = computed(() => langStore.t)
const dateLocale = computed(() => (langStore.currentLang === 'vi' ? vi : enUS))

const sessions = ref<SessionSummary[]>([])
const loading = ref(true)
const statusFilter = ref<'all' | 'open' | 'waiting_for_payment' | 'done' | 'cancelled'>('all')
const selectionMode = ref(false)
const selectedCancelledIds = ref<string[]>([])
const bulkDeleting = ref(false)

interface SessionDeleteImpact {
  registrations_count: number
  intervals_count: number
  presence_count: number
  court_bookings_count: number
  extra_charges_count: number
  snapshots_count: number
  payments_count: number
}

const MAX_BULK_DELETE = 50

const statusSortRank: Record<SessionSummary['status'], number> = {
  open: 0,
  waiting_for_payment: 1,
  done: 2,
  cancelled: 3,
}

const filteredSessions = computed(() => {
  const base =
    statusFilter.value === 'all'
      ? [...sessions.value]
      : sessions.value.filter((s) => s.status === statusFilter.value)

  return base.sort((a, b) => {
    const rankDiff = statusSortRank[a.status] - statusSortRank[b.status]
    if (rankDiff !== 0) return rankDiff
    return new Date(b.session_date).getTime() - new Date(a.session_date).getTime()
  })
})

const cancelledSessions = computed(() => sessions.value.filter((s) => s.status === 'cancelled'))

const filterOptions = computed(() => [
  { key: 'all',                  label: t.value('dashboard.filterAll') },
  { key: 'open',                 label: t.value('dashboard.filterOpen') },
  { key: 'waiting_for_payment',  label: t.value('dashboard.filterWaiting') },
  { key: 'done',                 label: t.value('dashboard.filterDone') },
  { key: 'cancelled',            label: t.value('dashboard.filterCancelled') },
])

async function fetchSessions() {
  try {
    loading.value = true
    const { data, error } = await supabase
      .from('view_session_summary')
      .select('*')
      .order('session_date', { ascending: false })

    if (error) throw error
    sessions.value = data || []
  } catch (error) {
    console.error('Error fetching sessions:', error)
  } finally {
    loading.value = false
  }
}

function handleCardClick(sessionId: string) {
  if (selectionMode.value) return
  router.push(`/session/${sessionId}`)
}

function toggleSelectionMode() {
  selectionMode.value = !selectionMode.value
  if (!selectionMode.value) {
    selectedCancelledIds.value = []
  }
}

function isSelected(sessionId: string) {
  return selectedCancelledIds.value.includes(sessionId)
}

function toggleSessionSelection(sessionId: string) {
  if (!selectionMode.value) return
  const next = [...selectedCancelledIds.value]
  const index = next.indexOf(sessionId)
  if (index >= 0) {
    next.splice(index, 1)
  } else {
    if (next.length >= MAX_BULK_DELETE) {
      toast.warning(t.value('dashboard.bulkDeleteLimitExceeded', { count: MAX_BULK_DELETE }))
      return
    }
    next.push(sessionId)
  }
  selectedCancelledIds.value = next
}

function selectAllCancelled() {
  const ids = cancelledSessions.value.map((s) => s.id)
  selectedCancelledIds.value = ids.slice(0, MAX_BULK_DELETE)
  if (ids.length > MAX_BULK_DELETE) {
    toast.info(t.value('dashboard.bulkDeleteLimitExceeded', { count: MAX_BULK_DELETE }))
  }
}

async function fetchDeleteImpact(sessionId: string): Promise<SessionDeleteImpact> {
  const { data, error } = await supabase.rpc('get_session_delete_impact', { p_session_id: sessionId })
  if (error) throw error
  const impact = (Array.isArray(data) ? data[0] : data) as SessionDeleteImpact | null
  if (!impact) throw new Error(t.value('session.deleteImpactLoadError'))
  return impact
}

function buildSingleDeleteMessage(impact: SessionDeleteImpact) {
  return [
    t.value('session.deleteImpactTitle'),
    `- ${t.value('session.deleteImpactRegistrations')}: ${impact.registrations_count}`,
    `- ${t.value('session.deleteImpactIntervals')}: ${impact.intervals_count}`,
    `- ${t.value('session.deleteImpactPresence')}: ${impact.presence_count}`,
    `- ${t.value('session.deleteImpactBookings')}: ${impact.court_bookings_count}`,
    `- ${t.value('session.deleteImpactExtraCharges')}: ${impact.extra_charges_count}`,
    `- ${t.value('session.deleteImpactSnapshots')}: ${impact.snapshots_count}`,
    `- ${t.value('session.deleteImpactPayments')}: ${impact.payments_count}`,
    '',
    t.value('session.deleteStepOneConfirm'),
  ].join('\n')
}

async function deleteSingleCancelledSession(sessionId: string) {
  if (!authStore.isAdmin) return

  try {
    const impact = await fetchDeleteImpact(sessionId)
    if (!confirm(buildSingleDeleteMessage(impact))) return
    if (!confirm(t.value('session.deleteStepTwoConfirm'))) return

    const { error } = await supabase.rpc('soft_delete_cancelled_session', {
      p_session_id: sessionId,
    })
    if (error) throw error

    toast.success(t.value('toast.sessionDeleted'))
    selectedCancelledIds.value = selectedCancelledIds.value.filter((id) => id !== sessionId)
    await fetchSessions()
  } catch (error: any) {
    toast.error(error.message || t.value('session.deleteError'))
  }
}

function buildBulkDeleteMessage(sessionCount: number, impact: SessionDeleteImpact) {
  return [
    t.value('dashboard.bulkDeleteImpactTitle', { count: sessionCount }),
    `- ${t.value('session.deleteImpactRegistrations')}: ${impact.registrations_count}`,
    `- ${t.value('session.deleteImpactIntervals')}: ${impact.intervals_count}`,
    `- ${t.value('session.deleteImpactPresence')}: ${impact.presence_count}`,
    `- ${t.value('session.deleteImpactBookings')}: ${impact.court_bookings_count}`,
    `- ${t.value('session.deleteImpactExtraCharges')}: ${impact.extra_charges_count}`,
    `- ${t.value('session.deleteImpactSnapshots')}: ${impact.snapshots_count}`,
    `- ${t.value('session.deleteImpactPayments')}: ${impact.payments_count}`,
    '',
    t.value('session.deleteStepOneConfirm'),
  ].join('\n')
}

async function bulkDeleteCancelledSessions() {
  if (!authStore.isAdmin || selectedCancelledIds.value.length === 0) return

  if (selectedCancelledIds.value.length > MAX_BULK_DELETE) {
    toast.warning(t.value('dashboard.bulkDeleteLimitExceeded', { count: MAX_BULK_DELETE }))
    return
  }

  try {
    bulkDeleting.value = true

    const impactList = await Promise.all(selectedCancelledIds.value.map((id) => fetchDeleteImpact(id)))
    const totalImpact = impactList.reduce(
      (acc, item) => ({
        registrations_count: acc.registrations_count + item.registrations_count,
        intervals_count: acc.intervals_count + item.intervals_count,
        presence_count: acc.presence_count + item.presence_count,
        court_bookings_count: acc.court_bookings_count + item.court_bookings_count,
        extra_charges_count: acc.extra_charges_count + item.extra_charges_count,
        snapshots_count: acc.snapshots_count + item.snapshots_count,
        payments_count: acc.payments_count + item.payments_count,
      }),
      {
        registrations_count: 0,
        intervals_count: 0,
        presence_count: 0,
        court_bookings_count: 0,
        extra_charges_count: 0,
        snapshots_count: 0,
        payments_count: 0,
      },
    )

    if (!confirm(buildBulkDeleteMessage(selectedCancelledIds.value.length, totalImpact))) return
    if (!confirm(t.value('session.deleteStepTwoConfirm'))) return

    const { data, error } = await supabase.rpc('soft_delete_cancelled_sessions_bulk', {
      p_session_ids: selectedCancelledIds.value,
    })
    if (error) throw error

    const rows = (data || []) as { session_id: string; deleted: boolean; message: string }[]
    const failed = rows.filter((r) => !r.deleted)
    const successCount = rows.length - failed.length

    if (failed.length === 0) {
      toast.success(t.value('toast.sessionsDeletedBulk', { count: successCount }))
    } else {
      toast.warning(
        t.value('toast.sessionsDeletedBulkPartial', {
          success: successCount,
          failed: failed.length,
        }),
      )
      console.error('Bulk delete failures:', failed)
    }

    selectedCancelledIds.value = []
    await fetchSessions()
  } catch (error: any) {
    toast.error(error.message || t.value('session.deleteError'))
  } finally {
    bulkDeleting.value = false
  }
}

function getStatusColor(status: string) {
  switch (status) {
    case 'open':             return 'bg-blue-100 text-blue-800'
    case 'waiting_for_payment': return 'bg-orange-100 text-orange-800'
    case 'done':             return 'bg-green-100 text-green-800'
    case 'cancelled':        return 'bg-gray-100 text-gray-500'
    default:                 return 'bg-gray-100 text-gray-500'
  }
}

function getStatusBorder(status: string) {
  switch (status) {
    case 'open':             return 'border-l-blue-400'
    case 'waiting_for_payment': return 'border-l-orange-400'
    case 'done':             return 'border-l-green-400'
    case 'cancelled':        return 'border-l-gray-300'
    default:                 return 'border-l-gray-200'
  }
}

function getStatusLabel(status: string) {
  return t.value(`common.${status}`)
}

onMounted(fetchSessions)
</script>

<template>
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
    <!-- Header -->
    <div class="flex justify-between items-center mb-5">
      <h1 class="text-2xl font-bold text-gray-900">{{ t('dashboard.title') }}</h1>
      <!-- Desktop create button -->
      <router-link
        v-if="authStore.isAdmin"
        to="/create-session"
        class="hidden md:flex items-center gap-2 px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition shadow-sm text-sm font-medium"
      >
        <Plus class="w-4 h-4" />
        {{ t('dashboard.newSession') }}
      </router-link>
    </div>

    <div v-if="authStore.isAdmin" class="mb-4 flex flex-wrap gap-2 items-center">
      <button
        @click="toggleSelectionMode"
        class="px-3 py-1.5 text-sm font-medium rounded-md border transition"
        :class="selectionMode ? 'bg-red-50 text-red-700 border-red-200' : 'bg-white text-gray-700 border-gray-300 hover:border-red-300 hover:text-red-700'"
      >
        {{ selectionMode ? t('dashboard.exitBulkDelete') : t('dashboard.enterBulkDelete') }}
      </button>

      <template v-if="selectionMode">
        <button
          @click="selectAllCancelled"
          class="px-3 py-1.5 text-sm font-medium rounded-md border border-gray-300 bg-white text-gray-700 hover:border-indigo-300 hover:text-indigo-700 transition"
        >
          {{ t('dashboard.selectAllCancelled') }}
        </button>
        <button
          @click="selectedCancelledIds = []"
          class="px-3 py-1.5 text-sm font-medium rounded-md border border-gray-300 bg-white text-gray-700 hover:border-gray-400 transition"
        >
          {{ t('dashboard.clearSelection') }}
        </button>
        <button
          @click="bulkDeleteCancelledSessions"
          :disabled="selectedCancelledIds.length === 0 || bulkDeleting"
          class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-md bg-red-600 text-white hover:bg-red-700 transition disabled:opacity-50"
        >
          <Trash2 class="w-4 h-4" />
          {{ t('dashboard.bulkDeleteAction', { count: selectedCancelledIds.length }) }}
        </button>
        <span class="text-xs text-gray-500">
          {{ t('dashboard.bulkDeleteHint', { count: MAX_BULK_DELETE }) }}
        </span>
      </template>
    </div>

    <!-- Filter pills -->
    <div class="flex gap-2 mb-4 overflow-x-auto pb-1 scrollbar-hide">
      <button
        v-for="opt in filterOptions"
        :key="opt.key"
        @click="statusFilter = opt.key as 'all' | 'open' | 'waiting_for_payment' | 'done' | 'cancelled'"
        class="flex-shrink-0 px-3 py-1 rounded-full text-sm font-medium transition-colors"
        :class="statusFilter === opt.key
          ? 'bg-indigo-600 text-white shadow-sm'
          : 'bg-white border border-gray-200 text-gray-600 hover:border-indigo-300 hover:text-indigo-600'"
      >
        {{ opt.label }}
        <span v-if="opt.key !== 'all'" class="ml-1 opacity-75 text-xs">
          ({{ sessions.filter(s => s.status === opt.key).length }})
        </span>
      </button>
    </div>

    <!-- Skeleton loading -->
    <div v-if="loading" class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <div
        v-for="i in 6"
        :key="i"
        class="bg-white rounded-xl border border-gray-100 border-l-4 border-l-gray-200 p-4 animate-pulse"
      >
        <div class="flex justify-between mb-3">
          <div class="h-5 bg-gray-200 rounded w-2/3" />
          <div class="h-5 bg-gray-100 rounded-full w-16" />
        </div>
        <div class="h-4 bg-gray-100 rounded w-1/2 mb-4" />
        <div class="flex gap-3">
          <div class="h-4 bg-gray-100 rounded w-16" />
          <div class="h-4 bg-gray-100 rounded w-20" />
        </div>
      </div>
    </div>

    <!-- Empty (no sessions at all) -->
    <div
      v-else-if="sessions.length === 0"
      class="text-center py-16 bg-white rounded-xl border border-gray-100"
    >
      <Calendar class="w-12 h-12 text-gray-300 mx-auto mb-3" />
      <p class="text-gray-400 font-medium">{{ t('dashboard.noSessions') }}</p>
    </div>

    <!-- Empty (filter active) -->
    <div
      v-else-if="filteredSessions.length === 0"
      class="text-center py-16 bg-white rounded-xl border border-gray-100"
    >
      <Calendar class="w-12 h-12 text-gray-300 mx-auto mb-3" />
      <p class="text-gray-400 font-medium">{{ t('dashboard.noSessionsFiltered') }}</p>
    </div>

    <!-- Session cards -->
    <div v-else class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <div
        v-for="session in filteredSessions"
        :key="session.id"
        class="block bg-white rounded-xl border border-gray-100 border-l-4 hover:shadow-md active:scale-[0.99] transition-all p-4"
        :class="getStatusBorder(session.status)"
        @click="handleCardClick(session.id)"
      >
        <!-- Title + status badge -->
        <div class="flex justify-between items-start gap-2 mb-1.5">
          <h2 class="text-base font-semibold text-gray-900 leading-snug line-clamp-2">
            {{ session.title }}
          </h2>
          <div class="flex items-center gap-1">
            <button
              v-if="authStore.isAdmin && session.status === 'cancelled'"
              @click.stop="deleteSingleCancelledSession(session.id)"
              class="p-1 rounded-md text-gray-400 hover:text-red-600 hover:bg-red-50 transition"
              :title="t('session.deleteCancelledSession')"
            >
              <Trash2 class="w-4 h-4" />
            </button>
            <button
              v-if="selectionMode && authStore.isAdmin && session.status === 'cancelled'"
              @click.stop="toggleSessionSelection(session.id)"
              class="p-1 rounded-md text-gray-500 hover:text-indigo-600 hover:bg-indigo-50 transition"
              :title="t('dashboard.selectForBulkDelete')"
            >
              <CheckSquare v-if="isSelected(session.id)" class="w-4 h-4 text-indigo-600" />
              <Square v-else class="w-4 h-4" />
            </button>
            <span
              class="flex-shrink-0 px-2 py-0.5 text-xs font-medium rounded-full"
              :class="getStatusColor(session.status)"
            >
              {{ getStatusLabel(session.status) }}
            </span>
          </div>
        </div>

        <!-- Date -->
        <p class="text-sm text-gray-500 mb-3 flex items-center gap-1.5 capitalize">
          <Calendar class="w-3.5 h-3.5 flex-shrink-0" />
          {{ format(new Date(session.session_date), 'EEE, dd/MM/yyyy', { locale: dateLocale }) }}
        </p>

        <!-- Stats row -->
        <div class="flex items-center gap-3 text-xs text-gray-500">
          <span class="flex items-center gap-1">
            <Clock class="w-3.5 h-3.5" />
            {{ session.total_intervals }} {{ t('dashboard.intervals') }}
          </span>
          <span class="flex items-center gap-1">
            <Users class="w-3.5 h-3.5" />
            {{ session.total_registrations }} {{ t('dashboard.registrations') }}
          </span>
          <span class="ml-auto flex items-center gap-1 font-medium text-gray-700">
            {{ formatCurrency(session.total_court_cost + session.shuttle_fee_total) }}
          </span>
        </div>

        <!-- View link — desktop only (whole card is tappable on mobile) -->
        <div class="hidden md:flex items-center mt-3 pt-3 border-t border-gray-50 text-indigo-600 text-xs font-medium">
          {{ t('dashboard.viewDetails') }}
          <ChevronRight class="w-3.5 h-3.5 ml-0.5" />
        </div>
      </div>
    </div>

    <!-- Mobile FAB -->
    <router-link
      v-if="authStore.isAdmin"
      to="/create-session"
      class="md:hidden fixed bottom-20 right-4 z-40 flex items-center justify-center w-14 h-14 bg-indigo-600 text-white rounded-full shadow-lg hover:bg-indigo-700 active:scale-95 transition-all"
      :title="t('dashboard.newSession')"
    >
      <Plus class="w-6 h-6" />
    </router-link>
  </div>
</template>
