<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { X, Calendar, Banknote, ChevronRight } from 'lucide-vue-next'
import { useLangStore } from '@/stores/lang'
import { formatDisplayDateTime } from '@/utils/dateFormatters'

const props = defineProps<{
  show: boolean
  memberName: string
  snapshots: any[]
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'select-snapshot', snapshot: any): void
  (
    e: 'batch-manual-payment',
    payload: { snapshotIds: string[]; amount: number; note: string },
  ): void
}>()
const langStore = useLangStore()
const t = computed(() => langStore.t)

const selectedSnapshotIds = ref<string[]>([])
const batchNote = ref('')

const selectedSnapshots = computed(() =>
  props.snapshots.filter((s) => selectedSnapshotIds.value.includes(s.id)),
)

const selectedRemainingTotal = computed(() =>
  selectedSnapshots.value.reduce((sum, s) => sum + (s.final_amount - s.paid_amount), 0),
)

const computedBatchAmount = computed(() => selectedRemainingTotal.value)

const canSubmitBatch = computed(
  () => selectedSnapshotIds.value.length > 0 && computedBatchAmount.value > 0,
)

watch(
  () => props.show,
  (show) => {
    if (!show) return
    // Default to all unpaid sessions of this member when opening the modal.
    selectedSnapshotIds.value = props.snapshots.map((s) => s.id)
    batchNote.value = t.value('payment.cash')
  },
)

const formatCurrency = (value: number) => {
  return new Intl.NumberFormat(langStore.currentLang === 'vi' ? 'vi-VN' : 'en-US', {
    style: 'currency',
    currency: 'VND',
    maximumFractionDigits: 0,
  }).format(value)
}

function handleSelect(snapshot: any) {
  emit('select-snapshot', snapshot)
}

function toggleSnapshot(snapshotId: string) {
  const idx = selectedSnapshotIds.value.indexOf(snapshotId)
  if (idx === -1) {
    selectedSnapshotIds.value.push(snapshotId)
  } else {
    selectedSnapshotIds.value.splice(idx, 1)
  }
}

function handleBatchManualPayment() {
  if (!canSubmitBatch.value) return
  emit('batch-manual-payment', {
    snapshotIds: [...selectedSnapshotIds.value],
    amount: computedBatchAmount.value,
    note: batchNote.value || t.value('payment.cash'),
  })
}
</script>

