<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import { X, Loader2, DollarSign, CheckCircle, Info, ArrowLeft } from 'lucide-vue-next'
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
    <div class="flex min-h-screen items-end justify-center px-0 text-center sm:items-center sm:px-4 sm:py-8">
      <!-- Background overlay -->
      <div
        class="fixed inset-0 bg-gray-500/75 transition-opacity"
        aria-hidden="true"
        @click="handleClose"
      ></div>

      <!-- Modal panel -->
      <div
        class="relative z-10 flex max-h-[88dvh] w-full flex-col overflow-hidden rounded-t-2xl bg-white text-left align-bottom shadow-xl transition-all sm:max-w-md sm:rounded-2xl"
      >
        <div class="shrink-0 border-b border-gray-100 bg-white px-4 py-4 sm:px-6">
          <div class="flex items-start justify-between gap-3">
            <h3
              class="flex items-center gap-2 text-[20px] font-bold leading-[1.2] text-gray-900"
              id="manual-payment-title"
            >
              <DollarSign class="h-6 w-6 text-green-600" />
              {{
                currentStep === 'review' ? t('payment.cashReviewTitle') : t('payment.manualTitle')
              }}
            </h3>
            <button
              type="button"
              @click="handleClose"
              :disabled="isSubmitting"
              class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-full text-gray-500 hover:bg-gray-100 hover:text-gray-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:opacity-50"
              :aria-label="t('common.cancel')"
            >
              <X class="h-6 w-6" />
            </button>
          </div>
        </div>

        <div class="flex-1 overflow-y-auto bg-white px-4 py-5 sm:px-6">
          <div v-if="snapshot" class="space-y-4">
            <template v-if="currentStep === 'entry'">
              <div class="flex items-start gap-3 rounded-2xl border border-blue-100 bg-blue-50 p-3">
                <Info class="mt-0.5 h-5 w-5 shrink-0 text-blue-600" />
                <div
                  class="text-sm text-blue-800"
                  v-html="t('payment.amountReceived', { name: memberName })"
                ></div>
              </div>

              <div class="space-y-4 pt-2">
                <div>
                  <label class="mb-1 block text-sm font-bold text-gray-700">{{
                    t('payment.reviewMember')
                  }}</label>
                  <div
                    class="rounded-xl border border-gray-200 bg-gray-50 px-3 py-3 font-bold uppercase text-gray-900"
                  >
                    {{ memberName }}
                  </div>
                </div>

                <div class="rounded-2xl border border-amber-100 bg-amber-50 px-4 py-3">
                  <p class="text-sm font-bold text-amber-800">{{ t('payment.debtLabel') }}</p>
                  <p class="mt-1 text-[32px] font-bold leading-[1.05] text-amber-900 tabular-nums">
                    {{ formatCurrency(remainingDebt) }}
                  </p>
                </div>

                <div>
                  <label for="amount" class="mb-1 block text-sm font-bold text-gray-700">{{
                    t('payment.amountCollected')
                  }}</label>
                  <div class="relative rounded-xl shadow-sm">
                    <input
                      id="amount"
                      v-model.number="amount"
                      type="number"
                      step="1000"
                      min="0"
                      class="block min-h-11 w-full rounded-xl border border-gray-300 py-2 pl-3 pr-12 text-[16px] font-bold leading-[1.5] text-indigo-700 focus:border-indigo-500 focus:ring-indigo-500"
                      :placeholder="t('payment.amountToPay') + '...'"
                      @keyup.enter="proceedToReview"
                    />
                    <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-3">
                      <span class="text-gray-500 sm:text-sm">₫</span>
                    </div>
                  </div>
                </div>

                <div>
                  <label for="note" class="mb-1 block text-sm font-bold text-gray-700">{{
                    t('payment.note')
                  }}</label>
                  <input
                    id="note"
                    v-model="note"
                    type="text"
                    class="block min-h-11 w-full rounded-xl border border-gray-300 px-3 py-2 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    :placeholder="t('payment.note') + '...'"
                  />
                </div>
              </div>
            </template>

            <template v-else>
              <div class="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
                {{ t('payment.cashReviewTitle') }}
              </div>

              <dl class="divide-y divide-gray-100 rounded-2xl border border-gray-200 bg-white">
                <div class="flex justify-between gap-4 px-4 py-3">
                  <dt class="text-sm font-bold text-gray-500">{{ t('payment.reviewMember') }}</dt>
                  <dd class="text-right text-sm font-bold text-gray-900">{{ memberName }}</dd>
                </div>
                <div class="flex justify-between gap-4 px-4 py-3">
                  <dt class="text-sm font-bold text-gray-500">{{ t('payment.reviewAmount') }}</dt>
                  <dd class="text-right text-sm font-bold text-indigo-700">
                    {{ formatCurrency(amount) }}
                  </dd>
                </div>
                <div class="flex justify-between gap-4 px-4 py-3">
                  <dt class="text-sm font-bold text-gray-500">
                    {{ t('payment.reviewRemainingDebt') }}
                  </dt>
                  <dd class="text-right text-sm font-bold text-gray-900">
                    {{ formatCurrency(remainingDebt) }}
                  </dd>
                </div>
                <div class="flex justify-between gap-4 px-4 py-3">
                  <dt class="text-sm font-bold text-gray-500">{{ t('payment.reviewNote') }}</dt>
                  <dd class="text-right text-sm text-gray-900">{{ note || '—' }}</dd>
                </div>
              </dl>
            </template>
          </div>
        </div>

        <div
          class="manual-payment-footer-safe sticky bottom-0 shrink-0 border-t border-gray-100 bg-gray-50 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse"
        >
          <template v-if="currentStep === 'entry'">
            <button
              @click="proceedToReview"
              type="button"
              class="inline-flex min-h-11 w-full items-center justify-center rounded-xl border border-transparent bg-green-600 px-4 py-2 text-base font-bold text-white shadow-sm hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 sm:ml-3 sm:w-auto sm:text-sm"
            >
              <CheckCircle class="mr-2 h-4 w-4" />
              {{ t('payment.confirmCash') }}
            </button>
            <button
              @click="handleClose"
              type="button"
              class="mt-3 inline-flex min-h-11 w-full justify-center rounded-xl border border-gray-300 bg-white px-4 py-2 text-base font-bold text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500 sm:mt-0 sm:ml-3 sm:w-auto sm:text-sm"
            >
              {{ t('common.cancel') }}
            </button>
          </template>

          <style scoped>
          .manual-payment-footer-safe {
            padding-bottom: calc(0.75rem + env(safe-area-inset-bottom));
          }
          </style>

          <template v-else>
            <button
              @click="handleConfirm"
              :disabled="isSubmitting"
              type="button"
              class="inline-flex min-h-11 w-full items-center justify-center rounded-xl border border-transparent bg-green-600 px-4 py-2 text-base font-bold text-white shadow-sm hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:opacity-50 sm:ml-3 sm:w-auto sm:text-sm"
            >
              <Loader2 v-if="isSubmitting" class="mr-2 h-4 w-4 animate-spin" />
              <CheckCircle v-else class="mr-2 h-4 w-4" />
              {{ t('payment.confirmCash') }}
            </button>
            <button
              @click="currentStep = 'entry'"
              :disabled="isSubmitting"
              type="button"
              class="mt-3 inline-flex min-h-11 w-full items-center justify-center rounded-xl border border-gray-300 bg-white px-4 py-2 text-base font-bold text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500 disabled:opacity-50 sm:mt-0 sm:ml-3 sm:w-auto sm:text-sm"
            >
              <ArrowLeft class="mr-2 h-4 w-4" />
              {{ t('payment.backToEdit') }}
            </button>
          </template>
        </div>
      </div>
    </div>
  </div>
</template>
