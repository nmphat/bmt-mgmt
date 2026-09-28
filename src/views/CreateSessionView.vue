<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { supabase } from '@/lib/supabase'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { useToast } from 'vue-toastification'
import { ChevronLeft } from 'lucide-vue-next'
import CourtBookingEditor from '@/components/session/CourtBookingEditor.vue'
import Button from '@/components/ui/Button.vue'
import FieldMessage from '@/components/ui/FieldMessage.vue'
import FormField from '@/components/ui/FormField.vue'
import Input from '@/components/ui/Input.vue'
import PageHeader from '@/components/ui/PageHeader.vue'
import type { CourtBookingDraft } from '@/types'

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
})

// Seeds newly added court slots so an admin isn't typing the same price into
// every one; does not touch p_price_per_hour, which stays hardcoded to 0.
const defaultCourtPrice = ref(0)

const bookings = ref<CourtBookingDraft[]>([
  {
    court_name: 'Sân 1',
    start_time: form.value.startTime,
    end_time: form.value.endTime,
    price_per_hour: 0,
  },
])

// Keep bookings in sync when session times change — only rows still matching
// the previous session times are updated; manually edited rows are left alone.
watch(
  () => [form.value.startTime, form.value.endTime] as const,
  ([newStart, newEnd], [oldStart, oldEnd]) => {
    bookings.value = bookings.value.map((b) =>
      b.start_time === oldStart && b.end_time === oldEnd
        ? { ...b, start_time: newStart, end_time: newEnd }
        : b,
    )
  },
)

const bookingsValid = ref(true)
const loading = ref(false)

const intervalPreview = computed(() => {
  const startParts = form.value.startTime.split(':').map(Number)
  const endParts = form.value.endTime.split(':').map(Number)
  const sh = startParts[0] ?? 0
  const sm = startParts[1] ?? 0
  const eh = endParts[0] ?? 0
  const em = endParts[1] ?? 0
  const minutes = eh * 60 + em - (sh * 60 + sm)
  return minutes > 0 ? Math.ceil(minutes / 30) : 0
})

const startDateTime = computed(() => {
  return `${form.value.date}T${form.value.startTime}:00+07:00`
})

const endDateTime = computed(() => {
  return `${form.value.date}T${form.value.endTime}:00+07:00`
})

const sessionTimeInvalid = computed(() => startDateTime.value >= endDateTime.value)

async function createSession() {
  if (!authStore.user) return

  if (startDateTime.value >= endDateTime.value) {
    toast.error(t.value('createSession.endTimeError'))
    return
  }

  if (!bookingsValid.value) {
    toast.error(t.value('createSession.courtEndTimeError'))
    return
  }

  try {
    loading.value = true
    const startTime = new Date(startDateTime.value).toISOString()
    const endTime = new Date(endDateTime.value).toISOString()
    const pBookings = bookings.value.map((b) => ({
      court_name: b.court_name,
      start_time: new Date(`${form.value.date}T${b.start_time}:00+07:00`).toISOString(),
      end_time: new Date(`${form.value.date}T${b.end_time}:00+07:00`).toISOString(),
      price_per_hour: b.price_per_hour,
    }))

    const { data: sessionId, error } = await supabase.rpc('create_session_with_bookings', {
      p_title: form.value.title,
      p_start_time: startTime,
      p_end_time: endTime,
      p_price_per_hour: 0,
      p_shuttle_fee: 0,
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
      <Button
        as="RouterLink"
        to="/sessions"
        size="Default"
        variant="Ghost"
        :leading-icon="ChevronLeft"
      >
        {{ t('common.backToSessions') }}
      </Button>
    </div>

    <div class="rounded-xl border border-line-divider bg-surface-card p-4 shadow-sm sm:p-6">
      <PageHeader :title="t('createSession.title')" class="mb-6" />

      <form @submit.prevent="createSession" class="space-y-6">
        <FormField control-id="title" :label="t('session.title')" v-slot="{ controlProps }">
          <Input
            v-model="form.title"
            v-bind="controlProps"
            size="Default"
            type="text"
            required
            :placeholder="t('createSession.titlePlaceholder')"
          />
        </FormField>

        <FormField control-id="date" :label="t('createSession.date')" v-slot="{ controlProps }">
          <Input v-model="form.date" v-bind="controlProps" size="Default" type="date" required />
        </FormField>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <FormField
            control-id="startTime"
            :label="t('createSession.startTime')"
            v-slot="{ controlProps }"
          >
            <Input
              v-model="form.startTime"
              v-bind="controlProps"
              size="Default"
              type="time"
              required
            />
          </FormField>
          <FormField control-id="endTime" :label="t('createSession.endTime')" message-tone="Error">
            <template #default="{ controlProps }">
              <Input
                v-model="form.endTime"
                v-bind="controlProps"
                size="Default"
                type="time"
                required
              />
            </template>
            <template v-if="sessionTimeInvalid" #message>
              {{ t('createSession.endTimeError') }}
            </template>
          </FormField>
        </div>

        <FieldMessage>
          {{ t('courtBooking.intervalPreview', { count: intervalPreview }) }}
        </FieldMessage>

        <FormField
          control-id="courtFee"
          :label="t('session.courtFeeAddon')"
          :message="t('session.courtFeeAddonHint')"
          v-slot="{ controlProps }"
        >
          <Input
            v-model.number="form.courtFee"
            v-bind="controlProps"
            size="Default"
            type="number"
            min="0"
            step="1000"
            required
          />
        </FormField>

        <FormField
          control-id="defaultCourtPrice"
          :label="t('session.defaultCourtPrice')"
          v-slot="{ controlProps }"
        >
          <Input
            v-model.number="defaultCourtPrice"
            v-bind="controlProps"
            size="Default"
            type="number"
            min="0"
            step="1000"
          />
        </FormField>

        <!-- Court Bookings -->
        <CourtBookingEditor
          v-model:bookings="bookings"
          :session-start="form.startTime"
          :session-end="form.endTime"
          :default-price="defaultCourtPrice"
          @update:valid="bookingsValid = $event"
        />

        <div class="pt-4">
          <Button
            type="submit"
            size="Large"
            variant="Primary"
            :disabled="loading || !bookingsValid || sessionTimeInvalid"
            class="w-full"
          >
            {{ loading ? t('createSession.creating') : t('createSession.createButton') }}
          </Button>
        </div>
      </form>
    </div>
  </div>
</template>
