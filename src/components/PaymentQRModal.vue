<script setup lang="ts">
import { computed, watch, ref } from 'vue'
import { Check, Loader2, X, AlertTriangle, Clock, Copy, Share2 } from 'lucide-vue-next'
import { getShortName, formatCurrency } from '@/utils/formatters'
import { usePaymentPolling } from '@/composables/usePaymentPolling'
import { useLangStore } from '@/stores/lang'

const langStore = useLangStore()
const t = computed(() => langStore.t)

const props = defineProps<{
  // Generic Props to replace specific ones
  code?: string
  amount?: number
  isOpen?: boolean
  // Keeping original props for now to avoid compilation errors if used elsewhere,
  // but logically mapped to the new ones
  show?: boolean
  snapshot?: any
  memberName?: string
  groupData?: any
  isPaid?: boolean
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'success'): void
  (e: 'payment-complete'): void
}>()

// Map old props to new structure if needed, or prefer explicit new props
const effectiveCode = computed(
  () =>
    props.code ||
    (props.groupData ? props.groupData.group_code : props.snapshot?.payment_code) ||
    '',
)
const effectiveAmount = computed(
  () =>
    props.amount ||
    (props.groupData
      ? props.groupData.total_amount
      : props.snapshot?.final_amount - props.snapshot?.paid_amount) ||
    0,
)
const effectiveIsOpen = computed(() => props.isOpen || props.show || false)

// Bank Info
const BANK_INFO_TP = { BANK_ID: 'TPB', ACCOUNT_NO: '10003392871', TEMPLATE: 'compact2' }
const BANK_INFO_MB = { BANK_ID: 'MB', ACCOUNT_NO: '3030191957777', TEMPLATE: 'compact2' }
const ACTIVE_BANK = BANK_INFO_MB

// QR Generation
const qrUrl = computed(() => {
  const addInfo = encodeURIComponent(`${effectiveCode.value}`)
  return `https://img.vietqr.io/image/${ACTIVE_BANK.BANK_ID}-${ACTIVE_BANK.ACCOUNT_NO}-${ACTIVE_BANK.TEMPLATE}.png?amount=${effectiveAmount.value}&addInfo=${addInfo}`
})

// Polling
const { data, startPolling, stopPolling } = usePaymentPolling(effectiveCode)

// Watch open state to start/stop polling
watch(
  [effectiveIsOpen, effectiveCode],
  ([isOpen, code]) => {
    if (isOpen) {
      if (code) {
        startPolling()
      }
    } else {
      stopPolling()
    }
  },
  { immediate: true },
)

// Watch success to auto-close
watch(
  () => data.value.success,
  (success) => {
    if (success) {
      setTimeout(() => {
        emit('success')
        emit('payment-complete')
        emit('close')
      }, 1500)
    }
  },
)

const remainingAmount = computed(() => {
  return Math.max(0, data.value.total - data.value.paid)
})

const isPartial = computed(() => data.value.paid > 0 && !data.value.success)

const copied = ref(false)
const copyCode = async () => {
  const text = `${effectiveCode.value}`
  try {
    await navigator.clipboard.writeText(text)
    copied.value = true
    setTimeout(() => {
      copied.value = false
    }, 2000)
  } catch (err) {
    console.error('Failed to copy:', err)
  }
}

const isSharing = ref(false)
const sharePayment = async () => {
  if (isSharing.value) return
  isSharing.value = true

  const shareUrl = `${window.location.origin}/pay?code=${effectiveCode.value}&amount=${effectiveAmount.value}`
  const shareTitle = t.value('payment.shareTitle', { code: effectiveCode.value })
  const shareText = t.value('payment.shareText', {
    amount: formatCurrency(effectiveAmount.value),
    code: effectiveCode.value,
  })

  try {
    const response = await fetch(qrUrl.value)
    const blob = await response.blob()
    const file = new File([blob], `badminton_qr_${effectiveCode.value}.png`, { type: 'image/png' })

    if (navigator.share) {
      const shareData: any = {
        title: shareTitle,
        text: shareText,
        url: shareUrl,
      }

      if (navigator.canShare && navigator.canShare({ files: [file] })) {
        shareData.files = [file]
      }

      await navigator.share(shareData)
    } else {
      // Fallback: Copy to clipboard
      await navigator.clipboard.writeText(`${shareTitle}\n${shareText}\n${shareUrl}`)
      alert(t.value('payment.copied'))
    }
  } catch (err) {
    console.error('Error sharing:', err)
  } finally {
    isSharing.value = false
  }
}

