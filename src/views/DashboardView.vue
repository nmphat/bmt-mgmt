<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import type { SessionSummary } from '@/types'
import { format } from 'date-fns'
import { Plus, ChevronRight } from 'lucide-vue-next'
import { useAuthStore } from '@/stores/auth'

const authStore = useAuthStore()
const sessions = ref<SessionSummary[]>([])
const loading = ref(true)

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

function getStatusColor(status: string) {
  switch (status) {
    case 'active': return 'bg-green-100 text-green-800'
    case 'closed': return 'bg-gray-100 text-gray-800'
    case 'draft': return 'bg-yellow-100 text-yellow-800'
    default: return 'bg-blue-100 text-blue-800'
  }
}

onMounted(fetchSessions)
</script>

<template>
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <div class="flex justify-between items-center mb-6">
      <h1 class="text-2xl font-bold text-gray-900">Badminton Sessions</h1>
      <router-link
        v-if="authStore.isAuthenticated"
        to="/create-session"
        class="flex items-center px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition"
      >
        <Plus class="w-5 h-5 mr-2" />
        New Session
      </router-link>
    </div>

    <div v-if="loading" class="flex justify-center py-12">
      <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
    </div>

    <div v-else-if="sessions.length === 0" class="text-center py-12 bg-white rounded-lg shadow">
      <p class="text-gray-500">No sessions found.</p>
    </div>

    <div v-else class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <router-link
        v-for="session in sessions"
        :key="session.id"
        :to="`/session/${session.id}`"
        class="block bg-white rounded-lg shadow hover:shadow-md transition p-4 border border-gray-100"
      >
        <div class="flex justify-between items-start mb-2">
          <h2 class="text-lg font-semibold text-gray-900">{{ session.title }}</h2>
          <span :class="['px-2 py-1 text-xs font-medium rounded-full', getStatusColor(session.status)]">
            {{ session.status }}
          </span>
        </div>
        <p class="text-sm text-gray-600 mb-4">
          {{ format(new Date(session.session_date), 'EEEE, dd/MM/yyyy') }}
        </p>
        <div class="flex justify-between text-xs text-gray-500">
          <span>{{ session.total_intervals }} intervals</span>
          <span>{{ session.total_registrations }} registrations</span>
        </div>
        <div class="mt-4 flex items-center text-indigo-600 text-sm font-medium">
          View details
          <ChevronRight class="w-4 h-4 ml-1" />
        </div>
      </router-link>
    </div>
  </div>
</template>
