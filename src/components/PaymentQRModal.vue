<script setup lang="ts">
import { computed, ref, watch, onUnmounted } from 'vue'
import { X, Copy, Check } from 'lucide-vue-next'
import { BANK_INFO } from '@/types'
import type { CostSnapshot, GroupPaymentData } from '@/types'
import { useLangStore } from '@/stores/lang'
import { supabase } from '@/lib/supabase'

const langStore = useLangStore()
const t = computed(() => langStore.t)

const props = defineProps<{
  show: boolean
  snapshot: CostSnapshot | null
  memberName: string
  groupData?: GroupPaymentData | null
  isPaid?: boolean
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'payment-complete'): void
}>()

const copied = ref(false)
const pollTimer = ref<number | null>(null)
const isPaymentComplete = ref(false)

const remainingAmount = computed(() => {
  if (props.groupData) return props.groupData.total_amount
  if (!props.snapshot) return 0
  return props.snapshot.final_amount - props.snapshot.paid_amount
})

const paymentInfo = computed(() => {
  if (props.groupData) return props.groupData.group_code
  if (!props.snapshot) return ''
  return `${props.snapshot.payment_code} ${props.memberName}`
})

const qrUrl = computed(() => {
  if (!props.snapshot && !props.groupData) return ''
  const amount = remainingAmount.value
  const addInfo = encodeURIComponent(paymentInfo.value)
  return `https://img.vietqr.io/image/${BANK_INFO.BANK_ID}-${BANK_INFO.ACCOUNT_NO}-${BANK_INFO.TEMPLATE}.png?amount=${amount}&addInfo=${addInfo}`
})

async function copyPaymentCode() {
  if (!paymentInfo.value) return
  await navigator.clipboard.writeText(paymentInfo.value)
  copied.value = true
  setTimeout(() => {
    copied.value = false
  }, 2000)
}

const formatCurrency = (value: number) => {
  return new Intl.NumberFormat(langStore.currentLang === 'vi' ? 'vi-VN' : 'en-US', {
    style: 'currency',
    currency: 'VND',
    maximumFractionDigits: 0,
  }).format(value)
}

const groupMemberCount = computed(() => {
  if (!props.groupData) return 0
  // Fallback to members.length if member_count is missing from RPC response
  return props.groupData.member_count ?? props.groupData.members?.length ?? 0
})

async function checkPaymentStatus(): Promise<boolean> {
  try {
    if (props.groupData) {
      // For group payment, check all snapshots with the group_code
      const { data, error } = await supabase
        .from('session_costs_snapshot')
        .select('paid_amount, final_amount')
        .eq('payment_code', props.groupData.group_code)

      if (error) {
        console.error('Error checking group payment status:', error)
        return false
      }

      // Check if all snapshots are fully paid
      return data?.every((snapshot) => snapshot.paid_amount >= snapshot.final_amount) ?? false
    } else if (props.snapshot) {
      // For single payment, check the specific snapshot
      const { data, error } = await supabase
        .from('session_costs_snapshot')
        .select('paid_amount, final_amount')
        .eq('id', props.snapshot.id)
        .single()

      if (error) {
        console.error('Error checking payment status:', error)
        return false
      }

      return data ? data.paid_amount >= data.final_amount : false
    }
    return false
  } catch (error) {
    console.error('Exception checking payment status:', error)
    return false
  }
}

function startPolling() {
  if (!props.show) return
  if (pollTimer.value) return
  if (props.isPaid || isPaymentComplete.value) return

  pollTimer.value = window.setInterval(async () => {
    const isPaid = await checkPaymentStatus()
    if (isPaid) {
      isPaymentComplete.value = true
      stopPolling()
      emit('payment-complete')
    }
  }, 5000) // Poll every 5 seconds
}

function stopPolling() {
  if (pollTimer.value) {
    clearInterval(pollTimer.value)
    pollTimer.value = null
  }
}

function handleClose() {
  stopPolling()
  emit('close')
}

// Watch for modal show/hide to start/stop polling
watch(
  () => props.show,
  (newShow) => {
    if (newShow && !props.isPaid) {
      startPolling()
    } else {
      stopPolling()
      copied.value = false
      if (!newShow) {
        isPaymentComplete.value = false
      }
    }
  },
)

// Cleanup on unmount
onUnmounted(() => {
  stopPolling()
})
</script>