const close = () => {
  emit('close')
}
</script>

<template>
  <div
    v-if="effectiveIsOpen"
    class="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm transition-all duration-300"
  >
    <!-- Card -->
    <div
      class="bg-white dark:bg-gray-800 rounded-2xl shadow-2xl w-full max-w-md overflow-hidden flex flex-col relative animate-in zoom-in-95 duration-200"
    >
      <!-- Header -->
      <div
        class="p-4 border-b border-gray-100 dark:border-gray-700 flex items-center justify-between bg-gray-50 dark:bg-gray-900/50"
      >
        <h3 class="font-bold text-lg text-gray-800 dark:text-gray-100">
          {{
            isPartial
              ? t('payment.partialPayment')
              : data.success
                ? t('payment.paymentSuccess')
                : t('payment.scanQR')
          }}
        </h3>
        <button
          @click="close"
          class="p-2 hover:bg-gray-200 dark:hover:bg-gray-700 rounded-full transition-colors cursor-pointer"
        >
          <X class="w-5 h-5 text-gray-500" />
        </button>
      </div>

      <!-- Body -->
      <div class="p-6 flex flex-col items-center">
        <!-- Success State -->
        <div v-if="data.success" class="flex flex-col items-center py-8">
          <div
            class="w-20 h-20 bg-green-100 rounded-full flex items-center justify-center mb-4 animate-bounce"
          >
            <Check class="w-10 h-10 text-green-600" stroke-width="3" />
          </div>
          <h2 class="text-2xl font-bold text-green-600 mb-2">
            {{ t('payment.paidSuccessTitle') }}
          </h2>
          <p class="text-gray-500">{{ t('payment.redirecting') }}</p>
        </div>

        <!-- Waiting / Partial State -->
        <div v-else class="w-full flex flex-col items-center gap-6">
          <div class="flex flex-col items-center gap-4 w-full">
            <div class="relative group">
              <img
                :src="qrUrl"
                alt="VietQR"
                class="w-64 h-64 object-contain border rounded-xl shadow-sm transition-all duration-300 group-hover:shadow-md"
              />
              <div
                v-if="!isPartial"
                class="absolute -bottom-3 left-1/2 -translate-x-1/2 flex items-center gap-2 px-3 py-1 bg-blue-50 border border-blue-100 rounded-full text-[10px] font-bold text-blue-700 whitespace-nowrap shadow-sm"
              >
                <Loader2 class="w-3 h-3 animate-spin text-blue-600" />
                {{ t('payment.waitingTransfer') }}
              </div>
            </div>

            <button
              @click="sharePayment"
              :disabled="isSharing"
              class="w-full flex items-center justify-center gap-2 px-6 py-3 bg-indigo-600 hover:bg-indigo-700 disabled:bg-indigo-400 text-white rounded-xl font-bold text-base transition-all active:scale-95 shadow-lg shadow-indigo-100 dark:shadow-none mt-2"
            >
              <Loader2 v-if="isSharing" class="w-5 h-5 animate-spin" />
              <Share2 v-else class="w-5 h-5" />
              {{ t('payment.share') }}
            </button>
          </div>

          <div class="text-center">
            <div class="text-sm text-gray-500 mb-1">{{ t('payment.totalAmount') }}</div>
            <div class="text-3xl font-bold text-gray-900 dark:text-white tracking-tight">
              {{ formatCurrency(effectiveAmount) }}
            </div>
            <button
              @click="copyCode"
              class="mt-2 flex items-center gap-2 px-5 py-2.5 rounded-xl border transition-all duration-200 group cursor-pointer shadow-sm hover:shadow-md active:scale-95 mx-auto"
              :class="
                copied
                  ? 'bg-emerald-50 hover:bg-emerald-100 border-emerald-200'
                  : 'bg-gray-100 hover:bg-gray-200 border-gray-200 dark:bg-gray-700 dark:hover:bg-gray-600 dark:border-gray-600'
              "
              :title="t('payment.copyCode')"
            >
              <span
                class="text-sm font-mono font-bold select-all tracking-wide"
                :class="copied ? 'text-emerald-700' : 'text-gray-700 dark:text-gray-200'"
              >
                {{ effectiveCode }}
              </span>
              <div
                class="flex items-center justify-center w-6 h-6 rounded-full bg-white dark:bg-gray-600 border shadow-sm transition-colors ml-1"
                :class="copied ? 'border-emerald-100' : 'border-gray-200 dark:border-gray-500'"
              >
                <Check v-if="copied" class="w-3.5 h-3.5 text-emerald-600 animate-in zoom-in" />
                <Copy
                  v-else
                  class="w-3.5 h-3.5 transition-colors text-gray-400 group-hover:text-gray-600 dark:text-gray-400 dark:group-hover:text-gray-200"
                />
              </div>
            </button>
          </div>

          <!-- Instructions -->
          <div
            v-if="!isPartial"
            class="w-full bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3 text-sm text-gray-600 dark:text-gray-300 space-y-2"
          >
            <div class="flex items-center gap-2">
              <span
                class="flex-shrink-0 w-5 h-5 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center text-xs font-bold"
                >1</span
              >
              <span v-html="t('payment.step1')"></span>
            </div>
            <div class="flex items-center gap-2">
              <span
                class="flex-shrink-0 w-5 h-5 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center text-xs font-bold"
                >2</span
              >
              <span v-html="t('payment.step2', { code: effectiveCode })"></span>
            </div>
            <div class="flex items-center gap-2">
              <span
                class="flex-shrink-0 w-5 h-5 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center text-xs font-bold"
                >3</span
              >
              <span>{{ t('payment.step3') }}</span>
            </div>
          </div>

          <!-- Partial Payment Alert -->
          <div
            v-if="isPartial"
            class="w-full bg-orange-50 border border-orange-200 rounded-xl p-4 animate-in slide-in-from-bottom-5"
          >
            <div class="flex items-start gap-3 mb-3">
              <div class="p-2 bg-orange-100 rounded-lg">
                <AlertTriangle class="w-5 h-5 text-orange-600" />
              </div>
              <div>
                <div class="font-bold text-orange-800">{{ t('payment.incompletePayment') }}</div>
                <div class="text-sm text-orange-700">
                  {{ t('payment.received') }}
                  <span class="font-bold">{{ formatCurrency(data.paid) }}</span
                  >. {{ t('payment.missing') }}
                  <span class="font-bold">{{ formatCurrency(remainingAmount) }}</span
                  >.
                </div>
              </div>
            </div>

            <!-- Member Details List -->
            <div class="mt-4 space-y-2 max-h-40 overflow-y-auto pr-1">
              <template v-for="(detail, idx) in data.details" :key="idx">
                <div
                  class="flex items-center justify-between p-2 rounded-lg bg-white/60 border border-orange-100 text-sm"
                >
                  <span class="font-medium text-gray-700">{{ getShortName(detail.name) }}</span>
                  <div class="flex items-center gap-2">
                    <span class="font-mono text-gray-600">{{ formatCurrency(detail.amount) }}</span>
                    <span
                      v-if="detail.status === 'paid'"
                      class="text-green-600 bg-green-100 p-0.5 rounded"
                    >
                      <Check class="w-4 h-4" />
                    </span>
                    <span v-else class="text-red-500 bg-red-100 p-0.5 rounded">
                      <Clock class="w-4 h-4" />
                    </span>
                  </div>
                </div>
              </template>
            </div>

            <div class="mt-3 text-xs text-center text-orange-600 italic">
              {{ t('payment.payRemaining') }}
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
