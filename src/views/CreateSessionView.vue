<script setup lang="ts">
import { ref, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { useToast } from 'vue-toastification'
import { ChevronLeft } from 'lucide-vue-next'

const router = useRouter()
const authStore = useAuthStore()
const langStore = useLangStore()
const toast = useToast()
const t = computed(() => langStore.t)

const form = ref({
  title: '',
  date: new Date().toISOString().split('T')[0],
  startTime: '18:00',
  endTime: '20:00',
  courtFee: 0,
  shuttleFee: 0,
})

const loading = ref(false)

const startDateTime = computed(() => {
  return `${form.value.date}T${form.value.startTime}:00`
})

const endDateTime = computed(() => {
  return `${form.value.date}T${form.value.endTime}:00`
})

async function createSession() {
  if (!authStore.user) return

  // Basic validation
  if (startDateTime.value >= endDateTime.value) {
    toast.error(t.value('createSession.endTimeError'))
    return
  }

  try {
    loading.value = true
    const startTime = new Date(startDateTime.value).toISOString()
    const endTime = new Date(endDateTime.value).toISOString()
    const { error } = await supabase.rpc('create_session_with_bookings', {
      p_title: form.value.title,
      p_start_time: startTime,
      p_end_time: endTime,
      p_price_per_hour: 0,
      p_shuttle_fee: form.value.shuttleFee,
      p_created_by: authStore.user.id,
      p_bookings: [{ court_name: 'Sân 1', start_time: startTime, end_time: endTime }],
      p_court_fee_addon: form.value.courtFee,
    })

    if (error) throw error

    toast.success(t.value('toast.sessionCreated'))
    router.push('/')
  } catch (error: any) {
    console.error('Error creating session:', error)
    toast.error(error.message || t.value('createSession.createError'))
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="max-w-2xl mx-auto px-4 py-6 sm:px-6 lg:px-8">
    <div class="mb-6">
      <router-link
        to="/"
        class="inline-flex min-h-11 items-center text-sm font-bold text-indigo-600 transition hover:text-indigo-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
      >
        <ChevronLeft class="mr-1 h-5 w-5" />
        {{ t('common.backToHome') }}
      </router-link>
    </div>

    <div class="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm sm:p-6">
      <h1 class="mb-6 text-[20px] font-bold leading-tight text-gray-900">
        {{ t('createSession.title') }}
      </h1>

      <form @submit.prevent="createSession" class="space-y-6">
        <div>
          <label for="title" class="block text-sm font-bold text-gray-700">{{
            t('session.title')
          }}</label>
          <input
            v-model="form.title"
            type="text"
            id="title"
            required
            class="mt-1 block min-h-11 w-full rounded-xl border border-gray-300 px-3 py-2 text-base shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            :placeholder="t('createSession.titlePlaceholder')"
          />
        </div>

        <div>
          <label for="date" class="block text-sm font-bold text-gray-700">{{
            t('createSession.date')
          }}</label>
          <input
            v-model="form.date"
            type="date"
            id="date"
            required
            class="mt-1 block min-h-11 w-full rounded-xl border border-gray-300 px-3 py-2 text-base shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
          />
        </div>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label for="startTime" class="block text-sm font-bold text-gray-700">{{
              t('createSession.startTime')
            }}</label>
            <input
              v-model="form.startTime"
              type="time"
              id="startTime"
              required
              class="mt-1 block min-h-11 w-full rounded-xl border border-gray-300 px-3 py-2 text-base shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            />
          </div>
          <div>
            <label for="endTime" class="block text-sm font-bold text-gray-700">{{
              t('createSession.endTime')
            }}</label>
            <input
              v-model="form.endTime"
              type="time"
              id="endTime"
              required
              class="mt-1 block min-h-11 w-full rounded-xl border border-gray-300 px-3 py-2 text-base shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            />
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label for="courtFee" class="block text-sm font-bold text-gray-700"
              >{{ t('session.courtFee') }} (VND)</label
            >
            <input
              v-model.number="form.courtFee"
              type="number"
              id="courtFee"
              min="0"
              step="1000"
              required
              class="mt-1 block min-h-11 w-full rounded-xl border border-gray-300 px-3 py-2 text-base shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            />
          </div>
          <div>
            <label for="shuttleFee" class="block text-sm font-bold text-gray-700"
              >{{ t('session.shuttleFee') }} (VND)</label
            >
            <input
              v-model.number="form.shuttleFee"
              type="number"
              id="shuttleFee"
              min="0"
              step="1000"
              required
              class="mt-1 block min-h-11 w-full rounded-xl border border-gray-300 px-3 py-2 text-base shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            />
          </div>
        </div>

        <div class="pt-4">
          <button
            type="submit"
            :disabled="loading"
            class="flex min-h-11 w-full justify-center rounded-xl bg-indigo-600 px-4 py-3 text-base font-bold text-white shadow-sm transition hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {{ loading ? t('createSession.creating') : t('createSession.createButton') }}
          </button>
        </div>
      </form>
    </div>
  </div>
</template>
