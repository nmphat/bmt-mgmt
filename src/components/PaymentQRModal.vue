<script setup lang="ts">
import { computed, ref } from 'vue'
import { X, Copy, Check } from 'lucide-vue-next'
import { BANK_INFO } from '@/types'
import type { CostSnapshot, GroupPaymentData } from '@/types'
import { useLangStore } from '@/stores/lang'

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
}>()

const copied = ref(false)

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
  const code = props.groupData ? props.groupData.group_code : props.snapshot?.payment_code
  if (!code) return
  await navigator.clipboard.writeText(code)
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
</script>

<template>
  <div
    v-if="show"
    class="fixed inset-0 z-[100] overflow-y-auto"
    aria-labelledby="modal-title"
    role="dialog"
    aria-modal="true"
  >
    <div
      class="flex items-center justify-center min-h-screen px-4 pt-4 pb-20 text-center sm:block sm:p-0"
    >
      <!-- Background overlay -->
      <div
        class="fixed inset-0 transition-opacity bg-gray-500/75"
        aria-hidden="true"
        @click="emit('close')"
      ></div>

      <!-- Modal panel -->
      <div
        class="relative z-10 inline-block overflow-hidden text-left align-bottom transition-all transform bg-white rounded-lg shadow-xl sm:my-8 sm:align-middle sm:max-w-lg sm:w-full"
      >
        <div class="px-4 pt-5 pb-4 bg-white sm:p-6 sm:pb-4">
          <div class="flex justify-between items-start mb-4">
            <h3 class="text-xl font-bold text-gray-900" id="modal-title">
              {{
                isPaid
                  ? t('payment.paymentSuccess')
                  : props.groupData
                    ? t('payment.groupPaymentFor', { count: props.groupData.member_count })
                    : t('payment.paymentFor', { name: memberName })
              }}
            </h3>
            <button
              @click="emit('close')"
              class="text-gray-400 hover:text-gray-600 focus:outline-none"
            >
              <X class="w-6 h-6" />
            </button>
          </div>

          <div v-if="snapshot || groupData" class="mt-4 flex flex-col items-center">
            <!-- Paid State -->
            <div v-if="isPaid" class="py-8 flex flex-col items-center">
              <div
                class="w-20 h-20 bg-green-100 rounded-full flex items-center justify-center mb-4 animate-bounce"
              >
                <Check class="w-12 h-12 text-green-600 stroke-[3px]" />
              </div>
              <p class="text-2xl font-bold text-gray-900 mb-2">{{ t('payment.thanks') }}</p>
              <p
                class="text-gray-600 text-center"
                v-html="
                  props.groupData
                    ? t('payment.manualPaymentSuccess')
                    : t('payment.recordingSuccess', { name: memberName })
                "
              ></p>
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
                  :alt="props.groupData ? t('payment.scanQR') : 'QR Payment for ' + memberName"
                  class="w-64 h-64 object-contain"
                />
                <div
                  class="absolute inset-0 flex items-center justify-center opacity-0 hover:opacity-100 transition-opacity bg-white/10 backdrop-blur-[2px] cursor-zoom-in"
                >
                  <span
                    class="bg-white/90 px-3 py-1 rounded-full text-xs font-medium text-gray-700 shadow-sm border border-gray-100"
                    >{{ t('payment.scanToPayManual') }}</span
                  >
                </div>
              </div>

              <div class="w-full space-y-4">
                <div class="bg-indigo-50 p-4 rounded-lg border border-indigo-100">
                  <div class="flex justify-between items-center mb-1">
                    <span class="text-xs font-semibold text-indigo-700 uppercase tracking-wider">{{
                      t('payment.transferContent')
                    }}</span>
                    <button
                      @click="copyPaymentCode"
                      class="text-indigo-600 hover:text-indigo-800 transition flex items-center gap-1 text-xs font-medium"
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
                    {{ groupData ? groupData.group_code : snapshot?.payment_code }}
                  </p>
                  <p class="text-sm text-indigo-700 mt-2 italic">
                    <template v-if="props.groupData">
                      <span
                        v-html="
                          t('payment.groupInstructions', {
                            count: props.groupData.member_count,
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

                <div class="text-sm text-gray-500 text-center">
                  <p>{{ t('payment.autoUpdateNote') }}</p>
                </div>
              </div>
            </template>
          </div>
        </div>
        <div class="px-4 py-3 bg-gray-50 sm:px-6 sm:flex sm:flex-row-reverse">
          <button
            type="button"
            class="inline-flex justify-center w-full px-6 py-2 text-base font-bold text-white rounded-md shadow-sm transition sm:ml-3 sm:w-auto sm:text-sm"
            :class="
              isPaid
                ? 'bg-green-600 hover:bg-green-700 font-bold'
                : 'bg-indigo-600 hover:bg-indigo-700 font-medium'
            "
            @click="emit('close')"
          >
            {{ isPaid ? t('payment.confirmAndClose') : t('payment.doneButton') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
