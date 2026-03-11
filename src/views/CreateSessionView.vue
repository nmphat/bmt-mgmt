<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { supabase } from '@/lib/supabase'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { useToast } from 'vue-toastification'
import { ChevronLeft, Trash2, Plus } from 'lucide-vue-next'

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
  pricePerHour: 0,
  courtFeeAddon: 0,
  shuttleFee: 0,
})

interface CourtSlot {
  name: string
  start: string
  end: string
}

const courts = ref<CourtSlot[]>([{ name: 'Sân 1', start: '18:00', end: '20:00' }])

const loading = ref(false)

const startDateTime = computed(() => {
  return `${form.value.date}T${form.value.startTime}:00+07:00`
})

const endDateTime = computed(() => {
  return `${form.value.date}T${form.value.endTime}:00+07:00`
})

// Sync first court slot times when session times change
watch(
  () => [form.value.startTime, form.value.endTime] as [string, string],
  ([newStart, newEnd]) => {
    if (courts.value.length === 1 && courts.value[0]) {
      courts.value[0].start = newStart
      courts.value[0].end = newEnd
    }
  },
)

function addCourt() {
  const name = `Sân ${courts.value.length + 1}`
  const start = form.value.startTime
  const end = form.value.endTime
  courts.value.push({ name, start, end })
  toast.success(t.value('createSession.courtAdded', { name, start, end }))
}

function removeCourt(index: number) {
  if (courts.value.length <= 1) return
  courts.value.splice(index, 1)
}

function isCourtOutOfBounds(court: CourtSlot): boolean {
  return court.start < form.value.startTime || court.end > form.value.endTime
}

function isCourtEndBeforeStart(court: CourtSlot): boolean {
  return court.start >= court.end
}

function validateCourtTime(index: number) {
  const court = courts.value[index]
  if (!court) return
  if (court.start >= court.end) {
    toast.error(t.value('createSession.courtEndTimeError'))
    return
  }
  if (court.start < form.value.startTime || court.end > form.value.endTime) {
    toast.warning(t.value('createSession.courtTimeError'))
  }
}

function validateCourts(): boolean {
  for (const court of courts.value) {
    if (court.start < form.value.startTime || court.end > form.value.endTime) {
      toast.error(t.value('createSession.courtTimeError'))
      return false
    }
    if (court.start >= court.end) {
      toast.error(t.value('createSession.courtEndTimeError'))
      return false
    }
  }
  return true
}

