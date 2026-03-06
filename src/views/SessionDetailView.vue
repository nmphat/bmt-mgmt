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
  CourtBooking,
} from '@/types'
import { useLangStore } from '@/stores/lang'
import PaymentQRModal from '@/components/PaymentQRModal.vue'
import ManualPaymentModal from '@/components/ManualPaymentModal.vue'
import SessionExtraCharges from '@/components/SessionExtraCharges.vue'
import SessionHeader from '@/components/session/SessionHeader.vue'
import SessionPaymentTable from '@/components/session/SessionPaymentTable.vue'
import SessionAttendanceGrid from '@/components/session/SessionAttendanceGrid.vue'
import SessionCostSummary from '@/components/session/SessionCostSummary.vue'
import SessionGroupPaymentBar from '@/components/session/SessionGroupPaymentBar.vue'
import { useAuthStore } from '@/stores/auth'
import type { RealtimeChannel } from '@supabase/supabase-js'
import { useToast } from 'vue-toastification'
import type { CostSnapshot } from '@/types'

const route = useRoute()
const authStore = useAuthStore()
const langStore = useLangStore()
const toast = useToast()
const t = computed(() => langStore.t)
const sessionId = route.params.id as string
const shouldOpenMemberDropdown = computed(() => route.query.openMemberDropdown === '1')

const session = ref<SessionSummary | null>(null)
const intervals = ref<Interval[]>([])
const registrations = ref<SessionRegistration[]>([])
const allMembers = ref<Member[]>([])
const isRegistering = ref(false)
const presence = ref<Record<string, Record<string, boolean>>>({}) // memberId -> intervalId -> isPresent
const costs = ref<MemberCost[]>([])
const courtBookings = ref<CourtBooking[]>([])
const extraChargesRef = ref<InstanceType<typeof SessionExtraCharges> | null>(null)

const snapshots = ref<(CostSnapshot & { display_name: string })[]>([])
const loading = ref(true)
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
const selectedSnapshotIds = ref<string[]>([])
const groupPaymentData = ref<GroupPaymentData | null>(null)
const isCreatingGroupPayment = ref(false)
const isFetching = ref(false)


let realtimeChannel: RealtimeChannel | null = null

const availableMembers = computed(() => {
  const registeredIds = new Set(registrations.value.map((r) => r.member_id))
  return allMembers.value
    .filter((m) => !registeredIds.has(m.id) && m.is_active)
    .sort((a, b) => a.display_name.localeCompare(b.display_name, 'vi'))
})

const registeredMembers = computed(() => {
  const memberMap = new Map<string, Member>()
  for (const reg of registrations.value) {
    if (reg.member) {
      memberMap.set(reg.member_id, reg.member)
    }
  }
  return Array.from(memberMap.values()).sort((a, b) =>
    a.display_name.localeCompare(b.display_name, 'vi'),
  )
})

