<script setup lang="ts">
import { computed, watch } from 'vue'
import { Plus, Trash2 } from 'lucide-vue-next'
import { useLangStore } from '@/stores/lang'
import { courtTotal, findOverlaps } from '@/utils/courtCost'
import { formatCurrency } from '@/utils/formatters'
import type { CourtBookingDraft } from '@/types'

const props = defineProps<{
  bookings: CourtBookingDraft[]
  sessionStart: string // "HH:mm" giờ Việt Nam
  sessionEnd: string // "HH:mm"
  defaultPrice: number
  disabled?: boolean
}>()

const emit = defineEmits<{
  'update:bookings': [CourtBookingDraft[]]
  'update:valid': [boolean]
}>()

const langStore = useLangStore()
const t = computed(() => langStore.t)

/** Mọi khung giờ trong ngày, cách nhau 30 phút. */
const timeOptions: string[] = Array.from({ length: 48 }, (_, i) => {
  const h = Math.floor(i / 2)
  const m = i % 2 === 0 ? '00' : '30'
  return `${String(h).padStart(2, '0')}:${m}`
})

interface CourtGroup {
  court_name: string
  rows: { index: number; booking: CourtBookingDraft }[]
}

/** Gom props.bookings theo court_name, giữ chỉ số gốc để emit lại đúng mảng phẳng. */
const groupedByCourt = computed<CourtGroup[]>(() => {
  const groups = new Map<string, CourtGroup>()
  props.bookings.forEach((booking, index) => {
    let group = groups.get(booking.court_name)
    if (!group) {
      group = { court_name: booking.court_name, rows: [] }
      groups.set(booking.court_name, group)
    }
    group.rows.push({ index, booking })
  })
  return [...groups.values()]
})

const total = computed(() => courtTotal(props.bookings))

/** Chỉ số các khung chồng lên khung khác của cùng một sân (từ Task 7, không tự viết lại). */
const overlapIndices = computed(() => new Set(findOverlaps(props.bookings)))

function isEndBeforeStart(booking: CourtBookingDraft): boolean {
  return booking.start_time >= booking.end_time
}

function isOutOfBounds(booking: CourtBookingDraft): boolean {
  return booking.start_time < props.sessionStart || booking.end_time > props.sessionEnd
}

/**
 * Hợp lệ khi: không khung nào chồng nhau, mọi khung có end_time > start_time,
 * mọi khung nằm trong [sessionStart, sessionEnd], và còn ít nhất một khung.
 * Carried from SessionHeader.vue:157-179 (isEditBookingOutOfBounds /
 * isEditBookingEndBeforeStart), plus the overlap rule from Task 7's findOverlaps,
 * which SessionHeader never checked.
 */
const isValid = computed(() => {
  if (props.bookings.length === 0) return false
  if (overlapIndices.value.size > 0) return false
  return props.bookings.every((b) => !isEndBeforeStart(b) && !isOutOfBounds(b))
})

watch(isValid, (v) => emit('update:valid', v), { immediate: true })

function patchBooking(index: number, patch: Partial<CourtBookingDraft>) {
  const next = props.bookings.map((b, i) => (i === index ? { ...b, ...patch } : b))
  emit('update:bookings', next)
}

function renameCourt(courtName: string, newName: string) {
  const next = props.bookings.map((b) =>
    b.court_name === courtName ? { ...b, court_name: newName } : b,
  )
  emit('update:bookings', next)
}

function addCourt() {
  const newBooking: CourtBookingDraft = {
    court_name: `Sân ${groupedByCourt.value.length + 1}`,
    start_time: props.sessionStart,
    end_time: props.sessionEnd,
    price_per_hour: props.defaultPrice,
  }
  emit('update:bookings', [...props.bookings, newBooking])
}

function addSlot(courtName: string) {
  const rows = groupedByCourt.value.find((g) => g.court_name === courtName)?.rows ?? []
  const lastRow = rows[rows.length - 1]
  const newBooking: CourtBookingDraft = {
    court_name: courtName,
    start_time: lastRow ? lastRow.booking.end_time : props.sessionStart,
    end_time: props.sessionEnd,
    price_per_hour: props.defaultPrice,
  }
  emit('update:bookings', [...props.bookings, newBooking])
}

/**
 * There is no dedicated "delete court" affordance: a court card exists only
 * while at least one row has its court_name, so removing a court's last
 * remaining slot removes the card with it. (Renaming a court's name field
 * onto an existing court's name merges the two cards the same way, since
 * grouping is purely by court_name.)
 */
function removeSlot(index: number) {
  if (props.bookings.length <= 1) return
  emit(
    'update:bookings',
    props.bookings.filter((_, i) => i !== index),
  )
}
</script>