<template>
  <div
    v-if="show"
    class="fixed inset-0 z-[60]"
    aria-labelledby="modal-title"
    role="dialog"
    aria-modal="true"
  >
    <div class="flex min-h-screen items-end sm:items-center justify-center sm:p-4">
      <div
        class="fixed inset-0 bg-gray-900/60 backdrop-blur-sm transition-opacity"
        aria-hidden="true"
        @click="emit('close')"
      ></div>

      <div
        class="relative z-10 w-full sm:max-w-lg bg-white rounded-t-2xl sm:rounded-2xl text-left shadow-xl transform transition-all max-h-[85vh] flex flex-col"
      >
        <div class="px-5 pt-5 pb-4 sm:p-6 sm:pb-4 flex-1 overflow-y-auto">
          <!-- Handle bar -->
          <div class="flex justify-center mb-3 sm:hidden">
            <div class="w-10 h-1 rounded-full bg-gray-300" />
          </div>
          <div class="flex justify-between items-start mb-4">
            <div>
              <h3 class="text-xl font-bold text-gray-900" id="modal-title">
                {{ t('debt.unpaidSessions') }}
              </h3>
              <p class="text-sm text-gray-500 uppercase font-medium">{{ memberName }}</p>
            </div>
            <button
              @click="emit('close')"
              class="text-gray-400 hover:text-gray-600 focus:outline-none"
            >
              <X class="w-6 h-6" />
            </button>
          </div>

          <div class="mt-4 space-y-3">
            <div
              v-for="snapshot in snapshots"
              :key="snapshot.id"
              class="group relative bg-white border border-gray-200 rounded-xl p-4 hover:border-indigo-300 hover:shadow-md transition-all"
            >
              <div class="flex justify-between items-center">
                <div class="mr-3 flex-shrink-0" @click.stop>
                  <input
                    type="checkbox"
                    :checked="selectedSnapshotIds.includes(snapshot.id)"
                    @change="toggleSnapshot(snapshot.id)"
                    class="h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-500 cursor-pointer"
                  />
                </div>
                <div class="flex-1 min-w-0 pr-4">
                  <h4 class="text-base font-bold text-gray-900 truncate">
                    {{ snapshot.sessions?.title }}
                  </h4>
                  <div class="flex items-center gap-2 mt-1 text-sm text-gray-500">
                    <Calendar class="w-3.5 h-3.5" />
                    <span>
                      {{
                        formatDisplayDateTime(snapshot.sessions?.start_time, langStore.currentLang)
                      }}
                    </span>
                  </div>
                </div>
                <div class="text-right flex items-center gap-3">
                  <div>
                    <div class="text-lg font-black text-red-600 leading-none">
                      {{ formatCurrency(snapshot.final_amount - snapshot.paid_amount) }}
                    </div>
                    <div class="text-[10px] text-gray-400 uppercase tracking-tighter mt-1">
                      {{ t('debt.remaining') }}
                    </div>
                  </div>
                  <button
                    @click="handleSelect(snapshot)"
                    class="p-1 rounded hover:bg-indigo-50"
                    :title="t('payment.cashPay')"
                  >
                    <ChevronRight
                      class="w-5 h-5 text-gray-300 group-hover:text-indigo-500 transition"
                    />
                  </button>
                </div>
              </div>

              <!-- Selection indicator/overlay -->
              <div class="mt-3 flex justify-end">
                <span
                  class="inline-flex items-center gap-1.5 px-3 py-1 bg-green-50 text-green-700 rounded-full text-xs font-bold border border-green-100 group-hover:bg-green-600 group-hover:text-white transition"
                >
                  <Banknote class="w-3.5 h-3.5" />
                  {{ t('payment.cashPay') }}
                </span>
              </div>
            </div>
          </div>

          <div
            v-if="selectedSnapshotIds.length > 0"
            class="mt-5 rounded-xl border border-indigo-100 bg-indigo-50/60 p-4 space-y-3"
          >
            <div class="flex items-center justify-between">
              <span class="text-sm font-semibold text-indigo-900">
                {{ t('payment.batchSelectedCount', { count: selectedSnapshotIds.length }) }}
              </span>
              <span class="text-sm font-bold text-indigo-700">
                {{ formatCurrency(selectedRemainingTotal) }}
              </span>
            </div>

            <div>
              <label class="block text-xs font-semibold text-gray-600 mb-1">{{
                t('payment.batchAmountCollected')
              }}</label>
              <input
                :value="computedBatchAmount"
                type="number"
                readonly
                class="w-full rounded-lg border border-gray-300 bg-gray-100 px-3 py-2 text-sm font-semibold text-gray-700"
              />
            </div>

            <div>
              <label class="block text-xs font-semibold text-gray-600 mb-1">{{
                t('payment.note')
              }}</label>
              <input
                v-model="batchNote"
                type="text"
                class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
              />
            </div>

            <button
              type="button"
              :disabled="!canSubmitBatch"
              @click="handleBatchManualPayment"
              class="w-full inline-flex justify-center items-center rounded-xl border border-transparent shadow-sm px-4 py-2.5 bg-green-600 text-sm font-bold text-white hover:bg-green-700 disabled:opacity-50"
            >
              <Banknote class="w-4 h-4 mr-2" />
              {{ t('payment.confirmBatchPayment') }}
            </button>
          </div>
        </div>

        <div
          class="bg-gray-50 px-5 py-4 sm:px-6 flex justify-end"
          style="padding-bottom: calc(env(safe-area-inset-bottom) + 1rem)"
        >
          <button
            @click="emit('close')"
            type="button"
            class="w-full sm:w-auto inline-flex justify-center rounded-xl border border-gray-300 shadow-sm px-4 py-2.5 bg-white text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none"
          >
            {{ t('common.cancel') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
