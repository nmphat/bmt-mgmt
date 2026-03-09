<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { format } from 'date-fns'
import { vi, enUS } from 'date-fns/locale'
import {
  ChevronLeft,
  Edit,
  X,
  Save,
  Lock,
  Loader2,
  Plus,
  Trash2,
  RefreshCcw,
} from 'lucide-vue-next'
import { useLangStore } from '@/stores/lang'
import { useAuthStore } from '@/stores/auth'
import { supabase } from '@/lib/supabase'
import { useToast } from 'vue-toastification'
import type { SessionSummary, CourtBooking, MemberCost, CostSnapshot } from '@/types'

const props = defineProps<{
  session: SessionSummary
  courtBookings: CourtBooking[]
  costs: MemberCost[]
  snapshots: (CostSnapshot & { display_name: string })[]
  sessionId: string
  loading?: boolean
}>()

const emit = defineEmits<{
  dataChanged: []
  refresh: []
  deleteRequested: []
}>()

const langStore = useLangStore()
const authStore = useAuthStore()
const toast = useToast()
const t = computed(() => langStore.t)
const dateLocale = computed(() => (langStore.currentLang === 'vi' ? vi : enUS))

const isEditingSession = ref(false)
const isSavingSession = ref(false)
const finalizeLoading = ref(false)

/** True when the user has changed session start or end time in the edit form */
const timesChanged = computed(
  () =>
    sessionForm.value.session_start !== toVNHHmm(props.session.start_time) ||
    sessionForm.value.session_end !== toVNHHmm(props.session.end_time),
)

interface EditBookingSlot {
  id?: string
  court_name: string
  start_time: string
  end_time: string
}

/** Convert ISO UTC string → "HH:mm" in Vietnam timezone (UTC+7) */
function toVNHHmm(iso: string): string {
  const vnMs = new Date(iso).getTime() + 7 * 3600 * 1000
  return new Date(vnMs).toISOString().slice(11, 16)
}

const sessionForm = ref({
  title: props.session.title,
  status: props.session.status,
  session_start: toVNHHmm(props.session.start_time), // HH:mm VN
  session_end: toVNHHmm(props.session.end_time), // HH:mm VN
  price_per_hour: props.session.price_per_hour,
  court_fee_addon: props.session.court_fee_addon ?? 0,
  shuttle_fee_total: props.session.shuttle_fee_total,
})

const editBookings = ref<EditBookingSlot[]>([])

watch(
  () => props.session,
  (s) => {
    if (!isEditingSession.value) {
      sessionForm.value = {
        title: s.title,
        status: s.status,
        session_start: toVNHHmm(s.start_time),
        session_end: toVNHHmm(s.end_time),
        price_per_hour: s.price_per_hour,
        court_fee_addon: s.court_fee_addon ?? 0,
        shuttle_fee_total: s.shuttle_fee_total,
      }
    }
  },
)

const currencyFormatter = new Intl.NumberFormat('vi-VN', {
  style: 'currency',
  currency: 'VND',
  maximumFractionDigits: 0,
})

const formatCurrency = (v: number) => currencyFormatter.format(v)

const formatSessionDate = (iso: string) =>
  format(new Date(iso), 'EEEE, dd/MM/yyyy', { locale: dateLocale.value })

const formatTime = (iso: string) => format(new Date(iso), 'HH:mm')

const totalCollected = computed(() => {
  if (props.costs.length > 0) return props.costs.reduce((s, c) => s + c.final_total, 0)
  return props.snapshots.reduce((s, sn) => s + sn.final_amount, 0)
})

function startEditing() {
  isEditingSession.value = true
  // Use VN timezone (UTC+7) for time display, NOT browser local time
  editBookings.value = props.courtBookings.map((b) => ({
    id: b.id,
    court_name: b.court_name,
    start_time: toVNHHmm(b.start_time),
    end_time: toVNHHmm(b.end_time),
  }))
  if (editBookings.value.length === 0) {
    editBookings.value.push({
      court_name: 'Sân 1',
      start_time: sessionForm.value.session_start,
      end_time: sessionForm.value.session_end,
    })
  }
}

function cancelEditing() {
  isEditingSession.value = false
  sessionForm.value = {
    title: props.session.title,
    status: props.session.status,
    session_start: toVNHHmm(props.session.start_time),
    session_end: toVNHHmm(props.session.end_time),
    price_per_hour: props.session.price_per_hour,
    court_fee_addon: props.session.court_fee_addon ?? 0,
    shuttle_fee_total: props.session.shuttle_fee_total,
  }
}

