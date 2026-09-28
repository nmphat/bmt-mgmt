<script setup lang="ts">
import { computed } from 'vue'

// Figma set "Checkbox" (components/checkbox.py). The root is the native checkbox (tests query
// input[type="checkbox"]); other attributes fall through to it.
export type CheckboxSize = '16' | '20' | '24'

const props = withDefaults(
  defineProps<{
    size?: CheckboxSize
    value?: unknown
    disabled?: boolean
  }>(),
  { size: '16', value: undefined, disabled: false },
)

const model = defineModel<boolean | unknown[]>()

const SIZES: Record<CheckboxSize, string> = { '16': 'size-4', '20': 'size-5', '24': 'size-6' }

const checked = computed(() =>
  Array.isArray(model.value) ? model.value.includes(props.value) : !!model.value,
)
const state = computed(
  () => (props.disabled ? 'Disabled ' : '') + (checked.value ? 'Checked' : 'Unchecked'),
)
</script>

<template>
  <input
    v-model="model"
    type="checkbox"
    data-ds="Checkbox"
    :data-ds-size="size"
    :data-ds-state="state"
    :value="value"
    :disabled="disabled"
    :class="[
      'shrink-0 cursor-pointer rounded-sm border-line-input accent-surface-brand focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-line-focus focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50',
      SIZES[size],
    ]"
  />
</template>
