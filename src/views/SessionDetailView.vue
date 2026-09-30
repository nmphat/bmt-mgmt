<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed, nextTick, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '@/lib/supabase'
import type {
  SessionSummary,
  Interval,
  SessionRegistration,
  MemberCost,
  Member,
  GroupPaymentData,
  CourtBooking,
  CourtBookingDraft,
} from '@/types'
import { format } from 'date-fns'
import { vi, enUS } from 'date-fns/locale'
import { useLangStore } from '@/stores/lang'
import {
  AlertTriangle,
  ChevronDown,
  ChevronLeft,
  ChevronUp,
  RefreshCcw,
  UserX,
  UserPlus,
  Trash2,
  X,
  Edit,
  Save,
  Lock,
  CreditCard,
  QrCode,
  Check,
} from 'lucide-vue-next'
import Alert from '@/components/ui/Alert.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import FormField from '@/components/ui/FormField.vue'
import IconButton from '@/components/ui/IconButton.vue'
import Input from '@/components/ui/Input.vue'
import SectionHeader from '@/components/ui/SectionHeader.vue'
import Select from '@/components/ui/Select.vue'
import SessionStatusBadge from '@/components/ui/SessionStatusBadge.vue'
import StatusIcon from '@/components/ui/StatusIcon.vue'
import Spinner from '@/components/ui/Spinner.vue'
import TableHeaderCell from '@/components/ui/TableHeaderCell.vue'
import PaymentQRModal from '@/components/PaymentQRModal.vue'
import ManualPaymentModal from '@/components/ManualPaymentModal.vue'
import SessionExtraCharges from '@/components/SessionExtraCharges.vue'
import CourtBookingEditor from '@/components/session/CourtBookingEditor.vue'
import ShuttleUsageEditor from '@/components/session/ShuttleUsageEditor.vue'
import { useAuthStore } from '@/stores/auth'
import type { RealtimeChannel } from '@supabase/supabase-js'
import { useToast } from 'vue-toastification'
import type { CostSnapshot } from '@/types'

const route = useRoute()
const router = useRouter()
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
const extraChargesRef = ref<InstanceType<typeof SessionExtraCharges> | null>(null)
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
const pageError = ref('')
const paymentDataError = ref('')
const actionError = ref('')

type SessionSectionId =
  | 'overview-section'
  | 'attendance-section'
  | 'costs-section'
  | 'payments-section'

const getDefaultActiveSection = (status?: string): SessionSectionId => {
  if (status === 'open') return 'attendance-section'
  if (status === 'waiting_for_payment' || status === 'done') return 'payments-section'
  return 'overview-section'
}

const sectionTabs = computed<{ id: SessionSectionId; label: string; ariaLabel: string }[]>(() => [
  {
    id: 'overview-section',
    label: t.value('session.overview'),
    ariaLabel: t.value('session.overview'),
  },
  {
    id: 'attendance-section',
    label: t.value('session.attendance'),
    ariaLabel: t.value('session.attendance'),
  },
  { id: 'costs-section', label: t.value('session.costs'), ariaLabel: t.value('session.costs') },
  {
    id: 'payments-section',
    label: t.value('session.payments'),
    ariaLabel: t.value('session.payments'),
  },
])

function scrollActiveTabIntoView(sectionId: string) {
  document
    .querySelector(`[data-tab-id="${sectionId}"]`)
    ?.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' })
}

watch(activeSection, (sectionId) => {
  nextTick(() => scrollActiveTabIntoView(sectionId))
})

function scrollToSection(sectionId: SessionSectionId) {
  activeSection.value = sectionId
  document.getElementById(sectionId)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}

let sectionObserver: IntersectionObserver | null = null

function setupSectionObserver() {
  sectionObserver?.disconnect()

  const ids: SessionSectionId[] = [
    'overview-section',
    'attendance-section',
    'costs-section',
    'payments-section',
  ]
  const elements = ids
    .map((id) => document.getElementById(id))
    .filter((el): el is HTMLElement => el !== null)
  if (elements.length === 0) return

  // Detection band: below the sticky header, upper half of the remaining
  // viewport. When two sections both straddle the band (tail of one, head
  // of the next), the one with the LARGEST top is the one that just started
  // and is actually occupying the top of the screen right now.
  sectionObserver = new IntersectionObserver(
    (entries) => {
      const visible = entries.filter((entry) => entry.isIntersecting)
      if (visible.length === 0) return
      const current = visible.reduce((a, b) =>
        a.boundingClientRect.top >= b.boundingClientRect.top ? a : b,
      )
      const id = current.target.id as SessionSectionId
      if (id !== activeSection.value) {
        activeSection.value = id
      }
    },
    { rootMargin: '-60px 0px -80% 0px', threshold: 0 },
  )
  elements.forEach((el) => sectionObserver!.observe(el))
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

type SessionSummaryResponse = Omit<
  SessionSummary,
  'court_fee_total' | 'shuttle_fee_total' | 'total_intervals' | 'total_registrations'
> & {
  court_fee_total?: number | string | null
  total_court_cost?: number | string | null
  shuttle_fee_total?: number | string | null
  total_intervals?: number | string | null
  total_registrations?: number | string | null
}

const toNumber = (value: unknown) => {
  const numericValue = typeof value === 'string' && value.trim() === '' ? NaN : Number(value)
  return Number.isFinite(numericValue) ? numericValue : 0
}

const normalizeSessionSummary = (row: SessionSummaryResponse): SessionSummary => ({
  ...row,
  court_fee_total: toNumber(row.court_fee_total ?? row.total_court_cost),
  shuttle_fee_total: toNumber(row.shuttle_fee_total),
  total_intervals: toNumber(row.total_intervals),
  total_registrations: toNumber(row.total_registrations),
})

const sessionForm = ref({
  title: '',
  status: 'open' as 'open' | 'waiting_for_payment' | 'done' | 'cancelled',
  court_fee_addon: 0,
  session_start: '',
  session_end: '',
})
// Default price seeded onto newly added court slots — not written back to
// sessions.price_per_hour, which the cost engine only uses as a legacy
// fallback for sessions with no priced bookings.
const defaultCourtPrice = ref(0)
const courtBookings = ref<CourtBooking[]>([])
const courtBookingDrafts = ref<CourtBookingDraft[]>([])
const bookingsValid = ref(true)
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
    paymentDataError.value = ''
    if (!refreshCostsOnly) {
      loading.value = true
      pageError.value = ''
      actionError.value = ''
    }

    // Fetch session summary (Always fetch this now to detect status changes)
    const { data: sessionData, error: sessionError } = await supabase
      .from('view_session_summary')
      .select('*')
      .eq('id', sessionId)
      .single()

    if (sessionError) throw sessionError
    const normalizedSession = normalizeSessionSummary(sessionData)
    session.value = normalizedSession

    if (lastStatusForActiveSection.value === null) {
      // First load: the page renders at the top (overview), so don't jump the
      // tab highlight away from what's actually on screen. Only later live
      // status changes (e.g. admin finalizes while member is viewing) should
      // nudge the active tab.
      lastStatusForActiveSection.value = normalizedSession.status
    } else if (lastStatusForActiveSection.value !== normalizedSession.status) {
      activeSection.value = getDefaultActiveSection(normalizedSession.status)
      lastStatusForActiveSection.value = normalizedSession.status
    }

    // Leave the open edit form alone: realtime refreshes and the shuttle
    // editor's @saved both call fetchData() and must not clobber unsaved edits.
    if (normalizedSession && !isEditingSession.value) {
      sessionForm.value = {
        title: normalizedSession.title,
        status: normalizedSession.status,
        court_fee_addon: normalizedSession.court_fee_addon,
        session_start: '',
        session_end: '',
      }
      defaultCourtPrice.value = normalizedSession.price_per_hour
    }

    if (!refreshCostsOnly) {
      // Fetch intervals
      const { data: intervalsData, error: intervalsError } = await supabase
        .from('session_intervals')
        .select('*')
        .eq('session_id', sessionId)
        .order('idx', { ascending: true })
      if (intervalsError) throw intervalsError
      intervals.value = intervalsData || []

      // Fetch all members for registration dropdown
      const { data: membersData, error: membersError } = await supabase
        .from('members')
        .select('*')
        .order('display_name', { ascending: true })
      if (membersError) throw membersError
      allMembers.value = membersData || []

      // Fetch court bookings
      const { data: bookingsData, error: bookingsError } = await supabase
        .from('session_court_bookings')
        .select('*')
        .eq('session_id', sessionId)
        .order('court_name', { ascending: true })
        .order('start_time', { ascending: true })
      if (bookingsError) throw bookingsError
      courtBookings.value = bookingsData || []

      // Fetch shuttle_usage (not in view_session_summary)
      const { data: sessionRow, error: sessionRowErr } = await supabase
        .from('sessions')
        .select('shuttle_usage')
        .eq('id', sessionId)
        .single()
      if (sessionRowErr) throw sessionRowErr
      if (session.value && sessionRow) {
        session.value.shuttle_usage = sessionRow.shuttle_usage || []
      }
    }

    // Fetch registrations (with member details)
    const { data: regsData, error: regsError } = await supabase
      .from('session_registrations')
      .select('*, member:members(*)')
      .eq('session_id', sessionId)
    if (regsError) throw regsError

    const sortedRegs = (regsData || []) as SessionRegistration[]
    sortedRegs.sort((a, b) =>
      (a.member?.display_name || '').localeCompare(b.member?.display_name || '', 'vi'),
    )
    registrations.value = sortedRegs

    // Fetch presence
    const { data: presenceData, error: presenceError } = await supabase
      .from('interval_presence')
      .select('*')
      .in(
        'interval_id',
        intervals.value.map((i) => i.id),
      )
    if (presenceError) throw presenceError

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
  } catch (error: unknown) {
    console.error('Error fetching session details:', error)
    const message = t.value('session.dataLoadError')
    pageError.value = message
    if (!refreshCostsOnly) toast.error(message)
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
    paymentDataError.value = t.value('session.paymentDataLoadError')
    return
  }

  const sortedSnapshots = (data || []).map((s: any) => ({
    ...s,
    display_name: s.member?.display_name || t.value('common.unknown'), // Need to add 'unknown' to messages.ts
  })) as (CostSnapshot & { display_name: string })[]
  sortedSnapshots.sort((a, b) => a.display_name.localeCompare(b.display_name, 'vi'))
  snapshots.value = sortedSnapshots
  snapshots.value = sortedSnapshots
}