async function createSession() {
  // logger for testing
  console.log('createSession')

  if (!authStore.user) return

  // Basic validation
  if (startDateTime.value >= endDateTime.value) {
    toast.error(t.value('createSession.endTimeError'))
    return
  }

  if (!validateCourts()) return

  try {
    loading.value = true

    const bookings = courts.value.map((c) => ({
      court_name: c.name,
      start_time: new Date(`${form.value.date}T${c.start}:00+07:00`).toISOString(),
      end_time: new Date(`${form.value.date}T${c.end}:00+07:00`).toISOString(),
    }))

    const { data: createdSessionId, error } = await supabase.rpc('create_session_with_bookings', {
      p_title: form.value.title,
      p_start_time: new Date(startDateTime.value).toISOString(),
      p_end_time: new Date(endDateTime.value).toISOString(),
      p_price_per_hour: form.value.pricePerHour,
      p_court_fee_addon: form.value.courtFeeAddon,
      p_shuttle_fee: form.value.shuttleFee,
      p_created_by: authStore.user.id,
      p_bookings: bookings,
    })

    if (error) throw error

    toast.success(t.value('toast.sessionCreated'))
    if (createdSessionId) {
      await router.push({
        name: 'session-detail',
        params: { id: createdSessionId },
        query: { openMemberDropdown: '1' },
      })
    } else {
      await router.push('/')
    }
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
            <label for="pricePerHour" class="block text-sm font-medium text-gray-700"
              >{{ t('session.pricePerHour') }} (VND)</label
            >
            <input
              v-model.number="form.pricePerHour"
              type="number"
              id="pricePerHour"
              min="0"
              step="1000"
              required
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
            />
          </div>
          <div>
            <label for="courtFeeAddon" class="block text-sm font-medium text-gray-700"
              >{{ t('session.courtFeeAddon') }} (VND)</label
            >
            <input
              v-model.number="form.courtFeeAddon"
              type="number"
              id="courtFeeAddon"
              min="0"
              step="1000"
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
            />
          </div>
          <div class="col-span-2">
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
        <!-- Warning: both cost sources active -->
        <div
          v-if="form.pricePerHour > 0 && form.courtFeeAddon > 0"
          class="flex items-start gap-2 p-3 bg-amber-50 border border-amber-200 rounded-lg text-xs text-amber-800"
        >
          <span class="mt-0.5">⚠️</span>
          <span>{{ t('session.courtFeeAddonWarning') }}</span>
        </div>

        <!-- Court Bookings -->
        <div>
          <div class="flex items-center justify-between mb-3">
            <label class="block text-sm font-medium text-gray-700">{{
              t('session.courtBookings')
            }}</label>
            <button
              type="button"
              @click="addCourt"
              class="flex items-center text-sm text-indigo-600 hover:text-indigo-800 font-medium transition"
            >
              <Plus class="w-4 h-4 mr-1" />
              {{ t('createSession.addCourt') }}
            </button>
          </div>
          <div class="space-y-3">
            <div
              v-for="(court, index) in courts"
              :key="index"
              class="flex flex-col gap-2 p-3 bg-gray-50 rounded-lg border border-gray-200"
            >
              <div class="grid grid-cols-2 gap-2 sm:flex sm:items-end sm:gap-3">
                <div class="col-span-2 sm:flex-1 sm:min-w-0">
                  <label class="block text-xs font-medium text-gray-500 mb-1">{{
                    t('createSession.courtName')
                  }}</label>
                  <input
                    v-model="court.name"
                    type="text"
                    required
                    :placeholder="t('createSession.courtNamePlaceholder')"
                    class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-1.5"
                  />
                </div>
                <div class="sm:w-28">
                  <label class="block text-xs font-medium text-gray-500 mb-1">{{
                    t('createSession.startTime')
                  }}</label>
                  <input
                    v-model="court.start"
                    type="time"
                    required
                    class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-1.5"
                    @change="validateCourtTime(index)"
                  />
                </div>
                <div class="sm:w-28">
                  <label class="block text-xs font-medium text-gray-500 mb-1">{{
                    t('createSession.endTime')
                  }}</label>
                  <input
                    v-model="court.end"
                    type="time"
                    required
                    class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-1.5"
                    @change="validateCourtTime(index)"
                  />
                </div>
                <div class="flex items-end justify-end col-span-2 sm:col-span-1">
                  <button
                    type="button"
                    @click="removeCourt(index)"
                    :disabled="courts.length <= 1"
                    class="p-1.5 text-gray-400 hover:text-red-500 transition disabled:opacity-30 disabled:cursor-not-allowed"
                    :title="t('createSession.removeCourt')"
                  >
                    <Trash2 class="w-4 h-4" />
                  </button>
                </div>
              </div>
              <div
                v-if="isCourtEndBeforeStart(court)"
                class="flex items-center gap-1.5 text-xs text-red-700 bg-red-50 border border-red-200 rounded px-2 py-1.5"
              >
                <span>&#x26A0;</span>
                <span>{{ t('createSession.courtEndTimeError') }}</span>
              </div>
              <div
                v-else-if="isCourtOutOfBounds(court)"
                class="flex items-center gap-1.5 text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded px-2 py-1.5"
              >
                <span>&#x26A0;</span>
                <span
                  >{{ t('createSession.courtTimeError') }} ({{ form.startTime }} –
                  {{ form.endTime }})</span
                >
              </div>
            </div>
          </div>
        </div>

        <div class="pt-4 sticky bottom-0 bg-white pb-safe">
          <button
            type="submit"
            :disabled="loading"
            class="w-full flex justify-center py-3 px-4 border border-transparent rounded-xl shadow-sm text-sm font-bold text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {{ loading ? t('createSession.creating') : t('createSession.createButton') }}
          </button>
        </div>
      </form>
    </div>
  </div>
</template>
