<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import type { SessionSummary } from '@/types'
import { format } from 'date-fns'
import { vi, enUS } from 'date-fns/locale'
import { Plus, ChevronRight } from 'lucide-vue-next'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { useToast } from 'vue-toastification'

const authStore = useAuthStore()
const langStore = useLangStore()
const toast = useToast()

const t = computed(() => langStore.t)
const dateLocale = computed(() => (langStore.currentLang === 'vi' ? vi : enUS))

const sessions = ref<SessionSummary[]>([])
const loading = ref(true)
const errorMessage = ref('')

async function fetchSessions() {
  try {
    loading.value = true
    errorMessage.value = ''
    const { data, error } = await supabase
      .from('view_session_summary')
      .select('*')
      .order('session_date', { ascending: false })

    if (error) throw error
    sessions.value = data || []
  } catch (error) {
    console.error('Error fetching sessions:', error)
    errorMessage.value = t.value('dashboard.loadError')
    toast.error(t.value('dashboard.loadError'))
  } finally {
    loading.value = false
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
      return 'bg-gray-100 text-gray-800'
    default:
      return 'bg-gray-100 text-gray-800'
  }
}

function getStatusLabel(status: string) {
  return t.value(`common.${status}`)
}

onMounted(fetchSessions)
</script>

<template>
  <div class="max-w-7xl mx-auto px-4 py-6 sm:px-6 lg:px-8">
    <div class="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
      <h1 class="text-[20px] font-bold leading-tight text-gray-900">{{ t('dashboard.title') }}</h1>
      <router-link
        v-if="authStore.isAdmin"
        to="/create-session"
        class="inline-flex min-h-11 items-center justify-center rounded-xl bg-indigo-600 px-4 py-2 text-sm font-bold text-white transition hover:bg-indigo-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
      >
        <Plus class="mr-2 h-5 w-5" />
        {{ t('dashboard.newSession') }}
      </router-link>
    </div>

    <div v-if="errorMessage" class="mb-4 rounded-xl border border-red-200 bg-red-50 p-4 text-sm font-bold text-red-700">
      {{ errorMessage }}
    </div>

    <div v-if="loading" class="flex justify-center py-12">
      <div class="h-12 w-12 animate-spin rounded-full border-b-2 border-indigo-600"></div>
    </div>

    <div
      v-else-if="sessions.length === 0"
      class="rounded-xl border border-gray-200 bg-white px-4 py-12 text-center shadow-sm"
    >
      <p class="text-gray-500">{{ t('dashboard.noSessions') }}</p>
    </div>

    <div v-else class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <router-link
        v-for="session in sessions"
        :key="session.id"
        :to="`/session/${session.id}`"
        :aria-label="t('dashboard.sessionCardAria', { title: session.title })"
        class="block rounded-xl border border-gray-200 bg-white p-4 shadow-sm transition hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
      >
        <div class="mb-3 flex items-start justify-between gap-3">
          <h2 class="text-[20px] font-bold leading-tight text-gray-900">{{ session.title }}</h2>
          <span
            :class="['shrink-0 rounded-full px-2 py-1 text-sm font-bold leading-tight', getStatusColor(session.status)]"
          >
            {{ getStatusLabel(session.status) }}
          </span>
        </div>
        <p class="mb-4 text-sm font-bold capitalize text-gray-600">
          {{ format(new Date(session.session_date), 'EEEE, dd/MM/yyyy', { locale: dateLocale }) }}
        </p>
        <div class="grid grid-cols-2 gap-3 text-sm text-gray-600">
          <span class="rounded-xl bg-gray-50 px-3 py-2 font-bold tabular-nums">
            {{ session.total_intervals }} {{ t('dashboard.intervals') }}
          </span>
          <span class="rounded-xl bg-gray-50 px-3 py-2 text-right font-bold tabular-nums">
            {{ session.total_registrations }} {{ t('dashboard.registrations') }}
          </span>
        </div>
        <div class="mt-4 flex min-h-11 items-center justify-between rounded-xl text-sm font-bold text-indigo-600">
          {{ t('dashboard.viewDetails') }}
          <ChevronRight class="h-4 w-4" />
        </div>
      </router-link>
    </div>
  </div>
</template>
