<script setup lang="ts">
import { computed, watch } from 'vue'
import { Plus, Trash2 } from 'lucide-vue-next'
import { useLangStore } from '@/stores/lang'
import { courtTotal, findOverlaps } from '@/utils/courtCost'
import { formatCurrency } from '@/utils/formatters'
import type { CourtBookingDraft } from '@/types'
import Alert from '@/components/ui/Alert.vue'
import Button from '@/components/ui/Button.vue'
import FormField from '@/components/ui/FormField.vue'
import IconButton from '@/components/ui/IconButton.vue'
import Input from '@/components/ui/Input.vue'
import Select from '@/components/ui/Select.vue'

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
    <h2 class="text-xl font-bold text-fg-primary">{{ t('courtBooking.title') }}</h2>

    <div
      v-for="group in groupedByCourt"
      :key="group.court_name"
      data-testid="court-card"
      class="space-y-3 rounded-xl border border-line-divider p-4"
    >
      <div class="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <FormField
          :label="t('courtBooking.courtName')"
          label-style="Muted"
          class="min-w-0 flex-1"
          v-slot="{ controlProps }"
        >
          <Input
            v-bind="controlProps"
            :model-value="group.court_name"
            :model-modifiers="{ lazy: true }"
            :disabled="disabled"
            :data-testid="`court-name-${group.court_name}`"
            size="Default"
            type="text"
            @update:model-value="renameCourt(group.court_name, $event as string)"
          />
        </FormField>
        <Button
          :data-testid="`add-slot-${group.court_name}`"
          :disabled="disabled"
          size="Default"
          variant="Outline Brand"
          :leading-icon="Plus"
          @click="addSlot(group.court_name)"
        >
          {{ t('courtBooking.addSlot') }}
        </Button>
      </div>

      <div class="space-y-2">
        <div
          v-for="row in group.rows"
          :key="row.index"
          data-ds="Court Slot Row"
          :data-ds-error="
            overlapIndices.has(row.index)
              ? 'Overlap'
              : isEndBeforeStart(row.booking)
                ? 'End Before Start'
                : isOutOfBounds(row.booking)
                  ? 'Out Of Bounds'
                  : 'None'
          "
          class="flex flex-col gap-2 rounded-xl border border-line-divider bg-surface-subtle p-3"
        >
          <div class="flex flex-col gap-2 sm:flex-row sm:items-end">
            <FormField
              :label="t('createSession.startTime')"
              control="Select"
              label-style="Muted"
              class="sm:w-28"
              v-slot="{ controlProps }"
            >
              <Select
                v-bind="controlProps"
                :model-value="row.booking.start_time"
                :disabled="disabled"
                :data-testid="`start-time-${row.index}`"
                size="Default"
                @change="
                  patchBooking(row.index, {
                    start_time: ($event.target as HTMLSelectElement).value,
                  })
                "
              >
                <option v-for="opt in timeOptions" :key="opt" :value="opt">{{ opt }}</option>
              </Select>
            </FormField>
            <FormField
              :label="t('createSession.endTime')"
              control="Select"
              label-style="Muted"
              class="sm:w-28"
              v-slot="{ controlProps }"
            >
              <Select
                v-bind="controlProps"
                :model-value="row.booking.end_time"
                :disabled="disabled"
                :data-testid="`end-time-${row.index}`"
                size="Default"
                @change="
                  patchBooking(row.index, { end_time: ($event.target as HTMLSelectElement).value })
                "
              >
                <option v-for="opt in timeOptions" :key="opt" :value="opt">{{ opt }}</option>
              </Select>
            </FormField>
            <FormField
              :label="t('courtBooking.pricePerHour')"
              label-style="Muted"
              class="sm:w-32"
              v-slot="{ controlProps }"
            >
              <Input
                v-bind="controlProps"
                :model-value="row.booking.price_per_hour"
                :model-modifiers="{ lazy: true }"
                :disabled="disabled"
                :data-testid="`price-${row.index}`"
                size="Default"
                type="number"
                min="0"
                step="1000"
                @update:model-value="
                  patchBooking(row.index, {
                    price_per_hour: Math.max(0, Number($event) || 0),
                  })
                "
              />
            </FormField>
            <IconButton
              :icon="Trash2"
              :label="t('courtBooking.removeSlot')"
              :data-testid="`remove-slot-${row.index}`"
              :disabled="disabled || bookings.length <= 1"
              :title="t('courtBooking.removeSlot')"
              size="Default"
              shape="Square"
              variant="Ghost"
              @click="removeSlot(row.index)"
            />
          </div>
          <Alert v-if="overlapIndices.has(row.index)" tone="Danger" size="Small" class="w-full">
            {{ t('courtBooking.overlapError') }}
          </Alert>
          <Alert
            v-else-if="isEndBeforeStart(row.booking)"
            tone="Danger"
            size="Small"
            class="w-full"
          >
            {{ t('courtBooking.endBeforeStartError') }}
          </Alert>
          <Alert v-else-if="isOutOfBounds(row.booking)" tone="Warning" size="Small" class="w-full">
            {{ t('courtBooking.outOfBoundsError') }}
          </Alert>
        </div>
      </div>
    </div>

    <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <Button
        data-testid="add-court"
        :disabled="disabled"
        size="Default"
        variant="Outline Brand"
        :leading-icon="Plus"
        @click="addCourt"
      >
        {{ t('courtBooking.addCourt') }}
      </Button>
      <div data-testid="court-total" class="text-right font-bold text-fg-primary">
        {{ t('courtBooking.total') }}: {{ formatCurrency(total) }}
      </div>
    </div>
  </div>
</template>
