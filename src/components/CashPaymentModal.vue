<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import { useToast } from 'vue-toastification'
import { useLangStore } from '@/stores/lang'
import { DollarSign, Loader2, X, CheckCircle, AlertTriangle } from 'lucide-vue-next'

interface UnpaidSnapshot {
  snapshot_id: string
  session_title: string
  start_time: string
  remaining_amount: number
}

const props = defineProps<{
  show: boolean
  memberId: string
  memberName: string
  totalDebt: number
}>()

const emit = defineEmits(['close', 'success'])
const toast = useToast()
const langStore = useLangStore()
const t = computed(() => langStore.t)

const snapshots = ref<UnpaidSnapshot[]>([])
const amount = ref(0)
const isSubmitting = ref(false)
const loadingSnapshots = ref(false)
const currentStep = ref<'preview' | 'confirm'>('preview')

const formatCurrency = (value: number) => {
  return new Intl.NumberFormat(langStore.currentLang === 'vi' ? 'vi-VN' : 'en-US', {
    style: 'currency',
    currency: 'VND',
    maximumFractionDigits: 0,
  }).format(value)
}

const allocationPreview = computed(() => {
  let remaining = amount.value
  return snapshots.value.map((s) => {
    const alloc = Math.min(s.remaining_amount, remaining)
    remaining = Math.max(0, remaining - alloc)
    return { ...s, allocated: alloc }
  })
})

const totalAllocated = computed(() =>
  allocationPreview.value.reduce((sum, s) => sum + s.allocated, 0),
)

watch(
  () => props.show,
  async (show) => {
    if (show) {
      currentStep.value = 'preview'
      await fetchSnapshots()
      amount.value = props.totalDebt
    }
  },
)

async function fetchSnapshots() {
  loadingSnapshots.value = true
  try {
    const { data, error } = await supabase
      .from('view_member_session_details')
      .select('snapshot_id, session_title, start_time, remaining_amount')
      .eq('member_id', props.memberId)
      .gt('remaining_amount', 0)
      .order('start_time', { ascending: true })

    if (error) throw error
    snapshots.value = (data as UnpaidSnapshot[]) || []
  } catch (error: any) {
    console.error('Error fetching snapshots:', error)
    toast.error(t.value('toast.error', { message: error.message }))
  } finally {
    loadingSnapshots.value = false
  }
}

function proceedToConfirm() {
  if (isNaN(amount.value) || amount.value <= 0) {
    toast.error(t.value('payment.amountPositiveError'))
    return
  }
  if (snapshots.value.length === 0) {
    toast.info(t.value('debt.noDebt'))
    return
  }
  currentStep.value = 'confirm'
}

async function handleConfirm() {
  isSubmitting.value = true
  let remainingInput = amount.value
  const paidSnapshotIds: string[] = []
  let failedCount = 0

  try {
    for (const snapshot of snapshots.value) {
      if (remainingInput <= 0) break

      // Re-fetch remaining_amount to guard against stale data
      const { data: freshSnapshot, error: fetchError } = await supabase
        .from('session_costs_snapshot')
        .select('paid_amount, final_amount')
        .eq('id', snapshot.snapshot_id)
        .single()

      if (fetchError || !freshSnapshot) {
        failedCount++
        continue
      }

      const freshRemaining =
        (freshSnapshot.final_amount || 0) - (freshSnapshot.paid_amount || 0)
      if (freshRemaining <= 0) continue // Already paid by another admin

      const payment = Math.min(freshRemaining, remainingInput)
      if (payment <= 0) continue

      const { error: rpcError } = await supabase.rpc('add_manual_payment', {
        p_snapshot_id: snapshot.snapshot_id,
        p_amount: payment,
        p_note: t.value('payment.cash'),
      })

      if (rpcError) {
        failedCount++
        continue
      }

      remainingInput -= payment
      paidSnapshotIds.push(snapshot.snapshot_id)
    }

    if (failedCount === 0) {
      toast.success(
        t.value('payment.cashPaymentSuccess', { count: paidSnapshotIds.length }),
      )
    } else {
      toast.warning(
        t.value('payment.cashPaymentPartial', {
          success: paidSnapshotIds.length,
          total: snapshots.value.length,
          error: failedCount,
        }),
      )
    }

    if (paidSnapshotIds.length > 0) {
      emit('success')
    }
    emit('close')
  } catch (error: any) {
    console.error('Error in cash payment loop:', error)
    toast.error(t.value('toast.error', { message: error.message }))
  } finally {
    isSubmitting.value = false
  }
}

function handleClose() {
  if (isSubmitting.value) return
  emit('close')
}
</script>