<template>
  <div class="space-y-4">
    <h2 class="text-[20px] font-bold leading-[1.2] text-fg-primary">{{ t('courtBooking.title') }}</h2>

    <div
      v-for="group in groupedByCourt"
      :key="group.court_name"
      data-testid="court-card"
      class="space-y-3 rounded-xl border border-divider p-4"
    >
      <div class="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div class="min-w-0 flex-1">
          <label class="mb-1 block text-xs font-bold text-fg-muted">{{
            t('courtBooking.courtName')
          }}</label>
          <input
            :value="group.court_name"
            :disabled="disabled"
            :data-testid="`court-name-${group.court_name}`"
            type="text"
            class="block min-h-11 w-full rounded-xl border border-input px-3 py-2 text-[20px] font-bold leading-[1.2] text-fg-primary focus:border-brand-500 focus:ring-brand-500 disabled:opacity-50"
            @change="renameCourt(group.court_name, ($event.target as HTMLInputElement).value)"
          />
        </div>
        <button
          type="button"
          :data-testid="`add-slot-${group.court_name}`"
          :disabled="disabled"
          class="inline-flex min-h-11 items-center justify-center gap-1 rounded-xl border border-brand-200 px-3 text-sm font-bold text-brand-600 transition hover:bg-brand-50 disabled:opacity-50"
          @click="addSlot(group.court_name)"
        >
          <Plus class="h-4 w-4" />
          {{ t('courtBooking.addSlot') }}
        </button>
      </div>

      <div class="space-y-2">
        <div
          v-for="row in group.rows"
          :key="row.index"
          class="flex flex-col gap-2 rounded-xl border border-divider bg-gray-50 p-3 sm:flex-row sm:items-end"
        >
          <div class="w-full sm:w-28">
            <label class="mb-1 block text-xs text-fg-muted">{{ t('createSession.startTime') }}</label>
            <select
              :value="row.booking.start_time"
              :disabled="disabled"
              :data-testid="`start-time-${row.index}`"
              class="block min-h-11 w-full rounded-xl border border-input px-2 text-sm focus:border-brand-500 focus:ring-brand-500 disabled:opacity-50"
              @change="
                patchBooking(row.index, { start_time: ($event.target as HTMLSelectElement).value })
              "
            >
              <option v-for="opt in timeOptions" :key="opt" :value="opt">{{ opt }}</option>
            </select>
          </div>
          <div class="w-full sm:w-28">
            <label class="mb-1 block text-xs text-fg-muted">{{ t('createSession.endTime') }}</label>
            <select
              :value="row.booking.end_time"
              :disabled="disabled"
              :data-testid="`end-time-${row.index}`"
              class="block min-h-11 w-full rounded-xl border border-input px-2 text-sm focus:border-brand-500 focus:ring-brand-500 disabled:opacity-50"
              @change="
                patchBooking(row.index, { end_time: ($event.target as HTMLSelectElement).value })
              "
            >
              <option v-for="opt in timeOptions" :key="opt" :value="opt">{{ opt }}</option>
            </select>
          </div>
          <div class="w-full sm:w-32">
            <label class="mb-1 block text-xs text-fg-muted">{{
              t('courtBooking.pricePerHour')
            }}</label>
            <input
              :value="row.booking.price_per_hour"
              :disabled="disabled"
              :data-testid="`price-${row.index}`"
              type="number"
              min="0"
              step="1000"
              class="block min-h-11 w-full rounded-xl border border-input px-2 text-sm focus:border-brand-500 focus:ring-brand-500 disabled:opacity-50"
              @change="
                patchBooking(row.index, {
                  price_per_hour: Math.max(0, Number(($event.target as HTMLInputElement).value) || 0),
                })
              "
            />
          </div>
          <button
            type="button"
            :data-testid="`remove-slot-${row.index}`"
            :disabled="disabled || bookings.length <= 1"
            :title="t('courtBooking.removeSlot')"
            class="flex min-h-11 min-w-11 items-center justify-center rounded-xl text-fg-disabled transition hover:text-status-danger-action disabled:opacity-30"
            @click="removeSlot(row.index)"
          >
            <Trash2 class="h-4 w-4" />
            <span class="sr-only">{{ t('courtBooking.removeSlot') }}</span>
          </button>
          <div
            v-if="overlapIndices.has(row.index)"
            class="flex items-center gap-1.5 rounded-xl border border-status-danger-border bg-status-danger-subtle px-2 py-1.5 text-xs text-status-danger-strong sm:w-full"
          >
            {{ t('courtBooking.overlapError') }}
          </div>
          <div
            v-else-if="isEndBeforeStart(row.booking)"
            class="flex items-center gap-1.5 rounded-xl border border-status-danger-border bg-status-danger-subtle px-2 py-1.5 text-xs text-status-danger-strong sm:w-full"
          >
            {{ t('courtBooking.endBeforeStartError') }}
          </div>
          <div
            v-else-if="isOutOfBounds(row.booking)"
            class="flex items-center gap-1.5 rounded-xl border border-amber-200 bg-amber-50 px-2 py-1.5 text-xs text-amber-700 sm:w-full"
          >
            {{ t('courtBooking.outOfBoundsError') }}
          </div>
        </div>
      </div>
    </div>

    <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <button
        type="button"
        data-testid="add-court"
        :disabled="disabled"
        class="inline-flex min-h-11 items-center justify-center gap-1 rounded-xl border border-brand-200 px-4 text-sm font-bold text-brand-600 transition hover:bg-brand-50 disabled:opacity-50"
        @click="addCourt"
      >
        <Plus class="h-4 w-4" />
        {{ t('courtBooking.addCourt') }}
      </button>
      <div data-testid="court-total" class="text-right font-bold text-fg-primary">
        {{ t('courtBooking.total') }}: {{ formatCurrency(total) }}
      </div>
    </div>
  </div>
</template>
