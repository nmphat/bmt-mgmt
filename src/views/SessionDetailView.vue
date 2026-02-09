<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '@/lib/supabase'
import type { SessionSummary, Interval, SessionRegistration, MemberCost, Member } from '@/types'
import { format } from 'date-fns'
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
} from 'lucide-vue-next'
import { useAuthStore } from '@/stores/auth'
import type { RealtimeChannel } from '@supabase/supabase-js'
import { useToast } from 'vue-toastification'

const route = useRoute()
const authStore = useAuthStore()
const toast = useToast()
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
const loading = ref(true)
const isEditingSession = ref(false)
const isSavingSession = ref(false)
const sessionForm = ref({
  title: '',
  status: 'draft' as 'draft' | 'active' | 'closed',
  court_fee_total: 0,
  shuttle_fee_total: 0,
})
let realtimeChannel: RealtimeChannel | null = null

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

    // Fetch session summary
    if (!refreshCostsOnly) {
      const { data: sessionData } = await supabase
        .from('view_session_summary')
        .select('*')
        .eq('id', sessionId)
        .single()
      session.value = sessionData

      if (sessionData) {
        sessionForm.value = {
          title: sessionData.title,
          status: sessionData.status,
          court_fee_total: sessionData.court_fee_total,
          shuttle_fee_total: sessionData.shuttle_fee_total,
        }
      }

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

    await fetchCosts()
  } catch (error) {
    console.error('Error fetching session details:', error)
  } finally {
    loading.value = false
  }
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

    toast.success('Session updated successfully')
    isEditingSession.value = false
    await fetchData()
  } catch (error: any) {
    console.error('Error updating session:', error)
    toast.error(error.message || 'Failed to update session')
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
      toast.error('Some registrations failed. Check console for details.')
    } else {
      toast.success(`${selectedMemberIds.value.length} member(s) registered successfully`)
    }

    selectedMemberIds.value = []
    showMemberDropdown.value = false
    await fetchData(true)
  } catch (error: any) {
    toast.error(error.message || 'Failed to register members')
  } finally {
    isRegistering.value = false
  }
}

async function removeRegistration(regId: string, name: string) {
  if (!confirm(`Remove ${name} from this session?`)) return

  try {
    const { error } = await supabase.from('session_registrations').delete().eq('id', regId)

    if (error) throw error

    toast.success('Registration removed')
    await fetchData(true)
  } catch (error: any) {
    toast.error(error.message || 'Failed to remove registration')
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
  return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(value)
}

const formatTime = (isoString: string) => {
  return format(new Date(isoString), 'HH:mm')
}

const surplus = computed(() => {
  if (!session.value || costs.value.length === 0) return 0

  const totalCollected = costs.value.reduce((sum, c) => sum + c.final_total, 0)
  // Note: session.court_fee_total and shuttle_fee_total might be string or number depending on DB driver, usually number in JS client
  const totalCost = (session.value.court_fee_total || 0) + (session.value.shuttle_fee_total || 0)

  return totalCollected - totalCost
})

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
    .subscribe()
})

