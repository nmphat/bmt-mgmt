<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useShuttleTypes } from '@/composables/useShuttleTypes'
import { supabase } from '@/lib/supabase'
import { useLangStore } from '@/stores/lang'
import { useToast } from 'vue-toastification'
import { shuttleTotal } from '@/utils/courtCost'
import { formatCurrency } from '@/utils/formatters'
import type { ShuttleUsageEntry } from '@/types'
import { Plus, Minus, Save, Loader2 } from 'lucide-vue-next'

const props = defineProps<{
  sessionId: string
  usage: ShuttleUsageEntry[]
  disabled?: boolean
}>()

const emit = defineEmits<{
  saved: [ShuttleUsageEntry[]]
}>()

const langStore = useLangStore()
const toast = useToast()
const t = computed(() => langStore.t)

const { activeTypes, fetchTypes } = useShuttleTypes()

const rows = ref<ShuttleUsageEntry[]>([])
const saving = ref(false)

onMounted(async () => {
  await fetchTypes()
  rows.value = props.usage.map((u) => ({ ...u }))
})

const total = computed(() => shuttleTotal(rows.value))

function addRow() {
  const first = activeTypes.value[0]
  if (!first) return
  rows.value.push({
    type_id: first.id,
    name: first.name,
    tube_price: first.tube_price,
    per_tube: first.per_tube,
    used: 0,
  })
}

function removeRow(index: number) {
  rows.value.splice(index, 1)
}

function changeType(index: number, typeId: string) {
  const type = activeTypes.value.find((t) => t.id === typeId)
  if (!type) return
  const row = rows.value[index]
  if (!row) return
  row.type_id = type.id
  row.name = type.name
  row.tube_price = type.tube_price
  row.per_tube = type.per_tube
}

function increment(index: number) {
  const row = rows.value[index]
  if (row) row.used++
}

function decrement(index: number) {
  const row = rows.value[index]
  if (row && row.used > 0) row.used--
}

async function handleSave() {
  saving.value = true
  try {
    const { error } = await supabase.rpc('set_session_shuttle_usage', {
      p_session_id: props.sessionId,
      p_usage: rows.value,
    })
    if (error) throw error
    toast.success(t.value('shuttle.saved'))
    emit('saved', rows.value.map((r) => ({ ...r })))
  } catch (err: any) {
    toast.error(err.message || 'Error saving shuttle usage')
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm sm:p-6">
    <h3 class="mb-4 text-[20px] font-bold leading-[1.2] text-gray-900">
      {{ t('shuttle.title') }}
    </h3>

    <div v-if="rows.length === 0" class="py-4 text-center text-sm text-gray-500">
      {{ t('shuttle.empty') }}
    </div>

    <div v-else class="space-y-3">
      <div
        v-for="(row, i) in rows"
        :key="i"
        class="flex flex-col gap-2 rounded-xl border border-gray-200 bg-gray-50 p-3 sm:flex-row sm:items-end"
      >
        <div class="min-w-0 flex-1">
          <label class="mb-1 block text-xs text-gray-500">{{ t('shuttle.type') }}</label>
          <select
            :value="row.type_id"
            :disabled="disabled"
            class="block min-h-11 w-full rounded-xl border border-gray-300 px-2 text-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:opacity-50"
            @change="changeType(i, ($event.target as HTMLSelectElement).value)"
          >
            <option v-for="type in activeTypes" :key="type.id" :value="type.id">
              {{ type.name }} ({{ formatCurrency(type.tube_price) }}/{{ type.per_tube }})
            </option>
          </select>
        </div>
        <div class="flex items-center gap-1">
          <button
            type="button"
            :disabled="disabled || row.used <= 0"
            class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-xl border border-gray-300 text-gray-600 transition hover:bg-gray-100 disabled:opacity-30"
            :data-testid="`dec-${i}`"
            @click="decrement(i)"
          >
            <Minus class="h-4 w-4" />
          </button>
          <input
            :value="row.used"
            :disabled="disabled"
            type="number"
            min="0"
            :data-testid="`used-${i}`"
            class="block w-16 min-h-11 rounded-xl border border-gray-300 px-2 text-center text-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:opacity-50"
            @change="
              rows[i]!.used = Math.max(0, Number(($event.target as HTMLInputElement).value))
            "
          />
          <button
            type="button"
            :disabled="disabled"
            class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-xl border border-gray-300 text-gray-600 transition hover:bg-gray-100 disabled:opacity-30"
            :data-testid="`inc-${i}`"
            @click="increment(i)"
          >
            <Plus class="h-4 w-4" />
          </button>
        </div>
        <div class="text-sm font-bold text-gray-700 sm:w-28 sm:text-right">
          {{ formatCurrency(shuttleTotal([row])) }}
        </div>
        <button
          v-if="!disabled"
          type="button"
          class="inline-flex min-h-11 items-center justify-center rounded-xl px-2 text-gray-400 transition hover:text-red-500"
          @click="removeRow(i)"
        >
          &times;
        </button>
      </div>
    </div>

    <div class="mt-4 flex items-center justify-between">
      <button
        v-if="!disabled"
        type="button"
        class="inline-flex min-h-11 items-center gap-1 rounded-xl border border-indigo-200 px-3 text-sm font-bold text-indigo-600 transition hover:bg-indigo-50"
        data-testid="add-row"
        @click="addRow"
      >
        <Plus class="h-4 w-4" />
        {{ t('shuttle.type') }}
      </button>
      <div class="text-right">
        <span class="text-sm text-gray-500">{{ t('shuttle.total') }}:</span>
        <span class="ml-2 text-lg font-bold text-gray-900" data-testid="shuttle-total">
          {{ formatCurrency(total) }}
        </span>
      </div>
    </div>

    <div v-if="!disabled" class="mt-4 flex justify-end border-t border-gray-100 pt-4">
      <button
        type="button"
        class="flex min-h-11 items-center rounded-xl bg-indigo-600 px-4 py-2 text-sm font-bold text-white transition hover:bg-indigo-700 disabled:opacity-50"
        data-testid="save"
        :disabled="saving"
        @click="handleSave"
      >
        <Save v-if="!saving" class="w-4 h-4 mr-2" />
        <Loader2 v-else class="w-4 h-4 mr-2 animate-spin" />
        {{ t('common.save') }}
      </button>
    </div>
  </div>
</template>
