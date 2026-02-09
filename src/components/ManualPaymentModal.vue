<script setup lang="ts">
import { ref, watch } from 'vue'
import { X, Loader2, DollarSign, CheckCircle, Info } from 'lucide-vue-next'
import { supabase } from '@/lib/supabase'
import type { CostSnapshot } from '@/types'
import { useToast } from 'vue-toastification'

const props = defineProps<{
  show: boolean
  snapshot: CostSnapshot | null
  memberName: string
}>()

const emit = defineEmits(['close', 'success'])
const toast = useToast()

const amount = ref(0)
const note = ref('Tiền mặt')
const isSubmitting = ref(false)

// Reset form when snapshot changes
watch(
  () => props.snapshot,
  (newVal) => {
    if (newVal) {
      amount.value = newVal.final_amount - newVal.paid_amount
      note.value = 'Tiền mặt'
    }
  },
  { immediate: true },
)

const formatCurrency = (value: number) => {
  return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(value)
}

async function handleConfirm() {
  if (!props.snapshot) return
  if (amount.value <= 0) {
    toast.error('Số tiền phải lớn hơn 0')
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

    toast.success('Ghi nhận thanh toán tiền mặt thành công!')
    emit('success')
    emit('close')
  } catch (error: any) {
    console.error('Error adding manual payment:', error)
    toast.error('Lỗi khi ghi nhận: ' + error.message)
  } finally {
    isSubmitting.value = false
  }
}
</script>

<template>
  <div
    v-if="show"
    class="fixed inset-0 z-50 overflow-y-auto"
    aria-labelledby="modal-title"
    role="dialog"
    aria-modal="true"
  >
    <div
      class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0"
    >
      <!-- Background overlay -->
      <div
        class="fixed inset-0 bg-gray-500/75 transition-opacity"
        aria-hidden="true"
        @click="emit('close')"
      ></div>

      <!-- Modal panel -->
      <span class="hidden sm:inline-block sm:align-middle sm:h-screen" aria-hidden="true"
        >&#8203;</span
      >
      <div
        class="relative z-10 inline-block align-bottom bg-white rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-md sm:w-full"
      >
        <div class="bg-white px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
          <div class="flex justify-between items-start mb-4">
            <h3 class="text-xl font-bold text-gray-900 flex items-center gap-2" id="modal-title">
              <DollarSign class="w-6 h-6 text-green-600" />
              Thu tiền mặt
            </h3>
            <button
              @click="emit('close')"
              class="text-gray-400 hover:text-gray-600 focus:outline-none"
            >
              <X class="w-6 h-6" />
            </button>
          </div>

          <div v-if="snapshot" class="space-y-4">
            <div class="p-3 bg-blue-50 rounded-lg border border-blue-100 flex items-start gap-3">
              <Info class="w-5 h-5 text-blue-600 shrink-0 mt-0.5" />
              <div class="text-sm text-blue-800">
                Ghi nhận số tiền mặt nhận được từ <strong>{{ memberName }}</strong
                >. Hệ thống sẽ cập nhật trạng thái đã đóng ngay lập tức.
              </div>
            </div>

            <div class="space-y-4 pt-2">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Thành viên</label>
                <div
                  class="px-3 py-2 bg-gray-100 rounded-md text-gray-900 font-semibold border border-gray-200 uppercase"
                >
                  {{ memberName }}
                </div>
              </div>

              <div>
                <label for="amount" class="block text-sm font-medium text-gray-700 mb-1"
                  >Số tiền thu (₫)</label
                >
                <div class="relative rounded-md shadow-sm">
                  <input
                    id="amount"
                    v-model.number="amount"
                    type="number"
                    step="1000"
                    min="0"
                    class="block w-full rounded-md border-gray-300 pl-3 pr-12 focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border py-2 font-bold text-indigo-700 text-lg"
                    placeholder="Nhập số tiền..."
                    @keyup.enter="handleConfirm"
                  />
                  <div
                    class="absolute inset-y-0 right-0 pr-3 flex items-center pointer-events-none"
                  >
                    <span class="text-gray-500 sm:text-sm">₫</span>
                  </div>
                </div>
                <p class="mt-1 text-xs text-gray-500">
                  Còn nợ:
                  <span class="font-medium">{{
                    formatCurrency(snapshot.final_amount - snapshot.paid_amount)
                  }}</span>
                </p>
              </div>

              <div>
                <label for="note" class="block text-sm font-medium text-gray-700 mb-1"
                  >Ghi chú</label
                >
                <input
                  id="note"
                  v-model="note"
                  type="text"
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
                  placeholder="Ghi chú thêm..."
                />
              </div>
            </div>
          </div>
        </div>

        <div class="bg-gray-50 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
          <button
            @click="handleConfirm"
            :disabled="isSubmitting"
            type="button"
            class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-green-600 text-base font-bold text-white hover:bg-green-700 focus:outline-none sm:ml-3 sm:w-auto sm:text-sm items-center disabled:opacity-50"
          >
            <Loader2 v-if="isSubmitting" class="w-4 h-4 mr-2 animate-spin" />
            <CheckCircle v-else class="w-4 h-4 mr-2" />
            Xác nhận đã nhận
          </button>
          <button
            @click="emit('close')"
            :disabled="isSubmitting"
            type="button"
            class="mt-3 w-full inline-flex justify-center rounded-md border border-gray-300 shadow-sm px-4 py-2 bg-white text-base font-medium text-gray-700 hover:bg-gray-50 focus:outline-none sm:mt-0 sm:ml-3 sm:w-auto sm:text-sm"
          >
            Hủy
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
