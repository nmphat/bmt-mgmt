<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '@/lib/supabase'
import type { SessionSummary } from '@/types'
import {
  Plus,
  ChevronRight,
  Calendar,
  Users,
  Clock,
  Trash2,
  Square,
  CheckSquare,
  Search,
  X,
  SlidersHorizontal,
  ChevronDown,
  ChevronUp,
} from 'lucide-vue-next'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { formatCurrency } from '@/utils/formatters'
import { formatDisplayDate } from '@/utils/dateFormatters'
import { understandSessionQuery } from '@/utils/sessionQueryUnderstanding'
import { useToast } from 'vue-toastification'

const authStore = useAuthStore()
const langStore = useLangStore()
const route = useRoute()
const router = useRouter()
const toast = useToast()

const t = computed(() => langStore.t)
const PAGE_SIZE = 18
const SEARCH_DEBOUNCE_MS = 450
const statusOrder = ['open', 'waiting_for_payment', 'done', 'cancelled'] as const
const GUEST_ALLOWED_STATUSES: Array<SessionSummary['status']> = ['waiting_for_payment', 'done']

const sessions = ref<SessionSummary[]>([])
const loading = ref(true)
const loadingMore = ref(false)
const hasMore = ref(false)
const searchInput = ref('')
const searchKeyword = ref('')
const startDate = ref('')
const endDate = ref('')
const statusFilter = ref<'all' | 'open' | 'waiting_for_payment' | 'done' | 'cancelled'>('all')
type DatePreset = 'all' | 'today' | 'last7' | 'last30' | 'thisMonth' | 'custom'
const datePreset = ref<DatePreset>('all')
const selectionMode = ref(false)
const selectedCancelledIds = ref<string[]>([])
const bulkDeleting = ref(false)
const isMobileFilterOpen = ref(false)
const sentinelRef = ref<HTMLElement | null>(null)
let searchDebounceTimer: ReturnType<typeof setTimeout> | null = null
let observer: IntersectionObserver | null = null
let isHydratingFromRoute = true
const cursor = ref<{ statusRank: number; sessionDate: string; id: string } | null>(null)

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

const cancelledSessions = computed(() => sessions.value.filter((s) => s.status === 'cancelled'))

const activeStatusFilter = computed<'all' | 'open' | 'waiting_for_payment' | 'done' | 'cancelled'>(
  () => {
    const current = statusFilter.value
    if (authStore.isAuthenticated) return current

    if (current === 'open' || current === 'cancelled') {
      return 'all'
    }

    return current
  },
)

const canClearFilters = computed(() => {
  return (
    searchInput.value.trim().length > 0 ||
    startDate.value.length > 0 ||
    endDate.value.length > 0 ||
    activeStatusFilter.value !== 'all'
  )
})

const datePresetOptions = computed<Array<{ key: DatePreset; label: string }>>(() => [
  { key: 'all', label: t.value('dashboard.presetAll') },
  { key: 'today', label: t.value('dashboard.presetToday') },
  { key: 'last7', label: t.value('dashboard.presetLast7') },
  { key: 'last30', label: t.value('dashboard.presetLast30') },
  { key: 'thisMonth', label: t.value('dashboard.presetThisMonth') },
  { key: 'custom', label: t.value('dashboard.presetCustom') },
])

const mobileFilterSummary = computed(() => {
  const parts: string[] = []

  if (activeStatusFilter.value !== 'all') {
    const statusLabel = filterOptions.value.find((f) => f.key === activeStatusFilter.value)?.label
    if (statusLabel) parts.push(statusLabel)
  }

  if (datePreset.value !== 'all') {
    const presetLabel = datePresetOptions.value.find((d) => d.key === datePreset.value)?.label
    if (presetLabel) parts.push(presetLabel)
  }

  if (parts.length === 0) return t.value('dashboard.filterAll')
  return parts.join(' • ')
})

const understoodQuery = computed(() => understandSessionQuery(searchKeyword.value))
const effectiveStartDate = computed(
  () => startDate.value || understoodQuery.value.parsedStartDate || '',
)
const effectiveEndDate = computed(() => endDate.value || understoodQuery.value.parsedEndDate || '')

