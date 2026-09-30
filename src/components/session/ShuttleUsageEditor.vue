<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { useShuttleTypes } from '@/composables/useShuttleTypes'
import { supabase } from '@/lib/supabase'
import { useLangStore } from '@/stores/lang'
import { useToast } from 'vue-toastification'
import { shuttleTotal } from '@/utils/courtCost'
import { formatCurrency } from '@/utils/formatters'
import type { ShuttleUsageEntry } from '@/types'
import { Plus, Minus, Save, X } from 'lucide-vue-next'
import { RouterLink } from 'vue-router'
import Button from '@/components/ui/Button.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import FieldMessage from '@/components/ui/FieldMessage.vue'
import FormField from '@/components/ui/FormField.vue'
import IconButton from '@/components/ui/IconButton.vue'
import Input from '@/components/ui/Input.vue'
import Select from '@/components/ui/Select.vue'

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

const loadError = ref(false)

// SessionDetailView mounts this editor before its own session fetch has
// filled in shuttle_usage, then patches the prop in a few round-trips later
// (and again on every full refetch, e.g. from realtime events). Sync from
// the prop until the admin edits a row; once dirty, local rows are the
// source of truth so a refetch can never overwrite an in-progress edit.
const dirty = ref(false)

watch(
  () => props.usage,
  (usage) => {
    if (dirty.value) return
    rows.value = usage.map((u) => ({ ...u }))
  },
  { immediate: true },
)

onMounted(async () => {
  try {
    await fetchTypes()
  } catch {
    loadError.value = true
  }
})

const total = computed(() => shuttleTotal(rows.value))

function addRow() {
  const first = activeTypes.value[0]
  if (!first) return
  dirty.value = true
  rows.value.push({
    type_id: first.id,
    name: first.name,
    tube_price: first.tube_price,
    per_tube: first.per_tube,
    used: 0,
  })
}

function removeRow(index: number) {
  dirty.value = true
  rows.value.splice(index, 1)
}

function changeType(index: number, typeId: string) {
  const type = activeTypes.value.find((t) => t.id === typeId)
  if (!type) return
  const row = rows.value[index]
  if (!row) return
  dirty.value = true
  row.type_id = type.id
  row.name = type.name
  row.tube_price = type.tube_price
  row.per_tube = type.per_tube
}

function increment(index: number) {
  const row = rows.value[index]
  if (row) {
    dirty.value = true
    row.used = (Number(row.used) || 0) + 1
  }
}

function decrement(index: number) {
  const row = rows.value[index]
  if (row) {
    dirty.value = true
    row.used = Math.max(0, (Number(row.used) || 0) - 1)
  }
}

function setUsed(index: number, value: number) {
  const row = rows.value[index]
  if (!row) return
  dirty.value = true
  row.used = Math.max(0, value || 0)
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
    emit(
      'saved',
      rows.value.map((r) => ({ ...r })),
    )
  } catch (err: any) {
    toast.error(err.message || t.value('shuttle.saveError'))
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="rounded-xl border border-line-divider bg-surface-card p-4 shadow-sm sm:p-6">
    <h3 class="mb-4 text-xl font-bold text-fg-primary">
      {{ t('shuttle.title') }}
    </h3>
    <FieldMessage v-if="loadError" tone="Error">{{ t('shuttle.loadError') }}</FieldMessage>
    <template v-else>
      <EmptyState v-if="rows.length === 0" variant="Plain" align="Center" size="Small">
        {{ t('shuttle.empty') }}
      </EmptyState>

      <p
        v-if="!disabled && activeTypes.length === 0"
        class="mt-2 text-sm text-status-warning-strong"
      >
        {{ t('shuttle.noActiveTypes') }}
        <RouterLink
          to="/settings"
          class="rounded-sm font-bold underline underline-offset-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-line-focus focus-visible:ring-offset-2"
        >
          {{ t('shuttle.goToSettings') }}
        </RouterLink>
      </p>

      <div v-else class="space-y-3">
        <div
          v-for="(row, i) in rows"
          :key="i"
          data-ds="Shuttle Usage Row"
          class="flex flex-col gap-2 rounded-xl border border-line-divider bg-surface-subtle p-3"
        >
          <div class="flex flex-col gap-2 sm:flex-row sm:items-end">
            <FormField
              :label="t('shuttle.type')"
              control="Select"
              label-style="Muted"
              class="min-w-0 flex-1"
              v-slot="{ controlProps }"
            >
              <Select
                v-bind="controlProps"
                :model-value="row.type_id"
                :disabled="disabled"
                size="Default"
                @change="changeType(i, ($event.target as HTMLSelectElement).value)"
              >
                <option v-for="type in activeTypes" :key="type.id" :value="type.id">
                  {{ type.name }} ({{ formatCurrency(type.tube_price) }}/{{ type.per_tube }})
                </option>
              </Select>
            </FormField>
            <div
              data-ds="Stepper"
              :data-ds-state="disabled ? 'Disabled' : row.used <= 0 ? 'Min' : 'Default'"
              class="flex items-center gap-1"
            >
              <IconButton
                :icon="Minus"
                :label="t('shuttle.decrease')"
                :disabled="disabled || row.used <= 0"
                :data-testid="`dec-${i}`"
                size="Default"
                shape="Square"
                variant="Outline"
                @click="decrement(i)"
              />
              <div class="w-16">
                <!-- :value falls through so the native input keeps its value attribute; .capture reads the raw
                     value before Input's inner v-model casts it to a number on change (as the native input did) -->
                <Input
                  :model-value="row.used"
                  :value="row.used"
                  :disabled="disabled"
                  type="number"
                  min="0"
                  :data-testid="`used-${i}`"
                  :aria-label="t('shuttle.used')"
                  size="Default"
                  @change.capture="setUsed(i, Number(($event.target as HTMLInputElement).value))"
                />
              </div>
              <IconButton
                :icon="Plus"
                :label="t('shuttle.increase')"
                :disabled="disabled"
                :data-testid="`inc-${i}`"
                size="Default"
                shape="Square"
                variant="Outline"
                @click="increment(i)"
              />
            </div>
            <div
              class="text-sm font-bold text-fg-primary sm:flex sm:h-11 sm:w-28 sm:items-center sm:justify-end"
            >
              {{ formatCurrency(shuttleTotal([row])) }}
            </div>
            <IconButton
              v-if="!disabled"
              :icon="X"
              :label="t('common.remove')"
              size="Default"
              shape="Square"
              variant="Ghost"
              @click="removeRow(i)"
            />
          </div>
        </div>
      </div>

      <div class="mt-4 flex items-center justify-between">
        <Button
          v-if="!disabled"
          :disabled="activeTypes.length === 0"
          :title="activeTypes.length === 0 ? t('shuttle.noActiveTypes') : undefined"
          size="Default"
          variant="Outline Brand"
          :leading-icon="Plus"
          data-testid="add-row"
          @click="addRow"
        >
          {{ t('shuttle.addType') }}
        </Button>
        <div class="text-right">
          <span class="text-sm text-fg-muted">{{ t('shuttle.total') }}:</span>
          <span class="ml-2 text-lg font-bold text-fg-primary" data-testid="shuttle-total">
            {{ formatCurrency(total) }}
          </span>
        </div>
      </div>

      <div v-if="!disabled" class="mt-4 flex justify-end border-t border-line-divider pt-4">
        <Button
          size="Default"
          variant="Primary"
          :leading-icon="Save"
          :loading="saving"
          :disabled="saving"
          data-testid="save"
          @click="handleSave"
        >
          {{ t('common.save') }}
        </Button>
      </div>
    </template>
  </div>
</template>