async function finalizeSession() {
  if (!isSessionEditable.value) return
  if (!session.value) return
  if (!confirm(t.value('session.finalizeConfirm'))) return

  try {
    finalizeLoading.value = true
    actionError.value = ''
    const { error } = await supabase.rpc('finalize_session', { p_session_id: sessionId })

    if (error) throw error

    toast.success(t.value('toast.sessionFinalized'))
    await fetchData()
  } catch (error: any) {
    console.error('Error finalizing session:', error)
    const message = t.value('session.finalizeError')
    actionError.value = message
    toast.error(message)
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
    actionError.value = ''
    const { error } = await supabase
      .from('sessions')
      .update({ status: 'cancelled' })
      .eq('id', sessionId)

    if (error) throw error
    toast.success(t.value('toast.sessionCancelled'))
    await fetchData()
  } catch (error: any) {
    console.error('Error cancelling session:', error)
    const message = t.value('session.cancelError')
    actionError.value = message
    toast.error(message)
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

/** Convert ISO UTC string → "HH:mm" in Vietnam timezone (UTC+7) */
function toVNHHmm(iso: string): string {
  const vnMs = new Date(iso).getTime() + 7 * 3600 * 1000
  return new Date(vnMs).toISOString().slice(11, 16)
}

function startEditing() {
  if (!session.value) return
  isEditingSession.value = true
  sessionForm.value.session_start = toVNHHmm(session.value.start_time)
  sessionForm.value.session_end = toVNHHmm(session.value.end_time)
  courtBookingDrafts.value = courtBookings.value.map((b) => ({
    id: b.id,
    court_name: b.court_name,
    start_time: toVNHHmm(b.start_time),
    end_time: toVNHHmm(b.end_time),
    price_per_hour: b.price_per_hour ?? 0,
  }))
  // Old sessions with no court bookings: seed one slot covering the whole session.
  if (courtBookingDrafts.value.length === 0) {
    courtBookingDrafts.value = [
      {
        court_name: 'Sân 1',
        start_time: sessionForm.value.session_start,
        end_time: sessionForm.value.session_end,
        price_per_hour: defaultCourtPrice.value ?? 0,
      },
    ]
  }
}

const sessionTimeInvalid = computed(() => {
  return (
    !!sessionForm.value.session_start &&
    !!sessionForm.value.session_end &&
    sessionForm.value.session_start >= sessionForm.value.session_end
  )
})

const timesChanged = computed(() => {
  if (!session.value) return false
  return (
    sessionForm.value.session_start !== toVNHHmm(session.value.start_time) ||
    sessionForm.value.session_end !== toVNHHmm(session.value.end_time)
  )
})

async function saveSession() {
  if (!isSessionEditable.value) return

  try {
    isSavingSession.value = true
    actionError.value = ''

    // Compute UTC start/end from VN HH:mm — use separate dates so cross-midnight works
    const vnDate = (iso: string) =>
      new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Ho_Chi_Minh' }).format(new Date(iso))
    const startDate = vnDate(session.value!.start_time)
    const endDate = vnDate(session.value!.end_time)
    const newStartUTC = new Date(`${startDate}T${sessionForm.value.session_start}:00+07:00`)
    const newEndUTC = new Date(`${endDate}T${sessionForm.value.session_end}:00+07:00`)

    if (newEndUTC <= newStartUTC) {
      toast.error(t.value('createSession.endTimeError'))
      return
    }

    // One transaction: admin check, interval rebuild (only if times changed),
    // court bookings, and the session row itself. Replaces the old three
    // sequential calls, which could leave attendance wiped and the rest of
    // the edit abandoned if a later step failed.
    const { error } = await supabase.rpc('update_session_details', {
      p_session_id: sessionId,
      p_title: sessionForm.value.title,
      p_status: sessionForm.value.status,
      p_court_fee_addon: sessionForm.value.court_fee_addon,
      p_start_time: newStartUTC.toISOString(),
      p_end_time: newEndUTC.toISOString(),
      p_bookings: courtBookingDrafts.value.map((b) => ({
        court_name: b.court_name,
        start_time: new Date(`${startDate}T${b.start_time}:00+07:00`).toISOString(),
        end_time: new Date(`${endDate}T${b.end_time}:00+07:00`).toISOString(),
        price_per_hour: b.price_per_hour,
      })),
    })
    if (error) throw error

    toast.success(t.value('toast.sessionUpdated'))
    isEditingSession.value = false
    await fetchData()
  } catch (error: any) {
    console.error('Error updating session:', error)
    const message = error.message || t.value('session.updateError')
    actionError.value = message
    toast.error(message)
  } finally {
    isSavingSession.value = false
  }
}

async function registerMembers() {
  if (!isSessionEditable.value) return
  if (selectedMemberIds.value.length === 0) return

  try {
    isRegistering.value = true
    actionError.value = ''

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
      actionError.value = t.value('toast.registrationPartialFailure')
      toast.error(t.value('toast.registrationPartialFailure'))
    } else {
      toast.success(t.value('toast.memberRegistered', { count: selectedMemberIds.value.length }))
    }

    selectedMemberIds.value = []
    showMemberDropdown.value = false
    await fetchData(true)
  } catch (error: any) {
    const message = t.value('session.registerError')
    actionError.value = message
    toast.error(message)
  } finally {
    isRegistering.value = false
  }
}

async function removeRegistration(regId: string, name: string, memberId?: string) {
  if (!isSessionEditable.value) return
  if (!confirm(t.value('session.removeConfirm', { name }))) return

  try {
    actionError.value = ''

    if (memberId) {
      // Use RPC to clean up all related data (presence, charges, snapshots, registration)
      const { error } = await supabase.rpc('remove_member_from_session', {
        p_session_id: sessionId,
        p_member_id: memberId,
      })
      if (error) throw error
    } else {
      // Fallback: direct delete if memberId not available
      const { error } = await supabase.from('session_registrations').delete().eq('id', regId)
      if (error) throw error
    }

    toast.success(t.value('toast.registrationRemoved'))
    await fetchData(true)
  } catch (error: any) {
    const message = t.value('session.removeError')
    actionError.value = message
    toast.error(message)
  }
}

async function fetchCosts() {
  const { data, error } = await supabase.rpc('calculate_session_costs', { p_session_id: sessionId })
  if (error) {
    console.error('Error fetching costs:', error)
    paymentDataError.value = t.value('session.paymentDataLoadError')
    return
  }
  const sortedCosts = [...(data || [])] as MemberCost[]
  sortedCosts.sort((a, b) => a.display_name.localeCompare(b.display_name, 'vi'))
  costs.value = sortedCosts
}

function handleExtraChargesChanged() {
  fetchCosts()
}

async function togglePresence(memberId: string, intervalId: string) {
  if (!isSessionEditable.value) return

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
    const message = t.value('session.presenceUpdateError')
    actionError.value = message
    toast.error(message)
  } else {
    actionError.value = ''
    // Recalculate costs is handled by realtime subscription or manual refresh,
    // but to be snappy we can call it here too.
    // However, let's rely on the method called after fetch or realtime for now to avoid race conditions.
    // Actually, calling fetchCosts here ensures the user sees the price update immediately after their action.
    await fetchCosts()
  }
}