async function fetchData(refreshCostsOnly = false) {
  if (isFetching.value) return
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

    if (!refreshCostsOnly) {
      // Fetch intervals
      const { data: intervalsData } = await supabase
        .from('session_intervals')
        .select('*')
        .eq('session_id', sessionId)
        .order('idx', { ascending: true })
      intervals.value = intervalsData || []

      // Fetch court bookings
      const { data: bookingsData } = await supabase
        .from('session_court_bookings')
        .select('*')
        .eq('session_id', sessionId)
        .order('start_time', { ascending: true })
      courtBookings.value = bookingsData || []

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

function stopRealtime() {
  if (realtimeChannel) {
    supabase.removeChannel(realtimeChannel)
    realtimeChannel = null
  }
}

async function registerMembers(memberIds: string[]) {
  if (memberIds.length === 0) return

  try {
    isRegistering.value = true

    // Call RPC for each selected member
    const promises = memberIds.map((memberId) =>
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
      toast.success(t.value('toast.memberRegistered', { count: memberIds.length }))
    }

    await fetchData(true)
  } catch (error: any) {
    toast.error(
      error.message || t.value('toast.error', { message: t.value('session.registerError') }),
    )
  } finally {
    isRegistering.value = false
  }
}

async function removeRegistration(memberId: string, name: string) {
  if (!confirm(t.value('session.removeConfirm', { name }))) return

  try {
    const { error } = await supabase.rpc('remove_member_from_session', {
      p_session_id: sessionId,
      p_member_id: memberId,
    })

    if (error) throw error

    const { error: extraChargesError } = await supabase
      .from('session_extra_charges')
      .delete()
      .eq('session_id', sessionId)
      .eq('member_id', memberId)

    if (extraChargesError) {
      console.error('Error cleaning extra charges for removed member:', extraChargesError)
    }

    toast.success(t.value('toast.registrationRemoved'))
    await fetchData(true)
    await extraChargesRef.value?.fetchCharges()
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

const surplus = computed(() => {
  if (!session.value || costs.value.length === 0) return 0

  // Surplus = sum of rounding adjustments (CEIL to 1000đ per member)
  // = totalCollected - totalActualCosts (before rounding)
  // Using costs array covers all cost types (court + shuttle + extra) without depending on
  // session-level fields. Court cost = booking cost (price_per_hour) + court_fee_addon (Option C).
  const totalCollected = costs.value.reduce((sum, c) => sum + c.final_total, 0)
  const totalActual = costs.value.reduce(
    (sum, c) => sum + c.total_court_fee + c.total_shuttle_fee + c.total_extra_fee,
    0,
  )
  return totalCollected - totalActual
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

async function handleExtraChargesChanged() {
  await fetchCosts()
}

onMounted(async () => {
  await fetchData()
  initRealtime()
})

onUnmounted(() => {
  if (realtimeChannel) {
    supabase.removeChannel(realtimeChannel)
  }
})
</script>

<template>
  <div class="max-w-full mx-auto px-3 sm:px-6 lg:px-8 py-4 md:py-6">
    <div v-if="loading && !session" class="flex justify-center py-12">
      <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
    </div>

    <template v-else-if="session">
      <SessionHeader
        :session="session"
        :courtBookings="courtBookings"
        :costs="costs"
        :snapshots="snapshots"
        :sessionId="sessionId"
        :loading="loading"
        @dataChanged="fetchData()"
        @refresh="fetchData()"
      />
      <!-- Cancelled Banner -->
      <div v-if="session.status === 'cancelled'" class="bg-gray-50 border-l-4 border-gray-400 p-4 mb-6 rounded-r-md">
        <p class="text-sm text-gray-700">{{ t('session.cancelledMessage') }}</p>
      </div>

      <!-- Payment table (waiting_for_payment / done) -->
      <SessionPaymentTable
        v-if="session.status === 'waiting_for_payment' || session.status === 'done'"
        :snapshots="snapshots"
        :costs="costs"
        :surplus="surplus"
        :selectedSnapshotIds="selectedSnapshotIds"
        @update:selectedSnapshotIds="selectedSnapshotIds = $event"
        @openQR="openPaymentQR"
        @openCash="openCashPayment"
      />

      <!-- Attendance grid + member management -->
      <SessionAttendanceGrid
        :session="session"
        :registrations="registrations"
        :intervals="intervals"
        :presence="presence"
        :availableMembers="availableMembers"
        :isRegistering="isRegistering"
        :autoOpenMemberDropdown="shouldOpenMemberDropdown"
        @togglePresence="togglePresence"
        @registerMembers="registerMembers"
        @removeRegistration="removeRegistration"
      />

      <!-- Live cost summary (open status only) -->
      <SessionCostSummary
        v-if="session.status !== 'waiting_for_payment' && session.status !== 'done'"
        :costs="costs"
        :surplus="surplus"
      />

      <!-- Extra Charges -->
      <SessionExtraCharges
        v-if="session.status !== 'cancelled'"
        ref="extraChargesRef"
        :sessionId="sessionId"
        :members="registeredMembers"
        :isAdmin="authStore.isAuthenticated"
        :isReadOnly="session.status === 'waiting_for_payment' || session.status === 'done'"
        @changed="handleExtraChargesChanged"
        class="mb-6"
      />
    </template>

    <!-- Floating group payment bar -->
    <SessionGroupPaymentBar
      :selectedCount="selectedSnapshotIds.length"
      :totalAmount="totalSelectedAmount"
      :isCreating="isCreatingGroupPayment"
      @create="handleCreateGroupPayment"
    />
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
