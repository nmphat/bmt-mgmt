<script setup lang="ts">
import { computed } from 'vue'
import { QrCode, Loader2 } from 'lucide-vue-next'
import { useLangStore } from '@/stores/lang'

const props = defineProps<{
  selectedCount: number
  totalAmount: number
  isCreating: boolean
}>()

defineEmits<{ create: [] }>()

const langStore = useLangStore()
const t = computed(() => langStore.t)

const currencyFormatter = new Intl.NumberFormat('vi-VN', {
  style: 'currency',
  currency: 'VND',
  maximumFractionDigits: 0,
})
const formatCurrency = (v: number) => currencyFormatter.format(v)
</script>

<template>
  <Transition
    enter-active-class="transition duration-300 ease-out"
    enter-from-class="transform translate-y-full opacity-0"
    enter-to-class="transform translate-y-0 opacity-100"
    leave-active-class="transition duration-200 ease-in"
    leave-from-class="transform translate-y-0 opacity-100"
    leave-to-class="transform translate-y-full opacity-0"
  >
    <div
      v-if="selectedCount > 0"
      class="fixed bottom-6 left-1/2 -translate-x-1/2 z-50 w-[calc(100%-2rem)] max-w-2xl"
    >
      <div
        class="bg-indigo-600 text-white rounded-2xl shadow-2xl p-4 flex items-center justify-between border border-indigo-500/50"
      >
        <div class="flex flex-col">
          <span class="text-sm font-medium opacity-90">
            {{ t('session.payGroup', { count: selectedCount }) }}
          </span>
          <span class="text-xl font-extrabold">
            {{ t('session.totalSelected', { amount: formatCurrency(totalAmount) }) }}
          </span>
        </div>
        <button
          @click="$emit('create')"
          :disabled="isCreating"
          class="flex items-center px-6 py-2.5 bg-white text-indigo-600 rounded-xl font-bold hover:bg-indigo-50 transition active:scale-95 disabled:opacity-50 shadow-sm"
        >
          <Loader2 v-if="isCreating" class="w-5 h-5 mr-2 animate-spin" />
          <QrCode v-else class="w-5 h-5 mr-2" />
          {{ t('session.groupPayButton') }}
        </button>
      </div>
    </div>
  </Transition>
</template>