onUnmounted(() => {
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
        Back to Dashboard
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
            <h2 class="text-xl font-bold text-gray-900">Edit Session</h2>
            <button @click="isEditingSession = false" class="text-gray-400 hover:text-gray-600">
              <X class="w-5 h-5" />
            </button>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700">Title</label>
              <input
                v-model="sessionForm.title"
                type="text"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">Status</label>
              <select
                v-model="sessionForm.status"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
              >
                <option value="draft">Draft</option>
                <option value="active">Active</option>
                <option value="closed">Closed</option>
              </select>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">Court Fee (Total)</label>
              <input
                v-model.number="sessionForm.court_fee_total"
                type="number"
                step="1000"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">Shuttle Fee (Total)</label>
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
              Cancel
            </button>
            <button
              @click="saveSession"
              :disabled="isSavingSession"
              class="flex items-center px-4 py-2 text-sm font-medium text-white bg-indigo-600 rounded-md hover:bg-indigo-700 transition disabled:opacity-50"
            >
              <Save v-if="!isSavingSession" class="w-4 h-4 mr-2" />
              <Loader2 v-else class="w-4 h-4 mr-2 animate-spin" />
              Save Changes
            </button>
          </div>
        </div>

        <!-- View Mode -->
        <div v-else class="flex justify-between items-start">
          <div>
            <div class="flex items-center gap-3 mb-2">
              <h1 class="text-3xl font-bold text-gray-900">{{ session.title }}</h1>
              <button
                v-if="authStore.isAuthenticated"
                @click="isEditingSession = true"
                class="p-1 text-gray-400 hover:text-indigo-600 transition"
                title="Edit session"
              >
                <Edit class="w-5 h-5" />
              </button>
            </div>
            <p class="text-gray-600 mb-4">
              {{ format(new Date(session.session_date), 'EEEE, dd/MM/yyyy') }}
            </p>
            <div class="flex flex-wrap gap-6 text-base">
              <div>
                <span class="text-gray-500 block mb-1">Court Fee</span>
                <span class="font-semibold text-gray-900">{{
                  formatCurrency(session.court_fee_total)
                }}</span>
              </div>
              <div>
                <span class="text-gray-500 block mb-1">Shuttle Fee</span>
                <span class="font-semibold text-gray-900">{{
                  formatCurrency(session.shuttle_fee_total)
                }}</span>
              </div>
              <div>
                <span class="text-gray-500 block mb-1">Status</span>
                <span
                  class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800 capitalize"
                  >{{ session.status }}</span
                >
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Attendance Matrix -->
      <div class="bg-white rounded-lg shadow-sm mb-8 border border-gray-100">
        <div
          class="px-6 py-4 border-b border-gray-100 bg-gray-50 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4"
        >
          <div class="flex items-center gap-2">
            <h2 class="text-xl font-semibold text-gray-900">Attendance Matrix</h2>
            <span v-if="!authStore.isAuthenticated" class="text-xs text-gray-500 italic"
              >(Read-only)</span
            >
          </div>
          <!-- Add Members to Session -->
          <div
            v-if="authStore.isAuthenticated"
            class="flex items-center gap-2 w-full sm:w-auto relative"
            ref="dropdownRef"
          >
            <div class="relative w-full sm:w-64">
              <button
                @click="showMemberDropdown = !showMemberDropdown"
                class="flex items-center justify-between w-full rounded-md border-gray-300 shadow-sm bg-white border px-3 py-1.5 text-sm cursor-pointer focus:ring-2 focus:ring-indigo-500 focus:outline-none"
              >
                <span v-if="selectedMemberIds.length === 0" class="text-gray-500"
                  >Select members...</span
                >
                <span v-else class="text-gray-900 font-medium"
                  >{{ selectedMemberIds.length }} selected</span
                >
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
                  No more active members
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
              Register
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
                  Member
                </th>
                <th
                  v-if="authStore.isAuthenticated"
                  scope="col"
                  class="px-2 py-3 text-center text-sm font-medium text-gray-500 uppercase tracking-wider w-12"
                >
                  <span class="sr-only">Actions</span>
                </th>
                <th
                  v-if="authStore.isAuthenticated"
                  scope="col"
                  class="px-2 py-3 text-center text-sm font-medium text-gray-500 uppercase tracking-wider w-16"
                >
                  Absent
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
                  class="sticky left-0 z-10 bg-white px-6 py-4 whitespace-nowrap text-base font-medium text-gray-900 border-r border-gray-200 shadow-[2px_0_5_rgba(0,0,0,0.05)]"
                >
                  <div class="flex items-center">
                    {{ reg.member?.display_name }}
                    <span
                      v-if="reg.is_registered_not_attended"
                      class="ml-2 text-sm text-red-500 font-normal italic"
                      >(Absent)</span
                    >
                  </div>
                </td>
                <td
                  v-if="authStore.isAuthenticated"
                  class="px-2 py-4 whitespace-nowrap text-center"
                >
                  <button
                    @click="removeRegistration(reg.id, reg.member?.display_name || '')"
                    class="text-gray-300 hover:text-red-500 transition focus:outline-none"
                    title="Remove member from session"
                  >
                    <Trash2 class="w-4 h-4 mx-auto" />
                  </button>
                </td>
                <td
                  v-if="authStore.isAuthenticated"
                  class="px-2 py-4 whitespace-nowrap text-center"
                >
                  <button
                    @click="toggleAbsent(reg)"
                    class="text-gray-400 hover:text-red-600 transition focus:outline-none"
                    :class="{ 'text-red-600': reg.is_registered_not_attended }"
                    title="Mark as Registered but Absent"
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
                      :disabled="!authStore.isAuthenticated || reg.is_registered_not_attended"
                      class="h-5 w-5 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                    />
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Cost Summary -->
      <div class="bg-white rounded-lg shadow-sm overflow-hidden border border-gray-100">
        <div class="px-6 py-4 border-b border-gray-100 bg-gray-50">
          <h2 class="text-xl font-semibold text-gray-900">Cost Summary</h2>
        </div>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th
                  scope="col"
                  class="px-6 py-3 text-left text-sm font-medium text-gray-500 uppercase tracking-wider"
                >
                  Member
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-right text-sm font-medium text-gray-500 uppercase tracking-wider font-bold"
                >
                  Total
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-center text-sm font-medium text-gray-500 uppercase tracking-wider"
                >
                  Intervals
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-right text-sm font-medium text-gray-500 uppercase tracking-wider"
                >
                  Court Fee
                </th>
                <th
                  scope="col"
                  class="px-6 py-3 text-right text-sm font-medium text-gray-500 uppercase tracking-wider"
                >
                  Shuttle Fee
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
                  Surplus Fund
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
</template>
