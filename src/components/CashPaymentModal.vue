<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import { useToast } from 'vue-toastification'
import { useLangStore } from '@/stores/lang'
import { DollarSign, CircleCheckBig, ArrowLeft } from 'lucide-vue-next'
import ModalPanel from '@/components/ui/ModalPanel.vue'
import ModalHeader from '@/components/ui/ModalHeader.vue'
import ModalFooter from '@/components/ui/ModalFooter.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import FormField from '@/components/ui/FormField.vue'
import Alert from '@/components/ui/Alert.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import Spinner from '@/components/ui/Spinner.vue'

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
  { immediate: true },
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

      const freshRemaining = (freshSnapshot.final_amount || 0) - (freshSnapshot.paid_amount || 0)
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
      toast.success(t.value('payment.cashPaymentSuccess', { count: paidSnapshotIds.length }))
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
        data-ds="Modal Scrim"
        data-ds-style="Default"
        class="fixed inset-0 bg-surface-scrim/75 transition-opacity"
        aria-hidden="true"
        @click="handleClose"
      ></div>

      <!-- Modal -->
      <ModalPanel width="md">
        <template #header>
          <ModalHeader
            title-id="cash-payment-title"
            :title="
              currentStep === 'confirm'
                ? t('payment.cashAllocationTitle')
                : t('payment.manualTitle')
            "
            :icon="DollarSign"
            :close="isSubmitting ? 'Disabled' : 'Default'"
            :close-label="t('common.cancel')"
            @close="handleClose"
          />
        </template>

        <!-- Body -->
        <div data-ds="Cash Payment Body" class="py-4">
          <!-- Loading -->
          <div v-if="loadingSnapshots" class="flex justify-center py-8">
            <Spinner size="32" tone="Success" />
          </div>

          <!-- No debt -->
          <EmptyState v-else-if="snapshots.length === 0" variant="Plain">
            {{ t('debt.noDebt') }}
          </EmptyState>

          <!-- Preview step -->
          <div v-else-if="currentStep === 'preview'" class="flex flex-col gap-4">
            <Alert tone="Success">
              <p>
                <strong>{{ memberName }}</strong> — {{ t('debt.totalDebt') }}:
                <strong>{{ formatCurrency(totalDebt) }}</strong>
              </p>
            </Alert>

            <!-- Amount input -->
            <FormField :label="t('payment.amount')">
              <template #default="{ controlProps }">
                <Input
                  v-bind="controlProps"
                  v-model.number="amount"
                  size="Default"
                  type="number"
                  :min="0"
                  :max="totalDebt"
                  @blur="amount = Math.min(Math.max(0, amount || 0), totalDebt)"
                />
              </template>
            </FormField>

            <!-- Allocation preview -->
            <div class="flex flex-col gap-2">
              <div class="text-sm font-bold text-fg-secondary">
                {{
                  t('payment.cashAllocationSummary', {
                    amount: formatCurrency(totalAllocated),
                    count: snapshots.length,
                  })
                }}
              </div>
              <div
                v-for="s in allocationPreview"
                :key="s.snapshot_id"
                data-ds="Amount List Item"
                data-ds-style="Allocation"
                class="flex justify-between gap-3 rounded-lg border border-line-divider px-3 py-2"
              >
                <div class="min-w-0 flex-1">
                  <div class="truncate text-sm font-medium text-fg-primary">
                    {{ s.session_title }}
                  </div>
                  <div class="text-xs text-fg-muted">
                    {{ new Date(s.start_time).toLocaleDateString() }}
                  </div>
                </div>
                <div class="text-right">
                  <div class="text-sm font-bold text-fg-primary">
                    {{ formatCurrency(s.allocated) }}
                  </div>
                  <div class="text-xs text-fg-muted">
                    / {{ formatCurrency(s.remaining_amount) }}
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Confirm step -->
          <div
            v-else-if="currentStep === 'confirm'"
            data-ds="Result State"
            data-ds-style="Plain"
            class="flex flex-col items-center gap-4 py-4 text-center"
          >
            <CircleCheckBig class="size-12 text-fg-success-soft" />
            <p class="text-lg font-bold text-fg-primary">
              {{
                t('payment.cashAllocationSummary', {
                  amount: formatCurrency(totalAllocated),
                  count: snapshots.length,
                })
              }}
            </p>
            <p class="text-sm text-fg-muted">
              {{ t('payment.cashAllocationTitle') }}
            </p>
          </div>
        </div>

        <!-- Footer -->
        <template #footer>
          <ModalFooter v-if="currentStep === 'preview'" background="White" buttons="One">
            <template #primary>
              <Button
                size="Default"
                variant="Success"
                :disabled="amount <= 0 || snapshots.length === 0"
                @click="proceedToConfirm"
              >
                {{ t('payment.confirmCash') }}
              </Button>
            </template>
          </ModalFooter>
          <ModalFooter v-else background="White" buttons="Two">
            <template #secondary>
              <Button
                size="Default"
                variant="Secondary"
                :leading-icon="ArrowLeft"
                :disabled="isSubmitting"
                @click="currentStep = 'preview'"
              >
                {{ t('common.back') }}
              </Button>
            </template>
            <template #primary>
              <Button
                size="Default"
                variant="Success"
                :loading="isSubmitting"
                :disabled="isSubmitting"
                @click="handleConfirm"
              >
                {{ t('payment.confirmCash') }}
              </Button>
            </template>
          </ModalFooter>
        </template>
      </ModalPanel>
    </div>
  </div>
</template>
