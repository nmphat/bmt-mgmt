<script setup lang="ts">
import { computed, ref, watch, onUnmounted } from 'vue'
import { Copy, Check } from 'lucide-vue-next'
import type { CostSnapshot, GroupPaymentData } from '@/types'
import { useLangStore } from '@/stores/lang'
import { useBankConfigStore } from '@/stores/bankConfig'
import { supabase } from '@/lib/supabase'
import { useToast } from 'vue-toastification'
import ModalPanel from '@/components/ui/ModalPanel.vue'
import ModalHeader from '@/components/ui/ModalHeader.vue'
import ModalFooter from '@/components/ui/ModalFooter.vue'
import Button from '@/components/ui/Button.vue'
import Alert from '@/components/ui/Alert.vue'

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
        data-ds="Modal Scrim"
        data-ds-style="Default"
        class="fixed inset-0 bg-surface-scrim/75 transition-opacity"
        aria-hidden="true"
        @click="handleClose"
      ></div>

      <ModalPanel width="lg">
        <template #header>
          <ModalHeader
            title-id="modal-title"
            :title="
              isPaid || isPaymentComplete
                ? t('payment.paymentSuccess')
                : props.groupData
                  ? t('payment.groupPaymentFor', { count: groupMemberCount })
                  : t('payment.paymentFor', { name: memberName })
            "
            :close-label="t('common.cancel')"
            @close="handleClose"
          />
        </template>

        <div
          v-if="snapshot || groupData"
          data-ds="Payment QR Body"
          class="flex flex-col items-center gap-5 py-5"
        >
          <!-- Paid State -->
          <div
            v-if="isPaid || isPaymentComplete"
            data-ds="Result State"
            data-ds-style="Circle"
            class="flex flex-col items-center gap-3 py-8 text-center"
            aria-live="polite"
          >
            <div
              data-ds="Icon Tile"
              data-ds-style="Success Circle"
              class="flex size-20 items-center justify-center rounded-full bg-status-success animate-bounce motion-reduce:animate-none"
            >
              <Check aria-hidden="true" class="size-12 stroke-[3px] text-fg-success" />
            </div>
            <p class="text-xl font-bold text-fg-primary">
              {{ t('payment.thanks') }}
            </p>
            <p class="max-w-sm text-base text-fg-secondary">{{ t('payment.qrSuccess') }}</p>
          </div>

          <!-- Pending State -->
          <template v-else>
            <div
              data-ds="Amount Panel"
              data-ds-style="Brand"
              class="flex w-full flex-col items-center gap-1 rounded-xl border border-line-brand-muted bg-surface-brand-subtle p-4"
            >
              <span class="text-sm font-bold text-fg-brand-strong">{{
                t('payment.amountToPay')
              }}</span>
              <span class="text-3xl font-bold text-fg-brand-strong tabular-nums">{{
                formatCurrency(remainingAmount)
              }}</span>
            </div>

            <div
              data-ds="QR Image"
              data-ds-style="Dashed"
              class="rounded-xl border-2 border-dashed border-line-divider bg-surface-card p-2 shadow-sm"
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

            <div
              data-ds="Transfer Code Card"
              data-ds-style="Modal"
              :data-ds-state="copied ? 'Copied' : 'Default'"
              class="flex w-full flex-col gap-2 rounded-xl border border-line-brand-muted bg-surface-brand-subtle p-4"
            >
              <div class="flex items-center justify-between gap-3">
                <span class="text-sm font-bold text-fg-brand-strong">{{
                  t('payment.transferContent')
                }}</span>
                <button
                  type="button"
                  data-ds="Copy Button"
                  :data-ds-state="copied ? 'Copied' : 'Default'"
                  class="inline-flex h-control-md items-center gap-1 rounded-control px-3 text-sm font-bold text-fg-brand transition hover:bg-surface-brand-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-line-focus"
                  :aria-label="t('payment.copyCode')"
                  @click="copyPaymentCode"
                >
                  <template v-if="!copied">
                    <Copy class="size-4" /> {{ t('payment.copyCode') }}
                  </template>
                  <template v-else>
                    <Check class="size-4 text-fg-success" /> {{ t('payment.copied') }}
                  </template>
                </button>
              </div>
              <p class="break-all font-mono text-xl font-bold text-fg-brand-deep">
                {{ paymentInfo }}
              </p>
              <p class="text-sm italic text-fg-brand-strong">
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
              class="w-full rounded-xl border border-line-divider bg-surface-subtle p-3"
            >
              <p class="mb-2 px-1 text-sm font-bold text-fg-muted">
                {{ t('session.memberBreakdown') }}
              </p>
              <div class="flex max-h-40 flex-col gap-1 overflow-y-auto">
                <div
                  v-for="m in groupMembers"
                  :key="m.name"
                  data-ds="Amount List Item"
                  data-ds-style="Simple"
                  class="flex justify-between gap-3 rounded-lg bg-surface-card px-3 py-2 text-sm"
                >
                  <span class="min-w-0 font-bold text-fg-secondary">{{ m.name }}</span>
                  <span class="shrink-0 font-bold text-fg-primary tabular-nums">{{
                    formatCurrency(m.amount)
                  }}</span>
                </div>
              </div>
            </div>

            <Alert tone="Neutral" align="Center" class="w-full" aria-live="polite">
              <p>{{ t('payment.qrStatusNote') }}</p>
            </Alert>
          </template>
        </div>

        <template #footer>
          <ModalFooter background="Gray" buttons="One" class="qr-modal-footer-safe">
            <template #primary>
              <Button
                size="Default"
                :variant="isPaid || isPaymentComplete ? 'Success' : 'Primary'"
                @click="handleClose"
              >
                {{
                  isPaid || isPaymentComplete
                    ? t('payment.confirmAndClose')
                    : t('payment.doneButton')
                }}
              </Button>
            </template>
          </ModalFooter>
        </template>
      </ModalPanel>
    </div>
  </div>
</template>

<style scoped>
.qr-modal-footer-safe {
  padding-bottom: calc(0.75rem + env(safe-area-inset-bottom));
}
</style>
