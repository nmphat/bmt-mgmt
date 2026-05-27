<script setup lang="ts">
import { computed, ref, watch, onUnmounted } from 'vue'
import { X, Copy, Check } from 'lucide-vue-next'
import type { CostSnapshot, GroupPaymentData } from '@/types'
import { useLangStore } from '@/stores/lang'
import { useBankConfigStore } from '@/stores/bankConfig'
import { supabase } from '@/lib/supabase'
import { useToast } from 'vue-toastification'

const langStore = useLangStore()
const bankConfigStore = useBankConfigStore()
const toast = useToast()
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
  const bankConfig = bankConfigStore.activeBank
  return `https://img.vietqr.io/image/${bankConfig.bank_id}-${bankConfig.account_number}-${bankConfig.template}.png?amount=${amount}&addInfo=${addInfo}`
})

async function copyPaymentCode() {
  if (!paymentInfo.value) return
  if (!navigator.clipboard?.writeText) {
    toast.error(t.value('payment.copyFailed'))
    return
  }

  try {
    await navigator.clipboard.writeText(paymentInfo.value)
    copied.value = true
    setTimeout(() => {
      copied.value = false
    }, 2000)
  } catch (error) {
    console.error('Error copying payment code:', error)
    toast.error(t.value('payment.copyFailed'))
  }
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

const groupMembers = computed(() => props.groupData?.members ?? [])

const toFiniteNumber = (value: unknown) => {
  const numberValue = typeof value === 'number' ? value : Number(value)
  return Number.isFinite(numberValue) ? numberValue : null
}

const isSnapshotPaid = (snapshot: {
  status?: string | null
  paid_amount?: unknown
  final_amount?: unknown
}) => {
  if (snapshot.status === 'paid') return true

  const paidAmount = toFiniteNumber(snapshot.paid_amount)
  const finalAmount = toFiniteNumber(snapshot.final_amount)

  return paidAmount !== null && finalAmount !== null && paidAmount >= finalAmount
}

async function checkPaymentStatus(): Promise<boolean> {
  try {
    if (props.groupData) {
      const snapshotIds = Array.from(new Set(props.groupData.snapshot_ids ?? []))
      const query = supabase
        .from('session_costs_snapshot')
        .select('id, paid_amount, final_amount, status')

      const { data, error } =
        snapshotIds.length > 0
          ? await query.in('id', snapshotIds)
          : await query.eq('payment_code', props.groupData.group_code)

      if (error) {
        console.error('Error checking group payment status:', error)
        return false
      }

      if (!data || data.length === 0) return false
      if (snapshotIds.length > 0 && data.length !== snapshotIds.length) return false

      return data.every(isSnapshotPaid)
    } else if (props.snapshot) {
      // For single payment, check the specific snapshot
      const { data, error } = await supabase
        .from('session_costs_snapshot')
        .select('paid_amount, final_amount, status')
        .eq('id', props.snapshot.id)
        .single()

      if (error) {
        console.error('Error checking payment status:', error)
        return false
      }

      return data ? isSnapshotPaid(data) : false
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

async function ensureBankConfig() {
  try {
    await bankConfigStore.fetchConfigs()
  } catch (error) {
    console.error('Error loading bank config:', error)
    toast.error(t.value('payment.bankConfigLoadError'))
  }
}

// Watch for modal show/hide to start/stop polling
watch(
  () => props.show,
  async (newShow) => {
    if (newShow && !props.isPaid) {
      await ensureBankConfig()
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
        class="fixed inset-0 bg-gray-500/75 transition-opacity"
        aria-hidden="true"
        @click="handleClose"
      ></div>

      <!-- Modal panel -->
      <div
        class="relative z-10 flex max-h-[88dvh] w-full flex-col overflow-hidden rounded-t-2xl bg-white text-left align-bottom shadow-xl transition-all sm:max-w-lg sm:rounded-2xl"
      >
        <div class="shrink-0 border-b border-gray-100 bg-white px-4 py-4 sm:px-6">
          <div class="flex items-start justify-between gap-3">
            <h3 class="text-[20px] font-bold leading-[1.2] text-gray-900" id="modal-title">
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
              class="flex flex-col items-center py-8 text-center"
              aria-live="polite"
            >
              <div
                class="mb-4 flex h-20 w-20 items-center justify-center rounded-full bg-green-100 animate-bounce"
              >
                <Check class="h-12 w-12 text-green-600 stroke-[3px]" />
              </div>
              <p class="mb-2 text-[20px] font-bold leading-[1.2] text-gray-900">{{ t('payment.thanks') }}</p>
              <p class="max-w-sm text-gray-600">{{ t('payment.qrSuccess') }}</p>
            </div>

            <!-- Pending State -->
            <template v-else>
              <div class="mb-5 w-full rounded-2xl border border-indigo-100 bg-indigo-50/70 p-4 text-center">
                <span class="mb-1 block text-sm font-bold text-indigo-700">{{
                  t('payment.amountToPay')
                }}</span>
                <span class="text-[32px] font-bold leading-[1.05] text-indigo-700 tabular-nums">{{
                  formatCurrency(remainingAmount)
                }}</span>
              </div>

              <div
                class="relative mb-5 rounded-2xl border-2 border-dashed border-gray-200 bg-white p-2 shadow-sm"
              >
                <img
                  :src="qrUrl"
                  :alt="
                    props.groupData
                      ? t('payment.groupPaymentFor', { count: groupMemberCount })
                      : t('payment.paymentFor', { name: memberName })
                  "
                  class="h-64 w-64 max-w-full object-contain"
                />
              </div>

              <div class="w-full space-y-4">
                <div class="rounded-2xl border border-indigo-100 bg-indigo-50 p-4">
                  <div class="mb-2 flex items-center justify-between gap-3">
                    <span class="text-sm font-bold text-indigo-700">{{
                      t('payment.transferContent')
                    }}</span>
                    <button
                      type="button"
                      @click="copyPaymentCode"
                      class="inline-flex min-h-11 min-w-11 items-center justify-center gap-1 rounded-xl px-3 text-sm font-bold text-indigo-600 transition hover:bg-indigo-100 hover:text-indigo-800 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                      :aria-label="t('payment.copyCode')"
                    >
                      <template v-if="!copied">
                        <Copy class="h-4 w-4" /> {{ t('payment.copyCode') }}
                      </template>
                      <template v-else>
                        <Check class="h-4 w-4 text-green-600" /> {{ t('payment.copied') }}
                      </template>
                    </button>
                  </div>
                  <p class="break-all font-mono text-[20px] font-bold leading-[1.2] text-indigo-900">
                    {{ paymentInfo }}
                  </p>
                  <p class="mt-2 text-sm italic text-indigo-700">
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
                  class="rounded-2xl border border-gray-100 bg-gray-50 p-3"
                >
                  <p
                    class="mb-2 px-1 text-sm font-bold text-gray-500"
                  >
                    {{ t('session.memberBreakdown') }}
                  </p>
                  <div class="max-h-40 space-y-1 overflow-y-auto">
                    <div
                      v-for="m in groupMembers"
                      :key="m.name"
                      class="flex items-center justify-between gap-3 rounded-lg bg-white px-3 py-2 text-sm"
                    >
                      <span class="min-w-0 font-bold text-gray-600">{{ m.name }}</span>
                      <span class="shrink-0 font-bold text-gray-900 tabular-nums">{{
                        formatCurrency(m.amount)
                      }}</span>
                    </div>
                  </div>
                </div>

                <div
                  class="rounded-xl bg-gray-50 px-4 py-3 text-center text-sm text-gray-600"
                  aria-live="polite"
                >
                  <p>{{ t('payment.qrStatusNote') }}</p>
                </div>
              </div>
            </template>
          </div>
        </div>

        <div
          class="qr-modal-footer-safe sticky bottom-0 shrink-0 border-t border-gray-100 bg-gray-50 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse"
        >
          <button
            type="button"
            class="inline-flex min-h-11 w-full justify-center rounded-xl px-6 py-2 text-base font-bold text-white shadow-sm transition focus:outline-none focus:ring-2 focus:ring-indigo-500 sm:ml-3 sm:w-auto sm:text-sm"
            :class="
              isPaid || isPaymentComplete
                ? 'bg-green-600 hover:bg-green-700 font-bold'
                : 'bg-indigo-600 hover:bg-indigo-700 font-bold'
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

<style scoped>
.qr-modal-footer-safe {
  padding-bottom: calc(0.75rem + env(safe-area-inset-bottom));
}
</style>