<template>
  <div
    v-if="show"
    class="fixed inset-0 z-50"
    aria-labelledby="cash-payment-title"
    role="dialog"
    aria-modal="true"
  >
    <div
      class="flex min-h-screen items-end justify-center px-0 text-center sm:items-center sm:px-4 sm:py-8"
    >
      <!-- Overlay -->
      <div
        class="fixed inset-0 bg-gray-500/75 transition-opacity"
        aria-hidden="true"
        @click="handleClose"
      ></div>

      <!-- Modal -->
      <div
        class="relative z-10 flex max-h-[88dvh] w-full flex-col overflow-hidden rounded-t-2xl bg-white text-left align-bottom shadow-xl transition-all sm:max-w-md sm:rounded-2xl"
      >
        <!-- Header -->
        <div class="shrink-0 border-b border-gray-100 bg-white px-4 py-4 sm:px-6">
          <div class="flex items-start justify-between gap-3">
            <h3
              class="flex items-center gap-2 text-[20px] font-bold leading-[1.2] text-gray-900"
              id="cash-payment-title"
            >
              <DollarSign class="h-6 w-6 text-green-600" />
              {{ currentStep === 'confirm' ? t('payment.cashAllocationTitle') : t('payment.manualTitle') }}
            </h3>
            <button
              type="button"
              @click="handleClose"
              :disabled="isSubmitting"
              class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-full text-gray-500 hover:bg-gray-100 hover:text-gray-700 focus:outline-none focus:ring-2 focus:ring-green-500 disabled:opacity-50"
            >
              <X class="h-5 w-5" />
            </button>
          </div>
        </div>

        <!-- Body -->
        <div class="flex-1 overflow-y-auto px-4 py-4 sm:px-6">
          <!-- Loading -->
          <div v-if="loadingSnapshots" class="flex items-center justify-center py-8">
            <Loader2 class="h-8 w-8 animate-spin text-green-600" />
          </div>

          <!-- No debt -->
          <div
            v-else-if="snapshots.length === 0"
            class="py-8 text-center text-gray-500"
          >
            {{ t('debt.noDebt') }}
          </div>

          <!-- Preview step -->
          <template v-else-if="currentStep === 'preview'">
            <div class="mb-4 rounded-lg bg-green-50 p-3 text-sm text-green-800">
              <strong>{{ memberName }}</strong> — {{ t('debt.totalDebt') }}:
              <strong class="text-green-700">{{ formatCurrency(totalDebt) }}</strong>
            </div>

            <!-- Amount input -->
            <div class="mb-4">
              <label class="mb-1 block text-sm font-bold text-gray-700">
                {{ t('payment.amount') }}
              </label>
              <input
                v-model.number="amount"
                type="number"
                :min="0"
                :max="totalDebt"
                @blur="amount = Math.min(Math.max(0, amount || 0), totalDebt)"
                class="w-full rounded-lg border border-gray-300 px-4 py-3 text-lg font-bold text-gray-900 focus:border-green-500 focus:ring-2 focus:ring-green-500/20"
              />
            </div>

            <!-- Allocation preview -->
            <div class="mb-2 text-sm font-bold text-gray-700">
              {{ t('payment.cashAllocationSummary', { amount: formatCurrency(totalAllocated), count: snapshots.length }) }}
            </div>
            <div class="space-y-2">
              <div
                v-for="s in allocationPreview"
                :key="s.snapshot_id"
                class="flex items-center justify-between rounded-lg border border-gray-200 px-3 py-2 text-sm"
              >
                <div class="min-w-0 flex-1">
                  <div class="truncate font-medium text-gray-900">{{ s.session_title }}</div>
                  <div class="text-xs text-gray-500">
                    {{ new Date(s.start_time).toLocaleDateString() }}
                  </div>
                </div>
                <div class="ml-3 text-right">
                  <div class="font-bold text-gray-900">{{ formatCurrency(s.allocated) }}</div>
                  <div class="text-xs text-gray-500">/ {{ formatCurrency(s.remaining_amount) }}</div>
                </div>
              </div>
            </div>
          </template>

          <!-- Confirm step -->
          <template v-else-if="currentStep === 'confirm'">
            <div class="space-y-4 py-4 text-center">
              <CheckCircle class="mx-auto h-12 w-12 text-green-500" />
              <p class="text-lg font-bold text-gray-900">
                {{ t('payment.cashAllocationSummary', { amount: formatCurrency(totalAllocated), count: snapshots.length }) }}
              </p>
              <p class="text-sm text-gray-500">
                {{ t('payment.cashAllocationTitle') }}
              </p>
            </div>
          </template>
        </div>

        <!-- Footer -->
        <div class="shrink-0 border-t border-gray-100 bg-white px-4 py-4 sm:px-6">
          <template v-if="currentStep === 'preview'">
            <button
              @click="proceedToConfirm"
              :disabled="amount <= 0 || snapshots.length === 0"
              class="flex w-full items-center justify-center gap-2 rounded-xl bg-green-600 px-4 py-3 text-base font-bold text-white shadow-sm transition hover:bg-green-500 focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-offset-2 disabled:opacity-50"
            >
              {{ t('payment.confirmCash') }}
            </button>
          </template>
          <template v-else>
            <div class="flex gap-3">
              <button
                @click="currentStep = 'preview'"
                :disabled="isSubmitting"
                class="flex-1 rounded-xl border border-gray-300 bg-white px-4 py-3 text-base font-bold text-gray-700 transition hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-green-500 disabled:opacity-50"
              >
                <AlertTriangle class="mr-1 inline h-4 w-4" />
                {{ t('common.back') }}
              </button>
              <button
                @click="handleConfirm"
                :disabled="isSubmitting"
                class="flex flex-1 items-center justify-center gap-2 rounded-xl bg-green-600 px-4 py-3 text-base font-bold text-white shadow-sm transition hover:bg-green-500 focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-offset-2 disabled:opacity-50"
              >
                <Loader2 v-if="isSubmitting" class="h-4 w-4 animate-spin" />
                {{ t('payment.confirmCash') }}
              </button>
            </div>
          </template>
        </div>
      </div>
    </div>
  </div>
</template>
