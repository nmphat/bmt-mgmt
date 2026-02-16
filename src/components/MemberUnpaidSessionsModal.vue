<script setup lang="ts">
import { computed } from 'vue'
import { X, Calendar, Banknote, ChevronRight } from 'lucide-vue-next'
import { useLangStore } from '@/stores/lang'
import { format } from 'date-fns'
import { vi, enUS } from 'date-fns/locale'

const props = defineProps<{
  show: boolean
  memberName: string
  snapshots: any[]
}>()

const emit = defineEmits(['close', 'select-snapshot'])
const langStore = useLangStore()
const t = computed(() => langStore.t)
const dateLocale = computed(() => (langStore.currentLang === 'vi' ? vi : enUS))

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
</script>

<template>
  <div
    v-if="show"
    class="fixed inset-0 z-[60] overflow-y-auto"
    aria-labelledby="modal-title"
    role="dialog"
    aria-modal="true"
  >
    <div
      class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0"
    >
      <div
        class="fixed inset-0 bg-gray-500/75 transition-opacity"
        aria-hidden="true"
        @click="emit('close')"
      ></div>

      <span class="hidden sm:inline-block sm:align-middle sm:h-screen" aria-hidden="true"
        >&#8203;</span
      >

      <div
        class="relative z-10 inline-block align-bottom bg-white rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full"
      >
        <div class="bg-white px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
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
              class="group relative bg-white border border-gray-200 rounded-xl p-4 hover:border-indigo-300 hover:shadow-md transition-all cursor-pointer"
              @click="handleSelect(snapshot)"
            >
              <div class="flex justify-between items-center">
                <div class="flex-1 min-w-0 pr-4">
                  <h4 class="text-base font-bold text-gray-900 truncate">
                    {{ snapshot.sessions?.title }}
                  </h4>
                  <div class="flex items-center gap-2 mt-1 text-sm text-gray-500">
                    <Calendar class="w-3.5 h-3.5" />
                    <span>
                      {{
                        format(new Date(snapshot.sessions?.start_time), 'dd/MM/yyyy HH:mm', {
                          locale: dateLocale,
                        })
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
                  <ChevronRight
                    class="w-5 h-5 text-gray-300 group-hover:text-indigo-500 transition"
                  />
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
        </div>

        <div class="bg-gray-50 px-4 py-3 sm:px-6 flex justify-end">
          <button
            @click="emit('close')"
            type="button"
            class="w-full sm:w-auto inline-flex justify-center rounded-md border border-gray-300 shadow-sm px-4 py-2 bg-white text-base font-medium text-gray-700 hover:bg-gray-50 focus:outline-none sm:text-sm"
          >
            {{ t('common.cancel') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