const filterOptions = computed(() => {
  if (!authStore.isAuthenticated) {
    return [
      { key: 'all', label: t.value('dashboard.filterAll') },
      { key: 'waiting_for_payment', label: t.value('dashboard.filterWaiting') },
      { key: 'done', label: t.value('dashboard.filterDone') },
    ]
  }

  return [
    { key: 'all', label: t.value('dashboard.filterAll') },
    { key: 'open', label: t.value('dashboard.filterOpen') },
    { key: 'waiting_for_payment', label: t.value('dashboard.filterWaiting') },
    { key: 'done', label: t.value('dashboard.filterDone') },
    { key: 'cancelled', label: t.value('dashboard.filterCancelled') },
  ]
})

async function fetchSessions() {
  await fetchSessionsPage(true)
}

function formatDatePart(value: number): string {
  return String(value).padStart(2, '0')
}

function toIsoDate(date: Date): string {
  const year = date.getFullYear()
  const month = formatDatePart(date.getMonth() + 1)
  const day = formatDatePart(date.getDate())
  return `${year}-${month}-${day}`
}

function buildMonthRange(year: number, month: number) {
  const from = `${year}-${formatDatePart(month)}-01`
  const endDate = new Date(year, month, 0)
  const to = `${year}-${formatDatePart(month)}-${formatDatePart(endDate.getDate())}`
  return { from, to }
}

function getAllowedStatusesForCurrentUser(): Array<SessionSummary['status']> {
  return authStore.isAuthenticated ? [...statusOrder] : [...GUEST_ALLOWED_STATUSES]
}

function getStatusFilterForQuery(): Array<SessionSummary['status']> {
  if (activeStatusFilter.value === 'all') return getAllowedStatusesForCurrentUser()
  return [activeStatusFilter.value]
}

function applyDatePreset(preset: DatePreset) {
  datePreset.value = preset

  if (preset === 'custom') return

  const now = new Date()

  if (preset === 'all') {
    startDate.value = ''
    endDate.value = ''
    return
  }

  if (preset === 'today') {
    const iso = toIsoDate(now)
    startDate.value = iso
    endDate.value = iso
    return
  }

  if (preset === 'last7') {
    const end = toIsoDate(now)
    const startDateObj = new Date(now)
    startDateObj.setDate(startDateObj.getDate() - 6)
    startDate.value = toIsoDate(startDateObj)
    endDate.value = end
    return
  }

  if (preset === 'last30') {
    const end = toIsoDate(now)
    const startDateObj = new Date(now)
    startDateObj.setDate(startDateObj.getDate() - 29)
    startDate.value = toIsoDate(startDateObj)
    endDate.value = end
    return
  }

  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1)
  const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0)
  startDate.value = toIsoDate(monthStart)
  endDate.value = toIsoDate(monthEnd)
}

async function fetchSessionsPage(reset: boolean) {
  if (reset) {
    loading.value = true
    cursor.value = null
    sessions.value = []
    hasMore.value = false
  } else {
    if (loadingMore.value || !hasMore.value) return
    loadingMore.value = true
  }

  try {
    const { data, error } = await supabase.rpc('search_sessions_list', {
      p_query: understoodQuery.value.keyword || null,
      p_status: getStatusFilterForQuery(),
      p_start_date: effectiveStartDate.value || null,
      p_end_date: effectiveEndDate.value || null,
      p_limit: PAGE_SIZE,
      p_cursor_status_rank: cursor.value?.statusRank ?? null,
      p_cursor_session_date: cursor.value?.sessionDate ?? null,
      p_cursor_id: cursor.value?.id ?? null,
    })

    if (error) throw error

    const rows = (data || []) as Array<
      SessionSummary & { status_rank: number; session_date: string; id: string }
    >

    if (reset) {
      sessions.value = rows
    } else {
      sessions.value = [...sessions.value, ...rows]
    }

    if (rows.length > 0) {
      const last = rows[rows.length - 1]
      if (!last) return
      cursor.value = {
        statusRank: last.status_rank,
        sessionDate: last.session_date,
        id: last.id,
      }
    }

    hasMore.value = rows.length === PAGE_SIZE
  } catch (error) {
    console.error('Error fetching sessions:', error)
    toast.error(t.value('toast.error', { message: t.value('dashboard.loadError') }))
  } finally {
    loading.value = false
    loadingMore.value = false
  }
}

