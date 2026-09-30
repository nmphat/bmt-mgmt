<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import { DollarSign, CircleCheckBig, Info, ArrowLeft } from 'lucide-vue-next'
import ModalPanel from '@/components/ui/ModalPanel.vue'
import ModalHeader from '@/components/ui/ModalHeader.vue'
import ModalFooter from '@/components/ui/ModalFooter.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import FormField from '@/components/ui/FormField.vue'
import FieldLabel from '@/components/ui/FieldLabel.vue'
import Alert from '@/components/ui/Alert.vue'
import { supabase } from '@/lib/supabase'
import type { CostSnapshot } from '@/types'
import { useToast } from 'vue-toastification'
import { useLangStore } from '@/stores/lang'

const props = defineProps<{
  show: boolean
  snapshot: CostSnapshot | null
  memberName: string
}>()

const emit = defineEmits(['close', 'success'])
const langStore = useLangStore()
const toast = useToast()
const t = computed(() => langStore.t)

const amount = ref(0)
const note = ref('')
const isSubmitting = ref(false)
const currentStep = ref<'entry' | 'review'>('entry')

const remainingDebt = computed(() => {
  if (!props.snapshot) return 0
  return props.snapshot.final_amount - props.snapshot.paid_amount
})

// Initialize note based on language
watch(
  () => langStore.currentLang,
  () => {
    if (!isSubmitting.value && !note.value) {
      note.value = t.value('payment.cash')
    }
  },
  { immediate: true },
)

// Reset form when snapshot changes
watch(
  () => props.snapshot,
  (newVal) => {
    if (newVal) {
      amount.value = newVal.final_amount - newVal.paid_amount
      note.value = t.value('payment.cash')
      currentStep.value = 'entry'
    }
  },
  { immediate: true },
)

watch(
  () => props.show,
  (show) => {
    if (show) {
      currentStep.value = 'entry'
    }
  },
)

const formatCurrency = (value: number) => {
  return new Intl.NumberFormat(langStore.currentLang === 'vi' ? 'vi-VN' : 'en-US', {
    style: 'currency',
    currency: 'VND',
    maximumFractionDigits: 0,
  }).format(value)
}

function handleClose() {
  if (isSubmitting.value) return
  emit('close')
}

function proceedToReview() {
  if (amount.value <= 0) {
    toast.error(t.value('payment.amountPositiveError'))
    return
  }
  currentStep.value = 'review'
}

async function handleConfirm() {
  if (!props.snapshot || currentStep.value !== 'review') return
  if (amount.value <= 0) {
    toast.error(t.value('payment.amountPositiveError'))
    currentStep.value = 'entry'
    return
  }

  isSubmitting.value = true
  try {
    const { error } = await supabase.rpc('add_manual_payment', {
      p_snapshot_id: props.snapshot.id,
      p_amount: amount.value,
      p_note: note.value,
    })

    if (error) throw error

    toast.success(t.value('payment.manualPaymentSuccess'))
    emit('success')
    emit('close')
  } catch (error: any) {
    console.error('Error adding manual payment:', error)
    toast.error(t.value('toast.error', { message: error.message }))
  } finally {
    isSubmitting.value = false
  }
}
</script>

