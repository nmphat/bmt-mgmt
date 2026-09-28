<script setup lang="ts">
import { ref, onMounted, computed, watch } from 'vue'
import { supabase } from '@/lib/supabase'
import type { SessionSummary } from '@/types'
import { format } from 'date-fns'
import { vi, enUS } from 'date-fns/locale'
import { Plus, ChevronRight } from 'lucide-vue-next'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { useToast } from 'vue-toastification'
import Alert from '@/components/ui/Alert.vue'
import Button from '@/components/ui/Button.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import PageHeader from '@/components/ui/PageHeader.vue'
import SessionStatusBadge from '@/components/ui/SessionStatusBadge.vue'
import Spinner from '@/components/ui/Spinner.vue'

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
    let query = supabase
      .from('view_session_summary')
      .select('*')
      .order('session_date', { ascending: false })

    if (!authStore.isAdmin) {
      query = query.in('status', ['waiting_for_payment', 'done'])
    }

    const { data, error } = await query

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

const STATUS_DS = {
  open: 'Open',
  waiting_for_payment: 'Waiting For Payment',
  done: 'Done',
  cancelled: 'Cancelled',
} as const
const dsStatus = (s: string) => STATUS_DS[s as keyof typeof STATUS_DS] ?? 'Cancelled'

onMounted(fetchSessions)
watch(
  () => authStore.isAdmin,
  () => fetchSessions(),
)
</script>

<template>
  <div class="max-w-7xl mx-auto px-4 py-6 sm:px-6 lg:px-8">
    <PageHeader
      :layout="authStore.isAdmin ? 'Title Action' : 'Title'"
      :title="t('dashboard.title')"
      class="mb-6"
    >
      <template #actions>
        <Button
          v-if="authStore.isAdmin"
          as="RouterLink"
          to="/create-session?from=sessions"
          size="Default"
          variant="Primary"
          :leading-icon="Plus"
        >
          {{ t('dashboard.newSession') }}
        </Button>
      </template>
    </PageHeader>

    <Alert v-if="errorMessage" tone="Danger" variant="Box" class="mb-4">
      {{ errorMessage }}
    </Alert>

    <div v-if="loading" class="flex justify-center py-12">
      <Spinner size="48" tone="Brand" />
    </div>

    <EmptyState v-else-if="sessions.length === 0" variant="Card">
      {{ t('dashboard.noSessions') }}
    </EmptyState>

    <div v-else class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <router-link
        v-for="session in sessions"
        :key="session.id"
        :to="`/session/${session.id}`"
        :aria-label="t('dashboard.sessionCardAria', { title: session.title })"
        class="flex flex-col gap-4 rounded-xl border border-line-divider bg-surface-card p-4 shadow-sm transition hover:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-line-focus focus-visible:ring-offset-2"
      >
        <div class="flex flex-col gap-3">
          <div class="flex items-start justify-between gap-3">
            <h2 class="text-xl font-bold text-fg-primary">{{ session.title }}</h2>
            <SessionStatusBadge :status="dsStatus(session.status)" />
          </div>
          <p class="text-sm font-bold capitalize text-fg-secondary">
            {{ format(new Date(session.session_date), 'EEEE, dd/MM/yyyy', { locale: dateLocale }) }}
          </p>
        </div>
        <div class="grid grid-cols-2 gap-3 text-sm text-fg-secondary">
          <span class="rounded-xl bg-surface-subtle px-3 py-2 font-bold tabular-nums">
            {{ session.total_intervals }} {{ t('dashboard.intervals') }}
          </span>
          <span class="rounded-xl bg-surface-subtle px-3 py-2 text-right font-bold tabular-nums">
            {{ session.total_registrations }} {{ t('dashboard.registrations') }}
          </span>
        </div>
        <div class="flex min-h-11 items-center justify-between text-sm font-bold text-fg-brand">
          {{ t('dashboard.viewDetails') }}
          <ChevronRight class="h-4 w-4" />
        </div>
      </router-link>
    </div>
  </div>
</template>