function handleCardClick(sessionId: string) {
  if (selectionMode.value) return
  router.push(`/session/${sessionId}`)
}

function clearFilters() {
  searchInput.value = ''
  searchKeyword.value = ''
  statusFilter.value = 'all'
  applyDatePreset('all')
}

async function loadMoreSessions() {
  await fetchSessionsPage(false)
}

function hydrateStateFromRoute() {
  const query = route.query
  const q = typeof query.q === 'string' ? query.q : ''
  const from = typeof query.from === 'string' ? query.from : ''
  const to = typeof query.to === 'string' ? query.to : ''
  const status = typeof query.status === 'string' ? query.status : 'all'
  const dp = typeof query.dp === 'string' ? query.dp : ''

  searchInput.value = q
  searchKeyword.value = q
  startDate.value = from
  endDate.value = to

  const validStatuses = ['all', 'open', 'waiting_for_payment', 'done', 'cancelled']
  statusFilter.value = validStatuses.includes(status)
    ? (status as 'all' | 'open' | 'waiting_for_payment' | 'done' | 'cancelled')
    : 'all'

  const validDatePresets: DatePreset[] = ['all', 'today', 'last7', 'last30', 'thisMonth', 'custom']
  if (validDatePresets.includes(dp as DatePreset)) {
    datePreset.value = dp as DatePreset
  } else {
    datePreset.value = from || to ? 'custom' : 'all'
  }

  if (datePreset.value !== 'all' && datePreset.value !== 'custom' && !from && !to) {
    applyDatePreset(datePreset.value)
  }
}

function syncRouteQuery() {
  const nextQuery: Record<string, string> = {}

  if (searchKeyword.value.trim()) nextQuery.q = searchKeyword.value.trim()
  if (activeStatusFilter.value !== 'all') nextQuery.status = activeStatusFilter.value

  if (datePreset.value === 'custom') {
    nextQuery.dp = 'custom'
    if (startDate.value) nextQuery.from = startDate.value
    if (endDate.value) nextQuery.to = endDate.value
  } else if (datePreset.value !== 'all') {
    nextQuery.dp = datePreset.value
  }

  router.replace({ query: nextQuery })
}

function setupInfiniteScroll() {
  if (observer) observer.disconnect()

  observer = new IntersectionObserver(
    (entries) => {
      const first = entries[0]
      if (!first) return
      if (first.isIntersecting && !loading.value && hasMore.value) {
        loadMoreSessions()
      }
    },
    { root: null, rootMargin: '200px 0px', threshold: 0.1 },
  )

  if (sentinelRef.value) {
    observer.observe(sentinelRef.value)
  }
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
  const { data, error } = await supabase.rpc('get_session_delete_impact', {
    p_session_id: sessionId,
  })
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

    const impactList = await Promise.all(
      selectedCancelledIds.value.map((id) => fetchDeleteImpact(id)),
    )
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
    case 'open':
      return 'bg-blue-100 text-blue-800'
    case 'waiting_for_payment':
      return 'bg-orange-100 text-orange-800'
    case 'done':
      return 'bg-green-100 text-green-800'
    case 'cancelled':
      return 'bg-gray-100 text-gray-500'
    default:
      return 'bg-gray-100 text-gray-500'
  }
}

function getStatusBorder(status: string) {
  switch (status) {
    case 'open':
      return 'border-l-blue-400'
    case 'waiting_for_payment':
      return 'border-l-orange-400'
    case 'done':
      return 'border-l-green-400'
    case 'cancelled':
      return 'border-l-gray-300'
    default:
      return 'border-l-gray-200'
  }
}

function getStatusLabel(status: string) {
  return t.value(`common.${status}`)
}