function addEditBooking() {
  const name = `Sân ${editBookings.value.length + 1}`
  const start = sessionForm.value.session_start
  const end = sessionForm.value.session_end
  editBookings.value.push({ court_name: name, start_time: start, end_time: end })
  toast.success(t.value('createSession.courtAdded', { name, start, end }))
}

function removeEditBooking(index: number) {
  if (editBookings.value.length <= 1) return
  editBookings.value.splice(index, 1)
}

function isEditBookingOutOfBounds(booking: EditBookingSlot): boolean {
  return (
    booking.start_time < sessionForm.value.session_start ||
    booking.end_time > sessionForm.value.session_end
  )
}

function isEditBookingEndBeforeStart(booking: EditBookingSlot): boolean {
  return booking.start_time >= booking.end_time
}

function validateEditBookingTime(index: number) {
  const booking = editBookings.value[index]
  if (!booking) return
  if (booking.start_time >= booking.end_time) {
    toast.error(t.value('createSession.courtEndTimeError'))
    return
  }
  if (
    booking.start_time < sessionForm.value.session_start ||
    booking.end_time > sessionForm.value.session_end
  ) {
    toast.warning(t.value('createSession.courtTimeError'))
  }
}

async function saveSession() {
  if (!authStore.isAuthenticated) return

  // Validate session time
  const sessionDate = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Ho_Chi_Minh' }).format(
    new Date(props.session.start_time),
  )
  const newStartUTC = new Date(`${sessionDate}T${sessionForm.value.session_start}:00+07:00`)
  const newEndUTC = new Date(`${sessionDate}T${sessionForm.value.session_end}:00+07:00`)

  if (newEndUTC <= newStartUTC) {
    toast.error(t.value('createSession.endTimeError'))
    return
  }

  // Validate court bookings are within session window
  for (const b of editBookings.value) {
    const bStart = new Date(`${sessionDate}T${b.start_time}:00+07:00`)
    const bEnd = new Date(`${sessionDate}T${b.end_time}:00+07:00`)
    if (bStart < newStartUTC || bEnd > newEndUTC || bStart >= bEnd) {
      toast.error(t.value('createSession.courtTimeError'))
      return
    }
  }

  try {
    isSavingSession.value = true

    const timeChanged =
      newStartUTC.getTime() !== new Date(props.session.start_time).getTime() ||
      newEndUTC.getTime() !== new Date(props.session.end_time).getTime()

    if (timeChanged) {
      // Recreate intervals + update session start/end in one RPC
      // (also calls refresh_interval_courts internally)
      const { error: recreateErr } = await supabase.rpc('recreate_session_intervals', {
        p_session_id: props.sessionId,
        p_start_time: newStartUTC.toISOString(),
        p_end_time: newEndUTC.toISOString(),
      })
      if (recreateErr) throw recreateErr
    }

    // Update session scalar fields
    const { error } = await supabase
      .from('sessions')
      .update({
        title: sessionForm.value.title,
        status: sessionForm.value.status,
        price_per_hour: sessionForm.value.price_per_hour,
        court_fee_addon: sessionForm.value.court_fee_addon,
        shuttle_fee_total: sessionForm.value.shuttle_fee_total,
        updated_at: new Date().toISOString(),
      })
      .eq('id', props.sessionId)
    if (error) throw error

    // Replace court bookings
    const { error: delErr } = await supabase
      .from('session_court_bookings')
      .delete()
      .eq('session_id', props.sessionId)
    if (delErr) throw delErr

    const newBookings = editBookings.value.map((b) => ({
      session_id: props.sessionId,
      court_name: b.court_name,
      start_time: new Date(`${sessionDate}T${b.start_time}:00+07:00`).toISOString(),
      end_time: new Date(`${sessionDate}T${b.end_time}:00+07:00`).toISOString(),
    }))
    const { error: insErr } = await supabase.from('session_court_bookings').insert(newBookings)
    if (insErr) throw insErr

    // Always re-sync active_court_count (court booking times may have changed)
    await supabase.rpc('refresh_interval_courts', { p_session_id: props.sessionId })

    toast.success(t.value('toast.sessionUpdated'))
    isEditingSession.value = false
    emit('dataChanged')
  } catch (err: any) {
    toast.error(err.message || t.value('session.updateError'))
  } finally {
    isSavingSession.value = false
  }
}