async function toggleAbsent(reg: SessionRegistration) {
  if (!isSessionEditable.value) return

  const previousPresence = { ...(presence.value[reg.member_id] ?? {}) }
  const rows = intervals.value.map((interval) => ({
    interval_id: interval.id,
    member_id: reg.member_id,
    is_present: false,
  }))

  if (presence.value[reg.member_id]) {
    for (const interval of intervals.value) {
      presence.value[reg.member_id]![interval.id] = false
    }
  }

  const { error } =
    rows.length > 0
      ? await supabase
          .from('interval_presence')
          .upsert(rows, { onConflict: 'interval_id, member_id' })
      : { error: null }

  if (error) {
    presence.value[reg.member_id] = previousPresence
    console.error('Error updating status:', error)
    const message = t.value('session.absentUpdateError')
    actionError.value = message
    toast.error(message)
  } else {
    actionError.value = ''
    await fetchCosts()
  }
}

const formatCurrency = (value: unknown) => {
  const formatter = currencyFormatters[langStore.currentLang] || currencyFormatters.vi
  return formatter!.format(toNumber(value))
}

const formatTime = (isoString: string) => {
  return format(new Date(isoString), 'HH:mm')
}

const presentIntervalCount = (memberId: string) => {
  return Object.values(presence.value[memberId] || {}).filter(Boolean).length
}

const isRegistrationAbsent = (reg: SessionRegistration) =>
  intervals.value.length > 0 && presentIntervalCount(reg.member_id) === 0

const formatSessionDate = (isoString: string) => {
  return format(new Date(isoString), 'EEEE, dd/MM/yyyy', { locale: dateLocale.value })
}

const STATUS_DS = {
  open: 'Open',
  waiting_for_payment: 'Waiting For Payment',
  done: 'Done',
  cancelled: 'Cancelled',
} as const
const dsStatus = (s: string) => STATUS_DS[s as keyof typeof STATUS_DS] ?? 'Cancelled'

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
  // Exclude extra charges — they are designated expenses/refunds, not surplus
  const totalExtra = costs.value.reduce((sum, c) => sum + c.total_extra_fee, 0)
  const totalCost =
    toNumber(session.value.court_fee_total) + toNumber(session.value.shuttle_fee_total)

  return totalCollected - totalExtra - totalCost
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
    actionError.value = ''
    const { data, error } = await supabase.rpc('create_group_payment', {
      p_snapshot_ids: selectedSnapshotIds.value,
    })

    if (error) throw error

    groupPaymentData.value = {
      group_code: data.group_code,
      total_amount: data.total_amount,
      snapshot_ids: [...selectedSnapshotIds.value],
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
    const message = t.value('session.groupPaymentError')
    actionError.value = message
    toast.error(message)
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
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'session_extra_charges',
        filter: `session_id=eq.${sessionId}`,
      },
      () => {
        extraChargesRef.value?.fetchCharges()
        fetchCosts()
      },
    )
    .subscribe()
}

onMounted(async () => {
  await fetchData()
  await nextTick()
  setupSectionObserver()

  // Auto-open member dropdown when navigating from create-session
  if (route.query.register === 'true' && session.value?.status === 'open' && authStore.isAdmin) {
    showMemberDropdown.value = true
  }
  // Strip query param to clean URL
  if (route.query.register) {
    router.replace({ name: route.name as string, params: route.params })
  }

  initRealtime()
  document.addEventListener('click', handleClickOutside)
  startPolling()
})

onUnmounted(() => {
  stopPolling()
  document.removeEventListener('click', handleClickOutside)
  sectionObserver?.disconnect()
  if (realtimeChannel) {
    supabase.removeChannel(realtimeChannel)
  }
})
</script>

