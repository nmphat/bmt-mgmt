<script setup lang="ts">
import { computed } from 'vue'
import { ChevronDown } from 'lucide-vue-next'

// Figma set "Select" (components/select.py). Native attributes fall through to the <select>; data-ds stays on the
// root. Default slot = the <option>s.
export type SelectSize = 'Small' | 'Default' | 'Large'

defineOptions({ inheritAttrs: false })

const props = withDefaults(
  defineProps<{
    size?: SelectSize
    disabled?: boolean
  }>(),
  { size: 'Small', disabled: false },
)

const model = defineModel<unknown>()

const SIZES: Record<SelectSize, string> = {
  Small: 'h-control-sm pl-3 pr-9',
  Default: 'h-control-md pl-3 pr-10',
  Large: 'h-control-lg pl-4 pr-11',
}
const CHEVRON: Record<SelectSize, string> = {
  Small: 'right-3 size-4',
  Default: 'right-3 size-5',
  Large: 'right-4 size-5',
}

const content = computed(() =>
  model.value === undefined || model.value === null || model.value === ''
    ? 'Placeholder'
    : 'Filled',
)
const state = computed(() => (props.disabled ? 'Disabled' : 'Default'))
</script>

<template>
  <div
    data-ds="Select"
    :data-ds-size="size"
    :data-ds-content="content"
    :data-ds-state="state"
    class="relative"
  >
    <select
      v-model="model"
      v-bind="$attrs"
      :disabled="disabled"
      :class="[
        'block w-full appearance-none rounded-control border border-line-input bg-surface-card text-base shadow-sm focus:border-line-focus focus:outline-none focus-visible:ring-1 focus-visible:ring-line-focus disabled:cursor-not-allowed disabled:opacity-50',
        SIZES[size],
        content === 'Filled' ? 'text-fg-primary' : 'text-fg-muted',
      ]"
    >
      <slot />
    </select>
    <ChevronDown
      :class="[
        'pointer-events-none absolute top-1/2 -translate-y-1/2 text-fg-muted',
        CHEVRON[size],
      ]"
    />
  </div>
</template>