watch(searchInput, (value) => {
  if (searchDebounceTimer) clearTimeout(searchDebounceTimer)
  searchDebounceTimer = setTimeout(() => {
    searchKeyword.value = value.trim()
  }, SEARCH_DEBOUNCE_MS)
})

watch(
  [searchKeyword, startDate, endDate, activeStatusFilter, datePreset],
  async () => {
    if (isHydratingFromRoute) return
    syncRouteQuery()
    await fetchSessionsPage(true)
  },
  { deep: false },
)

watch(
  () => authStore.isAuthenticated,
  async () => {
    if (
      !authStore.isAuthenticated &&
      (statusFilter.value === 'open' || statusFilter.value === 'cancelled')
    ) {
      statusFilter.value = 'all'
      return
    }

    await fetchSessionsPage(true)
  },
)

watch(sentinelRef, () => {
  setupInfiniteScroll()
})

onMounted(async () => {
  hydrateStateFromRoute()
  isHydratingFromRoute = false
  await fetchSessionsPage(true)
  setupInfiniteScroll()
})

onUnmounted(() => {
  if (searchDebounceTimer) clearTimeout(searchDebounceTimer)
  if (observer) observer.disconnect()
})
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
        :class="
          selectionMode
            ? 'bg-red-50 text-red-700 border-red-200'
            : 'bg-white text-gray-700 border-gray-300 hover:border-red-300 hover:text-red-700'
        "
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

    <!-- Filter pills (desktop) -->
    <div class="hidden md:flex gap-2 mb-4 overflow-x-auto pb-1 scrollbar-hide">
      <button
        v-for="opt in filterOptions"
        :key="opt.key"
        @click="
          statusFilter = opt.key as 'all' | 'open' | 'waiting_for_payment' | 'done' | 'cancelled'
        "
        class="flex-shrink-0 px-3 py-1 rounded-full text-sm font-medium transition-colors"
        :class="
          statusFilter === opt.key
            ? 'bg-indigo-600 text-white shadow-sm'
            : 'bg-white border border-gray-200 text-gray-600 hover:border-indigo-300 hover:text-indigo-600'
        "
      >
        {{ opt.label }}
      </button>
    </div>

    <!-- Search + date filters -->
    <div class="mb-5 bg-white border border-gray-100 rounded-xl p-3 sm:p-4">
      <div class="flex items-center gap-2">
        <div class="relative flex-1">
          <Search class="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
          <input
            v-model="searchInput"
            type="text"
            class="w-full rounded-lg border border-gray-200 pl-9 pr-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-200 focus:border-indigo-400"
            :placeholder="t('dashboard.searchPlaceholder')"
          />
        </div>

        <button
          type="button"
          class="md:hidden inline-flex items-center gap-1.5 px-3 py-2 rounded-lg border border-gray-200 text-gray-700 text-sm font-medium"
          @click="isMobileFilterOpen = !isMobileFilterOpen"
        >
          <SlidersHorizontal class="w-4 h-4" />
          {{ t('dashboard.filtersButton') }}
          <ChevronUp v-if="isMobileFilterOpen" class="w-4 h-4" />
          <ChevronDown v-else class="w-4 h-4" />
        </button>
      </div>

      <div class="mt-2 md:hidden text-xs text-gray-500">
        {{ t('dashboard.activeFilters') }}: {{ mobileFilterSummary }}
      </div>

      <div v-if="isMobileFilterOpen" class="md:hidden mt-3 pt-3 border-t border-gray-100 space-y-3">
        <div>
          <p class="text-xs font-medium text-gray-500 mb-2">{{ t('dashboard.datePresets') }}</p>
          <div class="flex gap-2 overflow-x-auto pb-1">
            <button
              v-for="preset in datePresetOptions"
              :key="preset.key"
              type="button"
              @click="applyDatePreset(preset.key)"
              class="flex-shrink-0 px-3 py-1 rounded-full text-xs font-medium border transition-colors"
              :class="
                datePreset === preset.key
                  ? 'bg-indigo-600 text-white border-indigo-600'
                  : 'bg-white text-gray-600 border-gray-200'
              "
            >
              {{ preset.label }}
            </button>
          </div>
        </div>

        <div v-if="datePreset === 'custom'" class="grid grid-cols-2 gap-2">
          <input
            v-model="startDate"
            type="date"
            class="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-200 focus:border-indigo-400"
            :aria-label="t('dashboard.dateFrom')"
          />

          <input
            v-model="endDate"
            type="date"
            class="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-200 focus:border-indigo-400"
            :aria-label="t('dashboard.dateTo')"
          />
        </div>

        <div>
          <p class="text-xs font-medium text-gray-500 mb-2">{{ t('dashboard.statusFilter') }}</p>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="opt in filterOptions"
              :key="`m-${opt.key}`"
              type="button"
              @click="
                statusFilter = opt.key as
                  | 'all'
                  | 'open'
                  | 'waiting_for_payment'
                  | 'done'
                  | 'cancelled'
              "
              class="px-3 py-1 rounded-full text-xs font-medium transition-colors border"
              :class="
                statusFilter === opt.key
                  ? 'bg-indigo-600 text-white border-indigo-600'
                  : 'bg-white border-gray-200 text-gray-600'
              "
            >
              {{ opt.label }}
            </button>
          </div>
        </div>
      </div>

      <div class="hidden md:grid gap-3 md:grid-cols-4 mt-3">
        <div>
          <select
            v-model="datePreset"
            class="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-200 focus:border-indigo-400"
            @change="applyDatePreset(datePreset)"
          >
            <option
              v-for="preset in datePresetOptions"
              :key="`d-${preset.key}`"
              :value="preset.key"
            >
              {{ preset.label }}
            </option>
          </select>
        </div>

        <div v-if="datePreset === 'custom'">
          <input
            v-model="startDate"
            type="date"
            class="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-200 focus:border-indigo-400"
            :aria-label="t('dashboard.dateFrom')"
          />
        </div>

        <div v-if="datePreset === 'custom'">
          <input
            v-model="endDate"
            type="date"
            class="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-200 focus:border-indigo-400"
            :aria-label="t('dashboard.dateTo')"
          />
        </div>
      </div>

      <div class="mt-3 flex items-center justify-between">
        <p class="text-xs text-gray-500">
          {{ t('dashboard.loadedCount', { count: sessions.length }) }}
        </p>
        <button
          v-if="canClearFilters"
          @click="clearFilters"
          class="inline-flex items-center gap-1 text-xs font-medium text-gray-500 hover:text-indigo-600"
        >
          <X class="w-3.5 h-3.5" />
          {{ t('dashboard.clearFilters') }}
        </button>
      </div>
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
      v-else-if="sessions.length === 0 && !canClearFilters"
      class="text-center py-16 bg-white rounded-xl border border-gray-100"
    >
      <Calendar class="w-12 h-12 text-gray-300 mx-auto mb-3" />
      <p class="text-gray-400 font-medium">{{ t('dashboard.noSessions') }}</p>
    </div>

    <!-- Empty (filter active) -->
    <div
      v-else-if="sessions.length === 0"
      class="text-center py-16 bg-white rounded-xl border border-gray-100"
    >
      <Calendar class="w-12 h-12 text-gray-300 mx-auto mb-3" />
      <p class="text-gray-400 font-medium">{{ t('dashboard.noSessionsFiltered') }}</p>
    </div>

    <!-- Session cards -->
    <div v-else class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <div
        v-for="session in sessions"
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
          {{ formatDisplayDate(session.session_date, langStore.currentLang) }}
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
        <div
          class="hidden md:flex items-center mt-3 pt-3 border-t border-gray-50 text-indigo-600 text-xs font-medium"
        >
          {{ t('dashboard.viewDetails') }}
          <ChevronRight class="w-3.5 h-3.5 ml-0.5" />
        </div>
      </div>
    </div>

    <div ref="sentinelRef" class="h-10 flex items-center justify-center">
      <div v-if="loadingMore" class="text-sm text-gray-500">{{ t('common.loading') }}</div>
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