<template>
  <div
    v-if="show"
    class="fixed inset-0 z-[100]"
    aria-labelledby="modal-title"
    role="dialog"
    aria-modal="true"
  >
    <div
      class="flex min-h-screen items-end justify-center px-0 text-center sm:items-center sm:px-4 sm:py-8"
    >
      <!-- Background overlay -->
      <div
        class="fixed inset-0 transition-opacity bg-gray-500/75"
        aria-hidden="true"
        @click="handleClose"
      ></div>

      <!-- Modal panel -->
      <div
        class="relative z-10 flex max-h-[88dvh] w-full flex-col overflow-hidden rounded-t-2xl bg-white text-left align-bottom shadow-xl transition-all sm:max-h-[calc(100vh-4rem)] sm:max-w-lg sm:rounded-lg"
      >
        <div class="shrink-0 border-b border-gray-100 bg-white px-4 py-4 sm:px-6">
          <div class="flex items-start justify-between gap-3">
            <h3 class="text-xl font-bold text-gray-900" id="modal-title">
              {{
                isPaid || isPaymentComplete
                  ? t('payment.paymentSuccess')
                  : props.groupData
                    ? t('payment.groupPaymentFor', { count: groupMemberCount })
                    : t('payment.paymentFor', { name: memberName })
              }}
            </h3>
            <button
              type="button"
              @click="handleClose"
              class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-full text-gray-500 hover:bg-gray-100 hover:text-gray-700 focus:outline-none focus:ring-2 focus:ring-indigo-500"
              :aria-label="t('common.cancel')"
            >
              <X class="w-6 h-6" />
            </button>
          </div>
        </div>

        <div class="flex-1 overflow-y-auto bg-white px-4 py-5 sm:px-6">
          <div v-if="snapshot || groupData" class="flex flex-col items-center">
            <!-- Paid State -->
            <div
              v-if="isPaid || isPaymentComplete"
              class="py-8 flex flex-col items-center"
              aria-live="polite"
            >
              <div
                class="w-20 h-20 bg-green-100 rounded-full flex items-center justify-center mb-4 animate-bounce"
              >
                <Check class="w-12 h-12 text-green-600 stroke-[3px]" />
              </div>
              <p class="text-2xl font-bold text-gray-900 mb-2">{{ t('payment.thanks') }}</p>
              <p class="text-gray-600 text-center">{{ t('payment.qrSuccess') }}</p>
            </div>

            <!-- Pending State -->
            <template v-else>
              <div class="mb-6 p-4 bg-gray-50 rounded-lg w-full text-center">
                <span class="text-gray-500 text-sm block mb-1">{{ t('payment.amountToPay') }}</span>
                <span class="text-2xl font-bold text-indigo-600">{{
                  formatCurrency(remainingAmount)
                }}</span>
              </div>

              <div
                class="relative bg-white p-2 border-2 border-dashed border-gray-200 rounded-xl mb-6 shadow-sm"
              >
                <img
                  :src="qrUrl"
                  :alt="
                    props.groupData
                      ? t('payment.scanQR')
                      : t('payment.paymentFor', { name: memberName })
                  "
                  class="w-64 h-64 object-contain"
                />
              </div>

              <div class="w-full space-y-4">
                <div class="bg-indigo-50 p-4 rounded-lg border border-indigo-100">
                  <div class="flex justify-between items-center mb-1">
                    <span class="text-xs font-semibold text-indigo-700 uppercase tracking-wider">{{
                      t('payment.transferContent')
                    }}</span>
                    <button
                      @click="copyPaymentCode"
                      class="inline-flex min-h-11 items-center gap-1 rounded-md px-2 text-xs font-bold text-indigo-600 transition hover:bg-indigo-100 hover:text-indigo-800 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    >
                      <template v-if="!copied">
                        <Copy class="w-3 h-3" /> {{ t('payment.copyCode') }}
                      </template>
                      <template v-else>
                        <Check class="w-3 h-3 text-green-600" /> {{ t('payment.copied') }}
                      </template>
                    </button>
                  </div>
                  <p class="text-xl font-mono font-bold text-indigo-900 break-all">
                    {{ paymentInfo }}
                  </p>
                  <p class="text-sm text-indigo-700 mt-2 italic">
                    <template v-if="props.groupData">
                      <span
                        v-html="
                          t('payment.groupInstructions', {
                            count: groupMemberCount,
                            code: props.groupData.group_code,
                          })
                        "
                      ></span>
                    </template>
                    <template v-else>
                      {{ t('payment.keepCodeNote') }}
                    </template>
                  </p>
                </div>

                <!-- Group Members Breakdown -->
                <div
                  v-if="props.groupData"
                  class="bg-gray-50 border border-gray-100 rounded-lg p-3"
                >
                  <p
                    class="text-[10px] font-bold text-gray-400 uppercase tracking-widest mb-2 px-1"
                  >
                    {{ t('session.memberBreakdown') }}
                  </p>
                  <div class="space-y-1 max-h-40 overflow-y-auto">
                    <div
                      v-for="m in props.groupData.members"
                      :key="m.name"
                      class="flex justify-between items-center text-sm px-1"
                    >
                      <span class="text-gray-600 font-medium">{{ m.name }}</span>
                      <span class="text-gray-900 font-bold tabular-nums">{{
                        formatCurrency(m.amount)
                      }}</span>
                    </div>
                  </div>
                </div>

                <div class="text-sm text-gray-500 text-center" aria-live="polite">
                  <p>{{ t('payment.qrStatusNote') }}</p>
                </div>
              </div>
            </template>
          </div>
        </div>

        <div
          class="sticky bottom-0 shrink-0 border-t border-gray-100 bg-gray-50 px-4 py-3 pb-[calc(0.75rem+env(safe-area-inset-bottom))] sm:px-6 sm:flex sm:flex-row-reverse"
        >
          <button
            type="button"
            class="inline-flex min-h-11 justify-center w-full px-6 py-2 text-base font-bold text-white rounded-md shadow-sm transition sm:ml-3 sm:w-auto sm:text-sm"
            :class="
              isPaid || isPaymentComplete
                ? 'bg-green-600 hover:bg-green-700 font-bold'
                : 'bg-indigo-600 hover:bg-indigo-700 font-medium'
            "
            @click="handleClose"
          >
            {{
              isPaid || isPaymentComplete ? t('payment.confirmAndClose') : t('payment.doneButton')
            }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
