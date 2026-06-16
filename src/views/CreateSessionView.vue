<script setup lang="ts">
import { ref, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { useToast } from 'vue-toastification'
import { ChevronLeft, Plus, Trash2 } from 'lucide-vue-next'

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

interface BookingSlot {
  court_name: string
  start_time: string
  end_time: string
}

const bookings = ref<BookingSlot[]>([
  { court_name: 'Sân 1', start_time: '18:00', end_time: '20:00' },
])

const loading = ref(false)

const startDateTime = computed(() => {
  return `${form.value.date}T${form.value.startTime}:00`
})

const endDateTime = computed(() => {
  return `${form.value.date}T${form.value.endTime}:00`
})

function addBooking() {
  const name = `Sân ${bookings.value.length + 1}`
  bookings.value.push({
    court_name: name,
    start_time: form.value.startTime,
    end_time: form.value.endTime,
  })
  toast.success(t.value('createSession.courtAdded', { name, start: form.value.startTime, end: form.value.endTime }))
}

function removeBooking(index: number) {
  if (bookings.value.length <= 1) return
  bookings.value.splice(index, 1)
}

function isBookingEndBeforeStart(booking: BookingSlot): boolean {
  return booking.start_time >= booking.end_time
}

function isBookingOutOfBounds(booking: BookingSlot): boolean {
  return booking.start_time < form.value.startTime || booking.end_time > form.value.endTime
}

function validateBookingTime(index: number) {
  const booking = bookings.value[index]
  if (!booking) return
  if (booking.start_time >= booking.end_time) {
    toast.error(t.value('createSession.courtEndTimeError'))
    return
  }
  if (booking.start_time < form.value.startTime || booking.end_time > form.value.endTime) {
    toast.warning(t.value('createSession.courtTimeError'))
  }
}

async function createSession() {
  if (!authStore.user) return

  // Basic validation
  if (startDateTime.value >= endDateTime.value) {
    toast.error(t.value('createSession.endTimeError'))
    return
  }

  // Validate court bookings
  for (const b of bookings.value) {
    if (b.start_time >= b.end_time) {
      toast.error(t.value('createSession.courtEndTimeError'))
      return
    }
    if (b.start_time < form.value.startTime || b.end_time > form.value.endTime) {
      toast.error(t.value('createSession.courtTimeError'))
      return
    }
  }

  try {
    loading.value = true
    const startTime = new Date(startDateTime.value).toISOString()
    const endTime = new Date(endDateTime.value).toISOString()
    const pBookings = bookings.value.map((b) => ({
      court_name: b.court_name,
      start_time: new Date(`${form.value.date}T${b.start_time}:00`).toISOString(),
      end_time: new Date(`${form.value.date}T${b.end_time}:00`).toISOString(),
    }))

    const { data: sessionId, error } = await supabase.rpc('create_session_with_bookings', {
      p_title: form.value.title,
      p_start_time: startTime,
      p_end_time: endTime,
      p_price_per_hour: 0,
      p_shuttle_fee: form.value.shuttleFee,
      p_created_by: authStore.user.id,
      p_bookings: pBookings,
      p_court_fee_addon: form.value.courtFee,
    })

    if (error) throw error
    if (!sessionId) {
      toast.error(t.value('createSession.createError'))
      return
    }

    toast.success(t.value('toast.sessionCreated'))
    router.push({ name: 'session-detail', params: { id: sessionId }, query: { register: 'true' } })
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
        to="/sessions"
        class="inline-flex min-h-11 items-center text-sm font-bold text-indigo-600 transition hover:text-indigo-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
      >
        <ChevronLeft class="mr-1 h-5 w-5" />
        {{ t('common.backToSessions') }}
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

        <!-- Court Bookings -->
        <div>
          <div class="flex items-center justify-between mb-2">
            <label class="block text-sm font-bold text-gray-700">{{ t('session.courtBookings') }}</label>
            <button
              type="button"
              @click="addBooking"
              class="flex items-center text-sm text-indigo-600 hover:text-indigo-800 font-bold"
            >
              <Plus class="w-4 h-4 mr-1" />
              {{ t('createSession.addCourt') }}
            </button>
          </div>
          <div class="space-y-2">
            <div
              v-for="(booking, index) in bookings"
              :key="index"
              class="flex flex-col gap-2 p-3 bg-gray-50 rounded-xl border border-gray-200"
            >
              <div class="flex items-end gap-2">
                <div class="flex-1 min-w-0">
                  <label class="block text-xs text-gray-500 mb-1">{{
                    t('createSession.courtName')
                  }}</label>
                  <input
                    v-model="booking.court_name"
                    type="text"
                    class="block w-full rounded-lg border border-gray-300 text-sm px-3 py-1.5 focus:border-indigo-500 focus:ring-indigo-500"
                  />
                </div>
                <div class="w-24">
                  <label class="block text-xs text-gray-500 mb-1">{{
                    t('createSession.startTime')
                  }}</label>
                  <input
                    v-model="booking.start_time"
                    type="time"
                    class="block w-full rounded-lg border border-gray-300 text-sm px-2 py-1.5 focus:border-indigo-500 focus:ring-indigo-500"
                    @change="validateBookingTime(index)"
                  />
                </div>
                <div class="w-24">
                  <label class="block text-xs text-gray-500 mb-1">{{
                    t('createSession.endTime')
                  }}</label>
                  <input
                    v-model="booking.end_time"
                    type="time"
                    class="block w-full rounded-lg border border-gray-300 text-sm px-2 py-1.5 focus:border-indigo-500 focus:ring-indigo-500"
                    @change="validateBookingTime(index)"
                  />
                </div>
                <button
                  type="button"
                  @click="removeBooking(index)"
                  :disabled="bookings.length <= 1"
                  class="p-1.5 text-gray-400 hover:text-red-500 transition disabled:opacity-30"
                >
                  <Trash2 class="w-4 h-4" />
                </button>
              </div>
              <div
                v-if="isBookingEndBeforeStart(booking)"
                class="flex items-center gap-1.5 text-xs text-red-700 bg-red-50 border border-red-200 rounded-lg px-2 py-1.5"
              >
                <span>&#x26A0;</span>
                <span>{{ t('createSession.courtEndTimeError') }}</span>
              </div>
              <div
                v-else-if="isBookingOutOfBounds(booking)"
                class="flex items-center gap-1.5 text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-lg px-2 py-1.5"
              >
                <span>&#x26A0;</span>
                <span>{{ t('createSession.courtTimeError') }} ({{ form.startTime }} – {{ form.endTime }})</span>
              </div>
            </div>
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