<template>
  <div class="session-detail-shell mx-auto max-w-full px-4 py-4 sm:px-6 md:py-6 lg:px-8">
    <div v-if="loading && !session" class="flex justify-center py-12">
      <Spinner size="48" />
    </div>

    <Alert v-else-if="pageError" tone="Danger" aria-live="polite">
      <p class="font-bold">{{ pageError }}</p>
      <template #action>
        <Button size="Default" variant="Outline Danger" @click="() => fetchData()">
          {{ t('session.refreshSession') }}
        </Button>
      </template>
    </Alert>

    <div v-else-if="session" class="space-y-4">
      <Alert v-if="pageError || actionError || paymentDataError" tone="Danger" aria-live="polite">
        <p v-if="pageError" class="font-bold">{{ pageError }}</p>
        <p v-if="actionError" class="font-bold">{{ actionError }}</p>
        <p v-if="paymentDataError" class="font-bold">{{ paymentDataError }}</p>
        <template #action>
          <Button size="Default" variant="Outline Danger" @click="() => fetchData()">
            {{ t('session.refreshSession') }}
          </Button>
        </template>
      </Alert>

      <section
        id="overview-section"
        data-ds="Session Overview Section"
        class="session-scroll-target flex flex-col gap-5 rounded-xl border border-line-divider bg-surface-card p-4 shadow-sm md:p-6"
      >
        <div class="flex items-center justify-between gap-3">
          <Button
            size="Default"
            variant="Ghost"
            :leading-icon="ChevronLeft"
            @click="$router.back()"
          >
            {{ t('common.back') }}
          </Button>
          <IconButton
            size="Default"
            shape="Square"
            variant="Outline"
            :icon="RefreshCcw"
            :label="t('session.refreshSession')"
            :title="t('session.refreshSession')"
            :loading="loading"
            @click="() => fetchData()"
          />
        </div>

        <!-- Edit Mode -->
        <div v-if="isEditingSession && authStore.isAdmin" class="flex flex-col gap-4">
          <div class="flex items-center justify-between">
            <h2 class="text-xl font-bold text-fg-primary">
              {{ t('session.editSession') }}
            </h2>
            <IconButton
              size="Default"
              shape="Square"
              variant="Ghost"
              :icon="X"
              :label="t('common.cancel')"
              @click="isEditingSession = false"
            />
          </div>
          <div class="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-4">
            <FormField :label="t('session.title')" v-slot="{ controlProps }">
              <Input v-model="sessionForm.title" v-bind="controlProps" size="Default" type="text" />
            </FormField>
            <FormField control="Select" :label="t('common.status')" v-slot="{ controlProps }">
              <Select v-model="sessionForm.status" v-bind="controlProps" size="Default">
                <option value="open">{{ t('common.open') }}</option>
                <option value="waiting_for_payment">{{ t('common.waiting_for_payment') }}</option>
                <option value="done">{{ t('common.done') }}</option>
                <option value="cancelled">{{ t('common.cancelled') }}</option>
              </Select>
            </FormField>
            <FormField :label="t('createSession.startTime')" v-slot="{ controlProps }">
              <Input
                v-model="sessionForm.session_start"
                v-bind="controlProps"
                size="Default"
                type="time"
              />
            </FormField>
            <FormField :label="t('createSession.endTime')" message-tone="Error">
              <template #default="{ controlProps }">
                <Input
                  v-model="sessionForm.session_end"
                  v-bind="controlProps"
                  size="Default"
                  type="time"
                />
              </template>
              <template v-if="sessionTimeInvalid" #message>
                {{ t('createSession.endTimeError') }}
              </template>
            </FormField>
          </div>
          <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
            <FormField :label="t('session.courtFeeAddon')" v-slot="{ controlProps }">
              <Input
                v-model.number="sessionForm.court_fee_addon"
                v-bind="controlProps"
                size="Default"
                type="number"
                step="1000"
              />
            </FormField>
            <FormField :label="t('session.defaultCourtPrice')" v-slot="{ controlProps }">
              <Input
                v-model.number="defaultCourtPrice"
                v-bind="controlProps"
                size="Default"
                type="number"
                step="1000"
              />
            </FormField>
          </div>
          <Alert v-if="timesChanged" tone="Danger" :icon="AlertTriangle">
            {{ t('session.intervalsResetWarning') }}
          </Alert>
          <CourtBookingEditor
            v-model:bookings="courtBookingDrafts"
            :session-start="sessionForm.session_start"
            :session-end="sessionForm.session_end"
            :default-price="defaultCourtPrice"
            @update:valid="bookingsValid = $event"
          />
          <div class="flex justify-end gap-3 border-t border-line-divider pt-4">
            <Button size="Default" variant="Secondary" @click="isEditingSession = false">
              {{ t('common.cancel') }}
            </Button>
            <Button
              size="Default"
              variant="Primary"
              :leading-icon="Save"
              :loading="isSavingSession"
              :disabled="isSavingSession || !bookingsValid || sessionTimeInvalid"
              @click="saveSession"
            >
              {{ t('common.save') }}
            </Button>
          </div>
        </div>

        <!-- View Mode -->
        <div v-else class="flex flex-col gap-5">
          <div class="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
            <div class="flex min-w-0 flex-col gap-2">
              <div class="flex items-start gap-3">
                <h1 class="text-xl font-bold text-fg-primary">
                  {{ session.title }}
                </h1>
                <IconButton
                  v-if="isSessionEditable"
                  size="Default"
                  shape="Square"
                  variant="Ghost"
                  :icon="Edit"
                  :label="t('session.editSession')"
                  :title="t('session.editSession')"
                  @click="startEditing"
                />
              </div>
              <p class="text-sm capitalize text-fg-secondary">
                {{ formatSessionDate(session.session_date) }}
                <span v-if="sessionTimeRange"> · {{ sessionTimeRange }}</span>
              </p>
            </div>

            <SessionStatusBadge :status="dsStatus(session.status)" />
          </div>

          <div class="flex flex-col gap-3 md:flex-row">
            <div
              data-ds="Stat Tile"
              data-ds-tone="Neutral"
              class="flex flex-col gap-1 rounded-xl bg-surface-subtle p-3 md:flex-1"
            >
              <span class="text-sm font-bold text-fg-muted">{{ t('session.courtFee') }}</span>
              <span class="text-base font-bold text-fg-primary">{{
                formatCurrency(session.court_fee_total)
              }}</span>
            </div>
            <div
              data-ds="Stat Tile"
              data-ds-tone="Neutral"
              class="flex flex-col gap-1 rounded-xl bg-surface-subtle p-3 md:flex-1"
            >
              <span class="text-sm font-bold text-fg-muted">{{ t('session.shuttleFee') }}</span>
              <span class="text-base font-bold text-fg-primary">{{
                formatCurrency(session.shuttle_fee_total)
              }}</span>
            </div>
            <div
              v-if="session.status === 'waiting_for_payment' || session.status === 'done'"
              data-ds="Stat Tile"
              data-ds-tone="Brand"
              class="flex flex-col gap-1 rounded-xl bg-surface-brand-subtle p-3 md:flex-1"
            >
              <span class="text-sm font-bold text-fg-brand-strong">{{
                t('session.totalCollected')
              }}</span>
              <span class="text-base font-bold text-fg-brand-strong">{{
                formatCurrency(totalCollected)
              }}</span>
            </div>
          </div>

          <Alert v-if="overviewMessage" tone="Neutral">{{ overviewMessage }}</Alert>

          <div v-if="isSessionEditable" class="flex flex-col gap-2 md:flex-row md:justify-end">
            <Button size="Default" variant="Secondary" @click="cancelSession">
              {{ t('session.cancelSession') }}
            </Button>
            <Button
              size="Default"
              variant="Primary"
              :leading-icon="Lock"
              :loading="finalizeLoading"
              :disabled="finalizeLoading"
              @click="finalizeSession"
            >
              {{ t('session.finalize') }}
            </Button>
          </div>
        </div>
      </section>

      <!-- Cancelled Banner -->
      <Alert v-if="isSessionCancelled" tone="Neutral" variant="Banner" :icon="X" class="mb-8">
        {{ t('session.cancelledMessage') }}
      </Alert>

      <!-- Attendance -->
      <section
        id="attendance-section"
        class="session-scroll-target rounded-xl border border-line-divider bg-surface-card shadow-sm"
      >
        <SectionHeader variant="Tinted" :title="t('session.attendance')">
          <template #badge>
            <Badge v-if="attendanceLockMessage" tone="Neutral" :icon="Lock">
              {{ t('session.lockedStatusLabel') }}
            </Badge>
          </template>
        </SectionHeader>

        <!-- Add Members to Session -->
        <div class="border-b border-line-divider p-4 sm:p-6">
          <div
            v-if="isSessionEditable"
            data-ds="Add Members Panel"
            class="flex flex-col gap-3 rounded-xl border border-line-brand-muted bg-surface-brand-subtle p-4"
            ref="dropdownRef"
          >
            <div class="flex items-center gap-2">
              <UserPlus class="size-5 text-fg-brand" aria-hidden="true" />
              <h3 class="text-base font-bold text-fg-primary">
                {{ t('session.addMembersTitle') }}
              </h3>
            </div>
            <div class="flex w-full flex-col gap-3 sm:flex-row sm:items-start">
              <div class="relative w-full sm:w-80">
                <button
                  type="button"
                  data-ds="Select Trigger"
                  :data-ds-content="selectedMemberIds.length === 0 ? 'Placeholder' : 'Selected'"
                  :data-ds-open="String(showMemberDropdown)"
                  :aria-expanded="showMemberDropdown"
                  @click="showMemberDropdown = !showMemberDropdown"
                  class="flex h-control-md w-full cursor-pointer items-center justify-between rounded-control border border-line-input bg-surface-card px-4 text-left text-sm shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-line-focus focus-visible:ring-offset-2 sm:w-80"
                >
                  <span v-if="selectedMemberIds.length === 0" class="text-fg-muted">{{
                    t('session.selectMembers')
                  }}</span>
                  <span v-else class="font-bold text-fg-primary">{{
                    t('session.selectedCount', { count: selectedMemberIds.length })
                  }}</span>
                  <ChevronUp v-if="showMemberDropdown" class="size-4 text-fg-disabled" />
                  <ChevronDown v-else class="size-4 text-fg-disabled" />
                </button>
                <!-- Custom Checkbox Dropdown -->
                <div
                  v-if="showMemberDropdown"
                  data-ds="Multi-select Menu"
                  :data-ds-content="availableMembers.length === 0 ? 'Empty' : 'Options'"
                  class="absolute z-[60] left-0 right-0 mt-2 max-h-60 overflow-y-auto rounded-xl border border-line-divider bg-surface-card shadow-lg animate-in fade-in zoom-in-95 duration-100"
                >
                  <EmptyState v-if="availableMembers.length === 0" variant="Plain" align="Center">
                    {{ t('session.noMoreMembers') }}
                  </EmptyState>
                  <label
                    v-for="m in availableMembers"
                    :key="m.id"
                    data-ds="Checkbox Field"
                    data-ds-style="Option"
                    :data-ds-checked="String(selectedMemberIds.includes(m.id))"
                    class="flex h-11 cursor-pointer select-none items-center gap-3 px-3 hover:bg-surface-brand-subtle"
                  >
                    <Checkbox size="20" :value="m.id" v-model="selectedMemberIds" />
                    <span class="text-base text-fg-secondary">{{ m.display_name }}</span>
                  </label>
                </div>
              </div>
              <Button
                size="Default"
                variant="Primary"
                :leading-icon="UserPlus"
                :loading="isRegistering"
                :disabled="selectedMemberIds.length === 0 || isRegistering"
                @click="registerMembers"
              >
                {{ isRegistering ? t('common.loading') : t('session.register') }}
              </Button>
            </div>
          </div>
        </div>
        <div class="space-y-4 p-4 md:hidden">
          <EmptyState
            v-if="registrations.length === 0"
            variant="Dashed Muted"
            align="Center"
            size="Small"
          >
            {{ t('session.noRegisteredMembers') }}
          </EmptyState>
          <article
            v-for="reg in registrations"
            :key="reg.id"
            data-ds="Registration Card"
            :data-ds-absent="String(isRegistrationAbsent(reg))"
            :data-ds-editable="String(isSessionEditable)"
            class="flex flex-col gap-4 rounded-xl border border-line-divider p-4 shadow-sm"
            :class="isRegistrationAbsent(reg) ? 'bg-surface-subtle opacity-90' : 'bg-surface-card'"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="flex flex-col gap-1">
                <h3 class="text-base font-bold text-fg-primary">
                  {{ reg.member?.display_name }}
                </h3>
                <p class="flex gap-1 text-sm text-fg-secondary">
                  {{ t('session.presentIntervals') }}:
                  <span class="tabular-nums text-fg-primary">
                    {{ presentIntervalCount(reg.member_id) }}/{{ intervals.length }}
                  </span>
                </p>
              </div>
              <Badge v-if="isRegistrationAbsent(reg)" tone="Danger">
                {{ t('session.absent') }}
              </Badge>
            </div>

            <Alert
              v-if="isRegistrationAbsent(reg) || attendanceLockMessage"
              tone="Neutral"
              :icon="Lock"
            >
              {{ isRegistrationAbsent(reg) ? t('session.absent') : t('session.lockedStatusLabel') }}
            </Alert>

            <div v-if="isSessionEditable" class="grid grid-cols-2 gap-2">
              <Button
                size="Default"
                :variant="isRegistrationAbsent(reg) ? 'Outline Danger' : 'Secondary'"
                :pressed="isRegistrationAbsent(reg)"
                :leading-icon="UserX"
                :aria-pressed="isRegistrationAbsent(reg) ? 'true' : 'false'"
                @click="toggleAbsent(reg)"
              >
                {{ t('session.markAbsent') }}
              </Button>
              <Button
                size="Default"
                variant="Outline Danger"
                :leading-icon="Trash2"
                @click="removeRegistration(reg.id, reg.member?.display_name || '', reg.member_id)"
              >
                {{ t('common.remove') }}
              </Button>
            </div>

            <div class="flex flex-col gap-2">
              <label
                v-for="interval in intervals"
                :key="interval.id"
                data-ds="Interval Check Row"
                :data-ds-checked="String(presence[reg.member_id]?.[interval.id] || false)"
                :data-ds-editable="String(isSessionEditable)"
                class="flex h-11 items-center justify-between gap-3 rounded-xl border border-line-divider bg-surface-subtle px-3 py-2"
                :class="{ 'opacity-70': !isSessionEditable }"
              >
                <span class="text-sm font-normal text-fg-secondary">
                  {{ formatTime(interval.start_time) }} - {{ formatTime(interval.end_time) }}
                </span>
                <Checkbox
                  size="24"
                  :model-value="presence[reg.member_id]?.[interval.id] || false"
                  @change="togglePresence(reg.member_id, interval.id)"
                  :disabled="!isSessionEditable"
                  :aria-label="`${reg.member?.display_name || t('common.member')} ${formatTime(interval.start_time)} - ${formatTime(interval.end_time)}`"
                />
              </label>
            </div>
          </article>
        </div>
        <div class="hidden md:block overflow-x-auto">
          <table class="min-w-full">
            <thead>
              <tr class="border-b border-line-divider">
                <TableHeaderCell align="Left" class="sticky left-0 z-10 w-48">
                  {{ t('common.member') }}
                </TableHeaderCell>
                <TableHeaderCell
                  v-if="isSessionEditable"
                  align="Center"
                  density="Compact"
                  class="w-12"
                >
                  <span class="sr-only">{{ t('common.actions') }}</span>
                </TableHeaderCell>
                <TableHeaderCell
                  v-if="isSessionEditable"
                  align="Center"
                  density="Compact"
                  class="w-16"
                >
                  {{ t('session.absent') }}
                </TableHeaderCell>
                <TableHeaderCell
                  v-for="interval in intervals"
                  :key="interval.id"
                  align="Center"
                  density="Compact"
                  class="min-w-[100px]"
                >
                  {{ formatTime(interval.start_time) }} - {{ formatTime(interval.end_time) }}
                </TableHeaderCell>
              </tr>
            </thead>
            <tbody class="bg-surface-card">
              <tr
                v-for="reg in registrations"
                :key="reg.id"
                data-ds="Attendance Row"
                :data-ds-absent="String(isRegistrationAbsent(reg))"
                :data-ds-editable="String(isSessionEditable)"
                class="border-b border-line-divider last:border-b-0"
                :class="{ 'bg-surface-subtle opacity-60': isRegistrationAbsent(reg) }"
              >
                <td
                  class="sticky left-0 z-10 whitespace-nowrap bg-surface-card after:absolute after:inset-y-0 after:right-0 after:w-px after:bg-line-divider px-6 py-4 text-base font-bold text-fg-primary"
                >
                  <div class="flex items-center">
                    {{ reg.member?.display_name }}
                    <span
                      v-if="isRegistrationAbsent(reg)"
                      class="ml-2 text-sm text-status-danger-action font-normal italic"
                      >({{ t('session.absent') }})</span
                    >
                  </div>
                </td>
                <td v-if="isSessionEditable" class="px-3 py-4 whitespace-nowrap text-center">
                  <IconButton
                    size="Default"
                    shape="Square"
                    variant="Ghost"
                    :icon="Trash2"
                    :label="t('session.removeRegistrationTooltip')"
                    :title="t('session.removeRegistrationTooltip')"
                    @click="
                      removeRegistration(reg.id, reg.member?.display_name || '', reg.member_id)
                    "
                  />
                </td>
                <td v-if="isSessionEditable" class="px-3 py-4 whitespace-nowrap text-center">
                  <IconButton
                    size="Default"
                    shape="Square"
                    :variant="isRegistrationAbsent(reg) ? 'Ghost Danger' : 'Ghost'"
                    :icon="UserX"
                    :label="t('session.markAbsentTooltip')"
                    :title="t('session.markAbsentTooltip')"
                    @click="toggleAbsent(reg)"
                  />
                </td>
                <td
                  v-for="interval in intervals"
                  :key="interval.id"
                  class="px-3 py-4 whitespace-nowrap text-center"
                >
                  <div class="flex justify-center items-center h-full">
                    <Checkbox
                      size="24"
                      :model-value="presence[reg.member_id]?.[interval.id] || false"
                      @change="togglePresence(reg.member_id, interval.id)"
                      :disabled="!isSessionEditable || isSessionFinalized"
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
        class="session-scroll-target rounded-xl border border-line-divider bg-surface-card shadow-sm"
      >
        <SectionHeader
          variant="Tinted"
          :title="t('session.costSummary')"
          :suffix="`(${t('session.live')})`"
        />
        <div v-if="session.status !== 'waiting_for_payment' && session.status !== 'done'">
          <div v-if="costs.length === 0" class="p-6 text-sm text-fg-muted md:hidden">
            {{ t('session.liveCostsEmpty') }}
          </div>
          <div v-else class="flex flex-col gap-4 p-4 md:hidden">
            <div
              data-ds="Amount Panel"
              data-ds-tone="Success"
              class="flex flex-col gap-1 rounded-xl border border-line-success-subtle bg-status-success-subtle p-4"
            >
              <p class="text-sm font-bold text-status-success-strong">
                {{ t('session.surplusFund') }}
              </p>
              <p class="text-3xl font-bold text-fg-success tabular-nums">
                {{ formatCurrency(surplus) }}
              </p>
              <p class="text-sm text-status-success-strong">{{ t('session.live') }}</p>
            </div>

            <article
              v-for="cost in costs"
              :key="cost.member_id"
              data-ds="Cost Card"
              :data-ds-extra="
                cost.total_extra_fee > 0
                  ? 'Positive'
                  : cost.total_extra_fee < 0
                    ? 'Negative'
                    : 'None'
              "
              class="flex flex-col gap-4 rounded-xl border border-line-divider bg-surface-card p-4 shadow-sm"
            >
              <div class="flex items-start justify-between gap-3">
                <div class="flex flex-col gap-1">
                  <h3 class="text-base font-bold text-fg-primary">
                    {{ cost.display_name }}
                  </h3>
                  <p class="text-sm font-bold text-fg-muted">
                    {{ t('session.live') }}
                  </p>
                </div>
                <div class="flex flex-col items-end">
                  <p class="text-sm font-bold text-fg-muted">{{ t('session.total') }}</p>
                  <p class="text-3xl font-bold text-fg-brand-strong tabular-nums">
                    {{ formatCurrency(cost.final_total) }}
                  </p>
                </div>
              </div>

              <dl class="flex flex-col gap-3 text-sm">
                <div
                  data-ds="Key Value Row"
                  data-ds-layout="Inline Tinted"
                  data-ds-tone="Neutral"
                  data-ds-value-tone="Primary"
                  data-ds-align="Left"
                  class="flex justify-between gap-3 rounded-xl bg-surface-subtle px-3 py-2"
                >
                  <dt class="font-bold text-fg-muted">{{ t('session.numIntervals') }}</dt>
                  <dd class="font-bold text-fg-primary tabular-nums">{{ cost.intervals_count }}</dd>
                </div>
                <div
                  data-ds="Key Value Row"
                  data-ds-layout="Inline Tinted"
                  data-ds-tone="Neutral"
                  data-ds-value-tone="Primary"
                  data-ds-align="Left"
                  class="flex justify-between gap-3 rounded-xl bg-surface-subtle px-3 py-2"
                >
                  <dt class="font-bold text-fg-muted">{{ t('session.courtFee') }}</dt>
                  <dd class="font-bold text-fg-primary tabular-nums">
                    {{ formatCurrency(cost.total_court_fee) }}
                  </dd>
                </div>
                <div
                  data-ds="Key Value Row"
                  data-ds-layout="Inline Tinted"
                  data-ds-tone="Neutral"
                  data-ds-value-tone="Primary"
                  data-ds-align="Left"
                  class="flex justify-between gap-3 rounded-xl bg-surface-subtle px-3 py-2"
                >
                  <dt class="font-bold text-fg-muted">{{ t('session.shuttleFee') }}</dt>
                  <dd class="font-bold text-fg-primary tabular-nums">
                    {{ formatCurrency(cost.total_shuttle_fee) }}
                  </dd>
                </div>
                <div
                  v-if="cost.total_extra_fee !== 0"
                  data-ds="Key Value Row"
                  data-ds-layout="Inline Tinted"
                  :data-ds-tone="cost.total_extra_fee > 0 ? 'Debt' : 'Credit'"
                  :data-ds-value-tone="cost.total_extra_fee > 0 ? 'Debt' : 'Success'"
                  data-ds-align="Left"
                  class="flex justify-between gap-3 rounded-xl px-3 py-2"
                  :class="
                    cost.total_extra_fee > 0
                      ? 'bg-status-danger-subtle'
                      : 'bg-status-success-subtle'
                  "
                >
                  <dt
                    class="font-bold"
                    :class="
                      cost.total_extra_fee > 0
                        ? 'text-status-danger-strong'
                        : 'text-status-success-strong'
                    "
                  >
                    {{ t('session.extraFee') }}
                  </dt>
                  <dd
                    class="font-bold tabular-nums"
                    :class="cost.total_extra_fee > 0 ? 'text-fg-danger' : 'text-fg-success'"
                  >
                    {{
                      (cost.total_extra_fee > 0 ? '+' : '') + formatCurrency(cost.total_extra_fee)
                    }}
                  </dd>
                </div>
                <div
                  data-ds="Key Value Row"
                  data-ds-layout="Inline Tinted"
                  data-ds-tone="Credit"
                  data-ds-value-tone="Success"
                  data-ds-align="Left"
                  class="flex justify-between gap-3 rounded-xl bg-status-success-subtle px-3 py-2"
                >
                  <dt class="font-bold text-status-success-strong">
                    {{ t('session.surplusFund') }}
                  </dt>
                  <dd class="font-bold text-fg-success tabular-nums">
                    {{ formatCurrency(surplus) }}
                  </dd>
                </div>
              </dl>
            </article>
          </div>

          <div class="hidden overflow-x-auto md:block">
            <table class="min-w-full">
              <thead>
                <tr>
                  <TableHeaderCell align="Left">{{ t('common.member') }}</TableHeaderCell>
                  <TableHeaderCell align="Right">{{ t('session.total') }}</TableHeaderCell>
                  <TableHeaderCell align="Center">{{ t('session.numIntervals') }}</TableHeaderCell>
                  <TableHeaderCell align="Right">{{ t('session.courtFee') }}</TableHeaderCell>
                  <TableHeaderCell align="Right">{{ t('session.shuttleFee') }}</TableHeaderCell>
                  <TableHeaderCell align="Right">{{ t('session.extraFee') }}</TableHeaderCell>
                </tr>
              </thead>
              <tbody class="bg-surface-card">
                <tr
                  v-for="cost in costs"
                  :key="cost.member_id"
                  data-ds="Cost Table Row"
                  :data-ds-extra="
                    cost.total_extra_fee > 0
                      ? 'Positive'
                      : cost.total_extra_fee < 0
                        ? 'Negative'
                        : 'Zero'
                  "
                  class="border-b border-line-divider"
                >
                  <td class="px-6 py-4 whitespace-nowrap text-base font-bold text-fg-primary">
                    {{ cost.display_name }}
                  </td>
                  <td
                    class="px-6 py-4 whitespace-nowrap text-base text-right font-bold text-fg-primary"
                  >
                    {{ formatCurrency(cost.final_total) }}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-base text-center text-fg-muted">
                    {{ cost.intervals_count }}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-base text-right text-fg-muted">
                    {{ formatCurrency(cost.total_court_fee) }}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-base text-right text-fg-muted">
                    {{ formatCurrency(cost.total_shuttle_fee) }}
                  </td>
                  <td
                    class="px-6 py-4 whitespace-nowrap text-base text-right"
                    :class="
                      cost.total_extra_fee > 0
                        ? 'text-fg-danger font-bold'
                        : cost.total_extra_fee < 0
                          ? 'text-fg-success font-bold'
                          : 'text-fg-muted'
                    "
                  >
                    {{
                      cost.total_extra_fee !== 0
                        ? (cost.total_extra_fee > 0 ? '+' : '') +
                          formatCurrency(cost.total_extra_fee)
                        : '—'
                    }}
                  </td>
                </tr>
                <!-- Surplus Row -->
                <tr data-ds="Surplus Table Row" data-ds-table="Cost" class="bg-surface-subtle">
                  <td
                    colspan="5"
                    class="px-6 py-4 whitespace-nowrap text-right text-base font-bold text-fg-primary"
                  >
                    {{ t('session.surplusFund') }}
                  </td>
                  <td
                    class="px-6 py-4 whitespace-nowrap text-right text-base font-bold text-fg-success"
                  >
                    {{ formatCurrency(surplus) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <div v-else class="p-6 text-sm text-fg-muted">
          {{ t('session.liveCostsEmpty') }}
        </div>
      </section>

      <!-- Snapshot View (Waiting/Done mode) -->
      <ShuttleUsageEditor
        v-if="session.status === 'open' && authStore.isAdmin"
        :session-id="sessionId"
        :usage="session.shuttle_usage || []"
        @saved="fetchData()"
      />

      <SessionExtraCharges
        v-if="session.status !== 'cancelled'"
        ref="extraChargesRef"
        :sessionId="sessionId"
        :members="allMembers"
        :isAdmin="authStore.isAdmin"
        :isReadOnly="session.status === 'waiting_for_payment' || session.status === 'done'"
        @changed="handleExtraChargesChanged"
      />

      <section
        id="payments-section"
        class="session-scroll-target rounded-xl border border-line-divider bg-surface-card shadow-sm"
      >
        <SectionHeader variant="Tinted" :title="t('session.paymentTable')" />
        <div v-if="isSessionFinalized">
          <div v-if="snapshots.length === 0" class="p-6 text-sm text-fg-muted md:hidden">
            {{ t('session.paymentSnapshotsEmpty') }}
          </div>
          <div v-else class="flex flex-col gap-4 p-4 md:hidden">
            <div
              data-ds="Amount Panel"
              data-ds-tone="Success"
              class="flex flex-col gap-1 rounded-xl border border-line-success-subtle bg-status-success-subtle p-4"
            >
              <p class="text-sm font-bold text-status-success-strong">
                {{ t('session.surplusFund') }}
              </p>
              <p class="text-3xl font-bold text-fg-success tabular-nums">
                {{ formatCurrency(surplus) }}
              </p>
            </div>

            <article
              v-for="snapshot in snapshots"
              :key="snapshot.id"
              data-ds="Payment Card"
              :data-ds-status="
                snapshot.status === 'paid'
                  ? 'Paid'
                  : snapshot.status === 'partial'
                    ? 'Partial'
                    : 'Pending'
              "
              :data-ds-admin="String(authStore.isAdmin && snapshot.status !== 'paid')"
              class="flex flex-col gap-4 rounded-xl border border-line-divider bg-surface-card p-4 shadow-sm"
            >
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="flex min-w-0 items-start gap-3">
                  <label
                    v-if="snapshot.status !== 'paid' && authStore.isAdmin"
                    data-ds="Checkbox Tile"
                    :data-ds-checked="String(selectedSnapshotIds.includes(snapshot.id))"
                    class="inline-flex size-11 shrink-0 items-center justify-center rounded-xl border border-line-brand-muted bg-surface-brand-subtle"
                  >
                    <Checkbox
                      v-model="selectedSnapshotIds"
                      size="20"
                      :value="snapshot.id"
                      :aria-label="`${t('session.groupPaymentBar', { count: 1 })}: ${snapshot.display_name}`"
                    />
                  </label>
                  <div class="flex min-w-0 flex-col items-start gap-2">
                    <h3 class="max-w-full truncate text-base font-bold uppercase text-fg-primary">
                      {{ snapshot.display_name }}
                    </h3>
                    <Badge
                      :tone="
                        snapshot.status === 'paid'
                          ? 'Success'
                          : snapshot.status === 'partial'
                            ? 'Warning'
                            : 'Danger'
                      "
                      data-ds="Payment Status Badge"
                      :data-ds-status="
                        snapshot.status === 'paid'
                          ? 'Paid'
                          : snapshot.status === 'partial'
                            ? 'Partial'
                            : 'Pending'
                      "
                    >
                      {{
                        snapshot.status === 'paid'
                          ? t('payment.paid')
                          : snapshot.status === 'partial'
                            ? t('payment.partial')
                            : t('payment.pending')
                      }}
                    </Badge>
                  </div>
                </div>
                <div class="ml-auto flex shrink-0 flex-col items-end">
                  <p class="text-sm font-bold text-fg-muted">{{ t('session.mustPay') }}</p>
                  <p class="text-3xl font-bold text-fg-brand-strong tabular-nums">
                    {{ formatCurrency(snapshot.final_amount) }}
                  </p>
                </div>
              </div>

              <dl class="flex flex-col gap-3 text-sm">
                <div
                  data-ds="Key Value Row"
                  data-ds-layout="Inline Tinted"
                  data-ds-tone="Neutral"
                  data-ds-value-tone="Success"
                  data-ds-align="Left"
                  class="flex justify-between gap-3 rounded-xl bg-surface-subtle px-3 py-2"
                >
                  <dt class="font-bold text-fg-muted">{{ t('payment.paid') }}</dt>
                  <dd class="font-bold text-fg-success tabular-nums">
                    {{ formatCurrency(snapshot.paid_amount) }}
                  </dd>
                </div>
                <div
                  data-ds="Key Value Row"
                  data-ds-layout="Inline Tinted"
                  data-ds-tone="Neutral"
                  data-ds-value-tone="Primary"
                  data-ds-align="Left"
                  class="flex justify-between gap-3 rounded-xl bg-surface-subtle px-3 py-2"
                >
                  <dt class="font-bold text-fg-muted">{{ t('session.intervalsAbbr') }}</dt>
                  <dd class="font-bold text-fg-primary tabular-nums">
                    {{ getBreakdown(snapshot.member_id)?.intervals_count || 0 }}
                  </dd>
                </div>
                <div
                  data-ds="Key Value Row"
                  data-ds-layout="Inline Tinted"
                  data-ds-tone="Neutral"
                  data-ds-value-tone="Primary"
                  data-ds-align="Left"
                  class="flex justify-between gap-3 rounded-xl bg-surface-subtle px-3 py-2"
                >
                  <dt class="font-bold text-fg-muted">{{ t('session.courtFee') }}</dt>
                  <dd class="font-bold text-fg-primary tabular-nums">
                    {{ formatCurrency(getBreakdown(snapshot.member_id)?.total_court_fee || 0) }}
                  </dd>
                </div>
                <div
                  data-ds="Key Value Row"
                  data-ds-layout="Inline Tinted"
                  data-ds-tone="Neutral"
                  data-ds-value-tone="Primary"
                  data-ds-align="Left"
                  class="flex justify-between gap-3 rounded-xl bg-surface-subtle px-3 py-2"
                >
                  <dt class="font-bold text-fg-muted">{{ t('session.shuttleFee') }}</dt>
                  <dd class="font-bold text-fg-primary tabular-nums">
                    {{ formatCurrency(getBreakdown(snapshot.member_id)?.total_shuttle_fee || 0) }}
                  </dd>
                </div>
                <div
                  data-ds="Key Value Row"
                  data-ds-layout="Inline Tinted"
                  data-ds-tone="Credit"
                  data-ds-value-tone="Success"
                  data-ds-align="Left"
                  class="flex justify-between gap-3 rounded-xl bg-status-success-subtle px-3 py-2"
                >
                  <dt class="font-bold text-status-success-strong">
                    {{ t('session.surplusFund') }}
                  </dt>
                  <dd class="font-bold text-fg-success tabular-nums">
                    {{ formatCurrency(surplus) }}
                  </dd>
                </div>
              </dl>

              <div v-if="snapshot.status !== 'paid'" class="grid grid-cols-1 gap-2 sm:grid-cols-2">
                <Button
                  size="Default"
                  variant="Outline Brand"
                  :leading-icon="QrCode"
                  @click="openPaymentQR(snapshot, snapshot.display_name)"
                >
                  {{ t('payment.qrPay') }}
                </Button>
                <Button
                  v-if="authStore.isAdmin"
                  size="Default"
                  variant="Outline Success"
                  @click="openCashPayment(snapshot, snapshot.display_name)"
                >
                  {{ t('payment.cashPay') }}
                </Button>
              </div>
              <div
                v-else
                data-ds="Paid Indicator"
                data-ds-style="Banner"
                class="flex h-11 items-center justify-center gap-1.5 rounded-xl bg-status-success-subtle text-sm font-bold text-fg-success"
              >
                <Check class="size-5" aria-hidden="true" />
                {{ t('payment.done') }}
              </div>
            </article>
          </div>

          <div class="hidden overflow-x-auto md:block">
            <table class="min-w-full">
              <thead>
                <tr>
                  <TableHeaderCell
                    v-if="authStore.isAdmin"
                    content="Empty"
                    density="Compact"
                    align="Center"
                    class="w-12"
                  />
                  <TableHeaderCell align="Left">{{ t('common.member') }}</TableHeaderCell>
                  <TableHeaderCell align="Right">{{ t('session.mustPay') }}</TableHeaderCell>
                  <TableHeaderCell align="Center" density="Compact">{{
                    t('session.intervalsAbbr')
                  }}</TableHeaderCell>
                  <TableHeaderCell align="Right">{{ t('session.courtFee') }}</TableHeaderCell>
                  <TableHeaderCell align="Right">{{ t('session.shuttleFee') }}</TableHeaderCell>
                  <TableHeaderCell align="Right">{{ t('payment.paid') }}</TableHeaderCell>
                  <TableHeaderCell align="Center">{{ t('common.status') }}</TableHeaderCell>
                  <TableHeaderCell align="Center">{{ t('session.pay') }}</TableHeaderCell>
                </tr>
              </thead>
              <tbody class="bg-surface-card">
                <tr
                  v-for="snapshot in snapshots"
                  :key="snapshot.id"
                  data-ds="Payment Table Row"
                  :data-ds-status="
                    snapshot.status === 'paid'
                      ? 'Paid'
                      : snapshot.status === 'partial'
                        ? 'Partial'
                        : 'Pending'
                  "
                  :data-ds-admin="String(authStore.isAdmin)"
                  :data-ds-selected="String(selectedSnapshotIds.includes(snapshot.id))"
                  class="border-b border-line-divider"
                >
                  <td v-if="authStore.isAdmin" class="px-3 py-4 whitespace-nowrap text-center">
                    <Checkbox
                      v-if="snapshot.status !== 'paid'"
                      v-model="selectedSnapshotIds"
                      size="20"
                      :value="snapshot.id"
                      :aria-label="`${t('session.groupPaymentBar', { count: 1 })}: ${snapshot.display_name}`"
                    />
                    <StatusIcon v-else kind="Check" size="20" :label="t('payment.paid')" />
                  </td>
                  <td
                    class="px-6 py-4 whitespace-nowrap text-base font-bold text-fg-primary uppercase"
                  >
                    {{ snapshot.display_name }}
                  </td>
                  <td
                    class="px-6 py-4 whitespace-nowrap text-base text-right font-bold text-fg-brand-strong"
                  >
                    {{ formatCurrency(snapshot.final_amount) }}
                  </td>
                  <td class="px-3 py-4 whitespace-nowrap text-base text-center text-fg-muted">
                    {{ getBreakdown(snapshot.member_id)?.intervals_count || 0 }}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-base text-right text-fg-muted">
                    {{ formatCurrency(getBreakdown(snapshot.member_id)?.total_court_fee || 0) }}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-base text-right text-fg-muted">
                    {{ formatCurrency(getBreakdown(snapshot.member_id)?.total_shuttle_fee || 0) }}
                  </td>
                  <td
                    class="px-6 py-4 whitespace-nowrap text-base text-right text-fg-success font-bold"
                  >
                    {{ formatCurrency(snapshot.paid_amount) }}
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-center">
                    <Badge
                      :tone="
                        snapshot.status === 'paid'
                          ? 'Success'
                          : snapshot.status === 'partial'
                            ? 'Warning'
                            : 'Danger'
                      "
                      data-ds="Payment Status Badge"
                      :data-ds-status="
                        snapshot.status === 'paid'
                          ? 'Paid'
                          : snapshot.status === 'partial'
                            ? 'Partial'
                            : 'Pending'
                      "
                    >
                      {{
                        snapshot.status === 'paid'
                          ? t('payment.paid')
                          : snapshot.status === 'partial'
                            ? t('payment.partial')
                            : t('payment.pending')
                      }}
                    </Badge>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-center">
                    <div class="flex flex-col items-center gap-1.5">
                      <Button
                        v-if="snapshot.status !== 'paid'"
                        size="Small"
                        variant="Outline Brand"
                        :leading-icon="QrCode"
                        class="w-full"
                        :aria-label="`${t('payment.qrPay')}: ${snapshot.display_name}`"
                        @click="openPaymentQR(snapshot, snapshot.display_name)"
                      >
                        {{ t('payment.qrPay') }}
                      </Button>
                      <Button
                        v-if="snapshot.status !== 'paid' && authStore.isAdmin"
                        size="Small"
                        variant="Outline Success"
                        class="w-full"
                        :aria-label="`${t('payment.cashPay')}: ${snapshot.display_name}`"
                        @click="openCashPayment(snapshot, snapshot.display_name)"
                      >
                        {{ t('payment.cashPay') }}
                      </Button>
                      <span
                        v-else-if="snapshot.status === 'paid'"
                        data-ds="Paid Indicator"
                        data-ds-style="Inline"
                        class="inline-flex h-5 items-center gap-1 text-sm font-bold text-fg-success-soft"
                      >
                        <Check class="size-5" aria-hidden="true" />
                        {{ t('payment.done') }}
                      </span>
                    </div>
                  </td>
                </tr>
                <!-- Surplus Row -->
                <tr
                  data-ds="Surplus Table Row"
                  data-ds-table="Payment"
                  class="border-t-2 border-line-divider bg-surface-subtle"
                >
                  <td
                    :colspan="authStore.isAdmin ? 6 : 5"
                    class="px-6 py-4 whitespace-nowrap text-right text-sm font-bold text-fg-primary"
                  >
                    {{ t('session.surplusFund') }}
                  </td>
                  <td
                    class="px-6 py-4 whitespace-nowrap text-right text-base font-bold text-fg-success"
                  >
                    {{ formatCurrency(surplus) }}
                  </td>
                  <td colspan="2" class="whitespace-nowrap"></td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <div v-else class="p-6 text-sm text-fg-muted">{{ t('session.paymentSnapshotsEmpty') }}</div>
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
        class="session-group-payment-bar fixed left-1/2 z-50 max-w-2xl -translate-x-1/2"
      >
        <div
          data-ds="Floating Selection Bar"
          data-ds-style="Brand"
          class="flex items-center justify-between gap-4 rounded-xl border border-line-brand-emphasis bg-surface-brand p-4 shadow-xl"
        >
          <div class="flex flex-col">
            <span class="text-sm font-bold text-fg-on-brand">{{
              t('session.groupPaymentBar', { count: selectedSnapshotIds.length })
            }}</span>
            <span class="text-xl font-bold text-fg-on-brand">{{
              t('session.totalSelected', { amount: formatCurrency(totalSelectedAmount) })
            }}</span>
          </div>
          <Button
            size="Default"
            variant="Inverse"
            :leading-icon="QrCode"
            :loading="isCreatingGroupPayment"
            :disabled="isCreatingGroupPayment"
            class="active:scale-95"
            @click="handleCreateGroupPayment"
          >
            {{ t('session.groupPayButton') }}
          </Button>
        </div>
      </div>
    </Transition>
  </div>

  <nav
    v-if="session"
    data-ds="Section Tab Bar"
    :data-ds-active="
      activeSection.charAt(0).toUpperCase() + activeSection.slice(1, activeSection.indexOf('-'))
    "
    class="session-section-ribbon fixed inset-x-0 z-30 overflow-x-auto border-y border-line-divider bg-surface-card px-4 py-2 md:hidden"
    :aria-label="t('session.cockpitNavLabel')"
  >
    <div class="flex min-w-max gap-2 pr-6" style="scroll-snap-type: x proximity">
      <button
        v-for="tab in sectionTabs"
        :key="tab.id"
        :data-tab-id="tab.id"
        type="button"
        style="scroll-snap-align: start"
        data-ds="Section Tab"
        :data-ds-state="activeSection === tab.id ? 'Active' : 'Inactive'"
        class="h-11 shrink-0 rounded-xl px-4 text-sm font-bold transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-line-focus focus-visible:ring-offset-2"
        :class="
          activeSection === tab.id
            ? 'bg-surface-brand text-fg-on-brand shadow-sm'
            : 'bg-status-neutral text-fg-secondary hover:bg-surface-brand-subtle hover:text-fg-brand-strong'
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

<style scoped>
.session-detail-shell {
  padding-bottom: calc(220px + env(safe-area-inset-bottom));
}

.session-section-ribbon {
  bottom: calc(65px + max(8px, env(safe-area-inset-bottom)));
}

.session-section-ribbon::after {
  content: '';
  position: absolute;
  top: 0;
  right: 0;
  bottom: 0;
  width: 32px;
  background: linear-gradient(to right, transparent, var(--color-surface-card));
  pointer-events: none;
}

.session-scroll-target {
  scroll-margin-top: 57px;
}

.session-group-payment-bar {
  bottom: calc(135px + max(8px, env(safe-area-inset-bottom)));
  width: calc(100% - 2rem);
}

@media (min-width: 768px) {
  .session-detail-shell {
    padding-bottom: 2rem;
  }

  .session-group-payment-bar {
    bottom: 2rem;
  }

  .session-scroll-target {
    scroll-margin-top: 6rem;
  }
}
</style>
