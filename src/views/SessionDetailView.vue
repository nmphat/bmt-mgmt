<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '@/lib/supabase'
import type { SessionSummary, Interval, SessionRegistration, MemberCost } from '@/types'
import { format } from 'date-fns'
import { ChevronLeft, RefreshCcw, UserX } from 'lucide-vue-next'
import { useAuthStore } from '@/stores/auth'
import type { RealtimeChannel } from '@supabase/supabase-js'

const route = useRoute()
const authStore = useAuthStore()
const sessionId = route.params.id as string

const session = ref<SessionSummary | null>(null)
const intervals = ref<Interval[]>([])
const registrations = ref<SessionRegistration[]>([])
const presence = ref<Record<string, Record<string, boolean>>>({}) // memberId -> intervalId -> isPresent
const costs = ref<MemberCost[]>([])
const loading = ref(true)
let realtimeChannel: RealtimeChannel | null = null

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

      // Fetch intervals
      const { data: intervalsData } = await supabase
        .from('session_intervals')
        .select('*')
        .eq('session_id', sessionId)
        .order('idx', { ascending: true })
      intervals.value = intervalsData || []
    }

    // Fetch registrations (with member details)
    const { data: regsData } = await supabase
      .from('session_registrations')
      .select('*, member:members(*)')
      .eq('session_id', sessionId)
    registrations.value = regsData || []

    // Fetch presence
    const { data: presenceData } = await supabase
      .from('interval_presence')
      .select('*')
      .in('interval_id', intervals.value.map(i => i.id))
    
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

async function fetchCosts() {
  const { data, error } = await supabase.rpc('calculate_session_costs', { p_session_id: sessionId })
  if (!error) {
    costs.value = data
  }
}

async function togglePresence(memberId: string, intervalId: string) {
  if (!authStore.isAdmin) return

  const currentMemberPresence = presence.value[memberId]
  if (!currentMemberPresence) return

  const newValue = !currentMemberPresence[intervalId]
  
  // Optimistic update
  if (presence.value[memberId]) {
    presence.value[memberId][intervalId] = newValue
  }

  const { error } = await supabase
    .from('interval_presence')
    .upsert({ 
      interval_id: intervalId, 
      member_id: memberId, 
      is_present: newValue 
    }, { onConflict: 'interval_id, member_id' })

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
  if (!authStore.isAdmin) return

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

  realtimeChannel = supabase.channel(`session-${sessionId}`)
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'interval_presence' },
      () => fetchData(true)
    )
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'session_registrations', filter: `session_id=eq.${sessionId}` },
      () => fetchData(true)
    )
    .subscribe()
})

onUnmounted(() => {
  if (realtimeChannel) {
    supabase.removeChannel(realtimeChannel)
  }
})
</script>

<template>
  <div class="max-w-full mx-auto px-4 sm:px-6 lg:px-8 py-6">
    <div class="mb-6 flex items-center justify-between">
      <router-link to="/" class="flex items-center text-indigo-600 hover:text-indigo-800 transition">
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
        <div class="flex justify-between items-start">
          <div>
            <h1 class="text-2xl font-bold text-gray-900 mb-2">{{ session.title }}</h1>
            <p class="text-gray-600">
              {{ format(new Date(session.session_date), 'EEEE, dd/MM/yyyy') }}
            </p>
          </div>
          <div class="text-right">
             <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
               {{ session.status }}
             </span>
          </div>
        </div>
      </div>

      <!-- Attendance Matrix -->
      <div class="bg-white rounded-lg shadow-sm overflow-hidden mb-8 border border-gray-100">
        <div class="px-6 py-4 border-b border-gray-100 bg-gray-50 flex justify-between items-center">
          <h2 class="text-lg font-semibold text-gray-900">Attendance Matrix</h2>
          <span v-if="!authStore.isAdmin" class="text-xs text-gray-500 italic">Read-only view</span>
        </div>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th scope="col" class="sticky left-0 z-10 bg-gray-50 px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider border-r border-gray-200 shadow-[2px_0_5px_rgba(0,0,0,0.05)] w-48">
                  Member
                </th>
                <th v-if="authStore.isAdmin" scope="col" class="px-2 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider w-16">
                  Absent
                </th>
                <th v-for="interval in intervals" :key="interval.id" scope="col" class="px-3 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider min-w-[60px]">
                  {{ formatTime(interval.start_time) }}
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <tr v-for="reg in registrations" :key="reg.id" :class="{ 'opacity-60 bg-gray-50': reg.is_registered_not_attended }">
                <td class="sticky left-0 z-10 bg-white px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900 border-r border-gray-200 shadow-[2px_0_5px_rgba(0,0,0,0.05)]">
                  <div class="flex items-center">
                    {{ reg.member?.display_name }}
                    <span v-if="reg.is_registered_not_attended" class="ml-2 text-xs text-red-500">(Absent)</span>
                  </div>
                </td>
                <td v-if="authStore.isAdmin" class="px-2 py-4 whitespace-nowrap text-center">
                  <button 
                    @click="toggleAbsent(reg)"
                    class="text-gray-400 hover:text-red-600 transition focus:outline-none"
                    :class="{ 'text-red-600': reg.is_registered_not_attended }"
                    title="Mark as Registered but Absent"
                  >
                    <UserX class="w-5 h-5 mx-auto" />
                  </button>
                </td>
                <td v-for="interval in intervals" :key="interval.id" class="px-3 py-4 whitespace-nowrap text-center">
                  <input
                    type="checkbox"
                    :checked="presence[reg.member_id]?.[interval.id] || false"
                    @change="togglePresence(reg.member_id, interval.id)"
                    :disabled="!authStore.isAdmin || reg.is_registered_not_attended"
                    class="h-5 w-5 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Cost Summary -->
      <div class="bg-white rounded-lg shadow-sm overflow-hidden border border-gray-100">
        <div class="px-6 py-4 border-b border-gray-100 bg-gray-50">
          <h2 class="text-lg font-semibold text-gray-900">Cost Summary</h2>
        </div>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Member</th>
                <th scope="col" class="px-6 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">Intervals</th>
                <th scope="col" class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Court Fee</th>
                <th scope="col" class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Shuttle Fee</th>
                <th scope="col" class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider font-bold">Total</th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <tr v-for="cost in costs" :key="cost.member_id">
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">{{ cost.display_name }}</td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-center text-gray-500">{{ cost.intervals_count }}</td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-right text-gray-500">{{ formatCurrency(cost.total_court_fee) }}</td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-right text-gray-500">{{ formatCurrency(cost.total_shuttle_fee) }}</td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-right font-bold text-gray-900">{{ formatCurrency(cost.final_total) }}</td>
              </tr>
              <!-- Surplus Row -->
               <tr class="bg-gray-50">
                 <td colspan="4" class="px-6 py-4 text-right text-sm font-bold text-gray-700">Surplus Fund</td>
                 <td class="px-6 py-4 text-right text-sm font-bold text-green-600">{{ formatCurrency(surplus) }}</td>
               </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
</template>

