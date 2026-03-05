<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import type { SessionSummary } from '@/types'
import { format } from 'date-fns'
import { vi, enUS } from 'date-fns/locale'
import { Plus, ChevronRight, Calendar, Users, Clock } from 'lucide-vue-next'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { formatCurrency } from '@/utils/formatters'

const authStore = useAuthStore()
const langStore = useLangStore()

const t = computed(() => langStore.t)
const dateLocale = computed(() => (langStore.currentLang === 'vi' ? vi : enUS))

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

    <!-- Empty -->
    <div
      v-else-if="sessions.length === 0"
      class="text-center py-16 bg-white rounded-xl border border-gray-100"
    >
      <Calendar class="w-12 h-12 text-gray-300 mx-auto mb-3" />
      <p class="text-gray-400 font-medium">{{ t('dashboard.noSessions') }}</p>
    </div>

    <!-- Session cards -->
    <div v-else class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <router-link
        v-for="session in sessions"
        :key="session.id"
        :to="`/session/${session.id}`"
        class="block bg-white rounded-xl border border-gray-100 border-l-4 hover:shadow-md active:scale-[0.99] transition-all p-4"
        :class="getStatusBorder(session.status)"
      >
        <!-- Title + status badge -->
        <div class="flex justify-between items-start gap-2 mb-1.5">
          <h2 class="text-base font-semibold text-gray-900 leading-snug line-clamp-2">
            {{ session.title }}
          </h2>
          <span
            class="flex-shrink-0 px-2 py-0.5 text-xs font-medium rounded-full"
            :class="getStatusColor(session.status)"
          >
            {{ getStatusLabel(session.status) }}
          </span>
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
            {{ formatCurrency(session.court_fee_total + session.shuttle_fee_total) }}
          </span>
        </div>

        <!-- View link — desktop only (whole card is tappable on mobile) -->
        <div class="hidden md:flex items-center mt-3 pt-3 border-t border-gray-50 text-indigo-600 text-xs font-medium">
          {{ t('dashboard.viewDetails') }}
          <ChevronRight class="w-3.5 h-3.5 ml-0.5" />
        </div>
      </router-link>
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
