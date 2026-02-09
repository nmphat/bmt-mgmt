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
    const { error } = await supabase.rpc('create_session_with_intervals', {
      p_title: form.value.title,
      p_start_time: new Date(startDateTime.value).toISOString(),
      p_end_time: new Date(endDateTime.value).toISOString(),
      p_court_fee: form.value.courtFee,
      p_shuttle_fee: form.value.shuttleFee,
      p_created_by: authStore.user.id,
    })

    if (error) throw error

    toast.success(t.value('toast.sessionCreated'))
    router.push('/')
  } catch (error: any) {
    console.error('Error creating session:', error)
    toast.error(error.message || t.value('session.updateError'))
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <div class="mb-6">
      <router-link
        to="/"
        class="flex items-center text-indigo-600 hover:text-indigo-800 transition"
      >
        <ChevronLeft class="w-5 h-5 mr-1" />
        {{ t('common.backToHome') }}
      </router-link>
    </div>

    <div class="bg-white shadow-sm rounded-lg border border-gray-100 p-6">
      <h1 class="text-2xl font-bold text-gray-900 mb-6">{{ t('createSession.title') }}</h1>

      <form @submit.prevent="createSession" class="space-y-6">
        <div>
          <label for="title" class="block text-sm font-medium text-gray-700">{{
            t('session.title')
          }}</label>
          <input
            v-model="form.title"
            type="text"
            id="title"
            required
            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
            :placeholder="t('createSession.titlePlaceholder')"
          />
        </div>

        <div>
          <label for="date" class="block text-sm font-medium text-gray-700">{{
            t('createSession.date')
          }}</label>
          <input
            v-model="form.date"
            type="date"
            id="date"
            required
            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
          />
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div>
            <label for="startTime" class="block text-sm font-medium text-gray-700">{{
              t('createSession.startTime')
            }}</label>
            <input
              v-model="form.startTime"
              type="time"
              id="startTime"
              required
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
            />
          </div>
          <div>
            <label for="endTime" class="block text-sm font-medium text-gray-700">{{
              t('createSession.endTime')
            }}</label>
            <input
              v-model="form.endTime"
              type="time"
              id="endTime"
              required
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
            />
          </div>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div>
            <label for="courtFee" class="block text-sm font-medium text-gray-700"
              >{{ t('session.courtFee') }} (VND)</label
            >
            <input
              v-model.number="form.courtFee"
              type="number"
              id="courtFee"
              min="0"
              step="1000"
              required
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
            />
          </div>
          <div>
            <label for="shuttleFee" class="block text-sm font-medium text-gray-700"
              >{{ t('session.shuttleFee') }} (VND)</label
            >
            <input
              v-model.number="form.shuttleFee"
              type="number"
              id="shuttleFee"
              min="0"
              step="1000"
              required
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
            />
          </div>
        </div>

        <div class="pt-4">
          <button
            type="submit"
            :disabled="loading"
            class="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {{ loading ? t('createSession.creating') : t('createSession.createButton') }}
          </button>
        </div>
      </form>
    </div>
  </div>
</template>