async function finalizeSession() {
  if (!authStore.isAuthenticated) return
  if (!confirm(t.value('session.finalizeConfirm'))) return
  try {
    finalizeLoading.value = true
    const { error } = await supabase.rpc('finalize_session', {
      p_session_id: props.sessionId,
    })
    if (error) throw error
    toast.success(t.value('toast.sessionFinalized'))
    emit('dataChanged')
  } catch (err: any) {
    toast.error(err.message || t.value('session.finalizeError'))
  } finally {
    finalizeLoading.value = false
  }
}

async function cancelSession() {
  if (!authStore.isAuthenticated) return
  if (!confirm(t.value('session.cancelConfirm'))) return
  try {
    const { error } = await supabase
      .from('sessions')
      .update({ status: 'cancelled' })
      .eq('id', props.sessionId)
    if (error) throw error
    toast.success(t.value('toast.sessionCancelled'))
    emit('dataChanged')
  } catch (err: any) {
    toast.error(err.message || t.value('session.cancelError'))
  }
}
</script>

<template>
  <div class="bg-white rounded-lg shadow-sm p-4 md:p-6 mb-6 border border-gray-100">
    <!-- Header row: back + refresh -->
    <div class="flex items-center justify-between mb-4">
      <router-link
        to="/"
        class="flex items-center text-indigo-600 hover:text-indigo-800 transition text-sm"
      >
        <ChevronLeft class="w-4 h-4 mr-1" />
        {{ t('common.backToHome') }}
      </router-link>
      <button @click="$emit('refresh')" class="p-2 text-gray-400 hover:text-indigo-600 transition">
        <RefreshCcw class="w-4 h-4" :class="{ 'animate-spin': loading }" />
      </button>
    </div>

    <!-- Edit Mode -->
    <div v-if="isEditingSession && authStore.isAuthenticated" class="space-y-4">
      <div class="flex justify-between items-center">
        <h2 class="text-lg font-bold text-gray-900">{{ t('session.editSession') }}</h2>
        <button @click="cancelEditing" class="text-gray-400 hover:text-gray-600">
          <X class="w-5 h-5" />
        </button>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div class="sm:col-span-2">
          <label class="block text-sm font-medium text-gray-700 mb-1">{{
            t('session.title')
          }}</label>
          <input
            v-model="sessionForm.title"
            type="text"
            class="block w-full rounded-md border border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm px-3 py-2"
          />
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">{{
            t('createSession.startTime')
          }}</label>
          <input
            v-model="sessionForm.session_start"
            type="time"
            class="block w-full rounded-md border border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm px-3 py-2"
          />
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">{{
            t('createSession.endTime')
          }}</label>
          <input
            v-model="sessionForm.session_end"
            type="time"
            class="block w-full rounded-md border border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm px-3 py-2"
          />
        </div>
        <!-- Warning: changing session time clears attendance data -->
        <div v-if="timesChanged" class="sm:col-span-2">
          <div
            class="flex items-start gap-2 p-3 bg-red-50 border border-red-200 rounded-lg text-xs text-red-800"
          >
            <span class="mt-0.5">⚠️</span>
            <span>{{ t('session.intervalsResetWarning') }}</span>
          </div>
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">{{
            t('common.status')
          }}</label>
          <select
            v-model="sessionForm.status"
            class="block w-full rounded-md border border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm px-3 py-2"
          >
            <option value="open">{{ t('common.open') }}</option>
            <option value="waiting_for_payment">{{ t('common.waiting_for_payment') }}</option>
            <option value="done">{{ t('common.done') }}</option>
            <option value="cancelled">{{ t('common.cancelled') }}</option>
          </select>
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">{{
            t('session.pricePerHour')
          }}</label>
          <input
            v-model.number="sessionForm.price_per_hour"
            type="number"
            step="1000"
            class="block w-full rounded-md border border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm px-3 py-2"
          />
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">{{
            t('session.courtFeeAddon')
          }}</label>
          <input
            v-model.number="sessionForm.court_fee_addon"
            type="number"
            step="1000"
            min="0"
            class="block w-full rounded-md border border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm px-3 py-2"
          />
        </div>
        <div class="sm:col-span-2 md:col-span-1">
          <label class="block text-sm font-medium text-gray-700 mb-1">{{
            t('session.shuttleFee')
          }}</label>
          <input
            v-model.number="sessionForm.shuttle_fee_total"
            type="number"
            step="1000"
            class="block w-full rounded-md border border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm px-3 py-2"
          />
        </div>
      </div>
      <!-- Warning: both cost sources active -->
      <div
        v-if="sessionForm.price_per_hour > 0 && sessionForm.court_fee_addon > 0"
        class="flex items-start gap-2 p-3 bg-amber-50 border border-amber-200 rounded-lg text-xs text-amber-800"
      >
        <span class="mt-0.5">⚠️</span>
        <span>{{ t('session.courtFeeAddonWarning') }}</span>
      </div>

      <!-- Court Bookings -->
      <div>
        <div class="flex items-center justify-between mb-2">
          <label class="text-sm font-medium text-gray-700">{{ t('session.courtBookings') }}</label>
          <button
            type="button"
            @click="addEditBooking"
            class="flex items-center text-sm text-indigo-600 hover:text-indigo-800 font-medium"
          >
            <Plus class="w-4 h-4 mr-1" />
            {{ t('createSession.addCourt') }}
          </button>
        </div>
        <div class="space-y-2">
          <div
            v-for="(booking, index) in editBookings"
            :key="index"
            class="flex flex-col gap-2 p-3 bg-gray-50 rounded-lg border border-gray-200"
          >
            <div class="flex items-end gap-2">
              <div class="flex-1 min-w-0">
                <label class="block text-xs text-gray-500 mb-1">{{
                  t('createSession.courtName')
                }}</label>
                <input
                  v-model="booking.court_name"
                  type="text"
                  class="block w-full rounded-md border border-gray-300 text-sm px-3 py-1.5"
                />
              </div>
              <div class="w-24">
                <label class="block text-xs text-gray-500 mb-1">{{
                  t('createSession.startTime')
                }}</label>
                <input
                  v-model="booking.start_time"
                  type="time"
                  class="block w-full rounded-md border border-gray-300 text-sm px-2 py-1.5"
                  @change="validateEditBookingTime(index)"
                />
              </div>
              <div class="w-24">
                <label class="block text-xs text-gray-500 mb-1">{{
                  t('createSession.endTime')
                }}</label>
                <input
                  v-model="booking.end_time"
                  type="time"
                  class="block w-full rounded-md border border-gray-300 text-sm px-2 py-1.5"
                  @change="validateEditBookingTime(index)"
                />
              </div>
              <button
                type="button"
                @click="removeEditBooking(index)"
                :disabled="editBookings.length <= 1"
                class="p-1.5 text-gray-400 hover:text-red-500 transition disabled:opacity-30"
              >
                <Trash2 class="w-4 h-4" />
              </button>
            </div>
            <div
              v-if="isEditBookingEndBeforeStart(booking)"
              class="flex items-center gap-1.5 text-xs text-red-700 bg-red-50 border border-red-200 rounded px-2 py-1.5"
            >
              <span>&#x26A0;</span>
              <span>{{ t('createSession.courtEndTimeError') }}</span>
            </div>
            <div
              v-else-if="isEditBookingOutOfBounds(booking)"
              class="flex items-center gap-1.5 text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded px-2 py-1.5"
            >
              <span>&#x26A0;</span>
              <span>{{ t('createSession.courtTimeError') }} ({{ sessionForm.session_start }} – {{ sessionForm.session_end }})</span>
            </div>
          </div>
        </div>
      </div>

      <div class="flex justify-end gap-2 pt-2 border-t border-gray-100">
        <button
          @click="cancelEditing"
          class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 transition"
        >
          {{ t('common.cancel') }}
        </button>
        <button
          @click="saveSession"
          :disabled="isSavingSession"
          class="flex items-center px-4 py-2 text-sm font-medium text-white bg-indigo-600 rounded-md hover:bg-indigo-700 transition disabled:opacity-50"
        >
          <Save v-if="!isSavingSession" class="w-4 h-4 mr-1.5" />
          <Loader2 v-else class="w-4 h-4 mr-1.5 animate-spin" />
          {{ t('common.save') }}
        </button>
      </div>
    </div>

    <!-- View Mode -->
    <div v-else>
      <div class="flex flex-col md:flex-row md:justify-between md:items-start gap-4">
        <!-- Left: title + info -->
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <h1 class="text-2xl md:text-3xl font-bold text-gray-900 break-words">
              {{ session.title }}
            </h1>
            <button
              v-if="
                authStore.isAuthenticated &&
                session.status !== 'done' &&
                session.status !== 'cancelled' &&
                session.status !== 'waiting_for_payment'
              "
              @click="startEditing"
              class="p-1 text-gray-400 hover:text-indigo-600 transition"
              :title="t('session.editSession')"
            >
              <Edit class="w-4 h-4" />
            </button>
          </div>
          <p class="text-sm text-gray-600 mb-3 capitalize">
            {{ formatSessionDate(session.session_date) }}
          </p>

          <!-- Stats grid: responsive wrapping -->
          <div class="grid grid-cols-2 sm:grid-cols-3 md:flex md:flex-wrap gap-3 md:gap-6 text-sm">
            <div>
              <span class="text-gray-500 block text-xs mb-0.5">{{
                t('session.pricePerHour')
              }}</span>
              <span class="font-semibold text-gray-900">{{
                formatCurrency(session.price_per_hour)
              }}</span>
            </div>
            <div v-if="session.court_fee_addon > 0">
              <span class="text-gray-500 block text-xs mb-0.5">{{
                t('session.courtFeeAddon')
              }}</span>
              <span class="font-semibold text-gray-900">{{
                formatCurrency(session.court_fee_addon)
              }}</span>
            </div>
            <div>
              <span class="text-gray-500 block text-xs mb-0.5">{{
                t('session.courtBookings')
              }}</span>
              <span class="font-semibold text-gray-900">
                {{ courtBookings.length }} {{ t('session.courts') }}
              </span>
            </div>
            <div>
              <span class="text-gray-500 block text-xs mb-0.5">{{ t('session.shuttleFee') }}</span>
              <span class="font-semibold text-gray-900">{{
                formatCurrency(session.shuttle_fee_total)
              }}</span>
            </div>
            <div v-if="session.status === 'waiting_for_payment' || session.status === 'done'">
              <span class="text-indigo-600 block text-xs font-bold mb-0.5">{{
                t('session.totalCollected')
              }}</span>
              <span class="font-bold text-indigo-700">{{ formatCurrency(totalCollected) }}</span>
            </div>
            <div>
              <span class="text-gray-500 block text-xs mb-0.5">{{ t('common.status') }}</span>
              <span
                class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium capitalize"
                :class="{
                  'bg-green-100 text-green-800': session.status === 'done',
                  'bg-orange-100 text-orange-800': session.status === 'waiting_for_payment',
                  'bg-gray-100 text-gray-800': session.status === 'cancelled',
                  'bg-blue-100 text-blue-800': session.status === 'open',
                }"
              >
                {{ t(`common.${session.status}`) }}
              </span>
            </div>
          </div>
        </div>

        <!-- Right: action buttons (desktop inline, mobile stacked below) -->
        <div
          v-if="authStore.isAuthenticated && (session.status === 'open' || session.status === 'cancelled')"
          class="flex flex-row md:flex-col gap-2 md:shrink-0"
        >
          <button
            v-if="session.status === 'cancelled'"
            @click="$emit('deleteRequested')"
            class="flex-1 md:flex-none flex items-center justify-center px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700 transition text-sm font-medium"
          >
            <Trash2 class="w-4 h-4 mr-1.5" />
            {{ t('session.deleteCancelledSession') }}
          </button>
          <button
            v-if="session.status === 'open'"
            @click="cancelSession"
            class="flex-1 md:flex-none flex items-center justify-center px-4 py-2 bg-gray-600 text-white rounded-md hover:bg-gray-700 transition text-sm font-medium"
          >
            🚫 {{ t('session.cancelSession') }}
          </button>
          <button
            v-if="session.status === 'open'"
            @click="finalizeSession"
            :disabled="finalizeLoading"
            class="flex-1 md:flex-none flex items-center justify-center px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition text-sm font-medium disabled:opacity-50"
          >
            <Lock v-if="!finalizeLoading" class="w-4 h-4 mr-1.5" />
            <Loader2 v-else class="w-4 h-4 mr-1.5 animate-spin" />
            {{ t('session.finalize') }}
          </button>
        </div>
      </div>

      <!-- Court booking chips (visible in view mode) -->
      <div v-if="courtBookings.length > 0" class="mt-3 flex flex-wrap gap-2">
        <span
          v-for="b in courtBookings"
          :key="b.id"
          class="inline-flex items-center gap-1 px-2.5 py-1 bg-indigo-50 text-indigo-700 rounded-full text-xs font-medium"
        >
          🏸 {{ b.court_name }} · {{ formatTime(b.start_time) }}–{{ formatTime(b.end_time) }}
        </span>
      </div>
    </div>
  </div>
</template>