<template>
  <div
    v-if="show"
    class="fixed inset-0 z-50"
    aria-labelledby="manual-payment-title"
    role="dialog"
    aria-modal="true"
  >
    <div
      class="flex min-h-screen items-end justify-center px-0 text-center sm:items-center sm:px-4 sm:py-8"
    >
      <!-- Background overlay -->
      <div
        data-ds="Modal Scrim"
        data-ds-style="Default"
        class="fixed inset-0 bg-surface-scrim/75 transition-opacity"
        aria-hidden="true"
        @click="handleClose"
      ></div>

      <ModalPanel width="md">
        <template #header>
          <ModalHeader
            title-id="manual-payment-title"
            :title="
              currentStep === 'review' ? t('payment.cashReviewTitle') : t('payment.manualTitle')
            "
            :icon="DollarSign"
            :close="isSubmitting ? 'Disabled' : 'Default'"
            :close-label="t('common.cancel')"
            @close="handleClose"
          />
        </template>

        <div
          v-if="snapshot"
          data-ds="Manual Payment Body"
          :data-ds-step="currentStep === 'entry' ? 'Entry' : 'Review'"
          class="flex flex-col gap-4 bg-surface-card py-5"
        >
          <template v-if="currentStep === 'entry'">
            <Alert tone="Info" :icon="Info">
              <div v-html="t('payment.amountReceived', { name: memberName })"></div>
            </Alert>

            <div class="flex flex-col gap-1">
              <FieldLabel>{{ t('payment.reviewMember') }}</FieldLabel>
              <div
                data-ds="Read-only Field"
                data-ds-size="Default"
                class="flex h-control-md items-center rounded-control border border-line-divider bg-surface-subtle px-3 text-base font-bold uppercase text-fg-primary"
              >
                {{ memberName }}
              </div>
            </div>

            <div
              data-ds="Amount Panel"
              data-ds-tone="Warning"
              class="flex flex-col gap-1 rounded-xl border border-status-warning-border bg-status-warning-subtle p-4"
            >
              <p class="text-sm font-bold text-status-warning-strong">
                {{ t('payment.debtLabel') }}
              </p>
              <p class="text-3xl font-bold text-status-warning-strong tabular-nums">
                {{ formatCurrency(remainingDebt) }}
              </p>
            </div>

            <FormField control-id="amount" :label="t('payment.amountCollected')">
              <template #default="{ controlProps }">
                <Input
                  v-bind="controlProps"
                  v-model.number="amount"
                  size="Default"
                  type="number"
                  step="1000"
                  min="0"
                  suffix="₫"
                  :placeholder="t('payment.amountToPay') + '...'"
                  @keyup.enter="proceedToReview"
                />
              </template>
            </FormField>

            <FormField control-id="note" :label="t('payment.note')">
              <template #default="{ controlProps }">
                <Input
                  v-bind="controlProps"
                  v-model="note"
                  size="Default"
                  type="text"
                  :placeholder="t('payment.note') + '...'"
                />
              </template>
            </FormField>
          </template>

          <template v-else>
            <Alert tone="Warning">
              {{ t('payment.cashReviewTitle') }}
            </Alert>

            <dl class="overflow-hidden rounded-xl border border-line-divider bg-surface-card">
              <div
                data-ds="Key Value Row"
                data-ds-layout="Inline Divided"
                data-ds-tone="Neutral"
                data-ds-align="Left"
                data-ds-value-tone="Primary"
                class="flex justify-between gap-3 border-b border-line-subtle px-4 py-3 last:border-b-0"
              >
                <dt class="text-sm font-bold text-fg-muted">{{ t('payment.reviewMember') }}</dt>
                <dd class="text-right text-sm font-bold text-fg-primary">{{ memberName }}</dd>
              </div>
              <div
                data-ds="Key Value Row"
                data-ds-layout="Inline Divided"
                data-ds-tone="Neutral"
                data-ds-align="Left"
                data-ds-value-tone="Brand"
                class="flex justify-between gap-3 border-b border-line-subtle px-4 py-3 last:border-b-0"
              >
                <dt class="text-sm font-bold text-fg-muted">{{ t('payment.reviewAmount') }}</dt>
                <dd class="text-right text-sm font-bold text-fg-brand-strong">
                  {{ formatCurrency(amount) }}
                </dd>
              </div>
              <div
                data-ds="Key Value Row"
                data-ds-layout="Inline Divided"
                data-ds-tone="Neutral"
                data-ds-align="Left"
                data-ds-value-tone="Primary"
                class="flex justify-between gap-3 border-b border-line-subtle px-4 py-3 last:border-b-0"
              >
                <dt class="text-sm font-bold text-fg-muted">
                  {{ t('payment.reviewRemainingDebt') }}
                </dt>
                <dd class="text-right text-sm font-bold text-fg-primary">
                  {{ formatCurrency(remainingDebt) }}
                </dd>
              </div>
              <div
                data-ds="Key Value Row"
                data-ds-layout="Inline Divided"
                data-ds-tone="Neutral"
                data-ds-align="Left"
                data-ds-value-tone="Regular"
                class="flex justify-between gap-3 border-b border-line-subtle px-4 py-3 last:border-b-0"
              >
                <dt class="text-sm font-bold text-fg-muted">{{ t('payment.reviewNote') }}</dt>
                <dd class="text-right text-sm text-fg-primary">{{ note || '—' }}</dd>
              </div>
            </dl>
          </template>
        </div>

        <template #footer>
          <ModalFooter background="Gray" buttons="Two" class="manual-payment-footer-safe">
            <template v-if="currentStep === 'entry'" #primary>
              <Button
                size="Default"
                variant="Success"
                :leading-icon="CircleCheckBig"
                @click="proceedToReview"
              >
                {{ t('payment.confirmCash') }}
              </Button>
            </template>
            <template v-else #primary>
              <Button
                size="Default"
                variant="Success"
                :leading-icon="CircleCheckBig"
                :loading="isSubmitting"
                :disabled="isSubmitting"
                @click="handleConfirm"
              >
                {{ t('payment.confirmCash') }}
              </Button>
            </template>
            <template v-if="currentStep === 'entry'" #secondary>
              <Button size="Default" variant="Secondary" @click="handleClose">
                {{ t('common.cancel') }}
              </Button>
            </template>
            <template v-else #secondary>
              <Button
                size="Default"
                variant="Secondary"
                :leading-icon="ArrowLeft"
                :disabled="isSubmitting"
                @click="currentStep = 'entry'"
              >
                {{ t('payment.backToEdit') }}
              </Button>
            </template>
          </ModalFooter>
        </template>
      </ModalPanel>
    </div>
  </div>
</template>

<style scoped>
.manual-payment-footer-safe {
  padding-bottom: calc(0.75rem + env(safe-area-inset-bottom));
}
</style>
