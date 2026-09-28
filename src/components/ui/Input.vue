<script setup lang="ts">
import { computed } from 'vue'

// Figma set "Input" (components/input.py). Native attributes (id, type, required, min, step, placeholder,
// autocomplete, aria-*) fall through to the <input>; data-ds stays on the root.
export type InputSize = 'Small' | 'Default' | 'Large'

defineOptions({ inheritAttrs: false })

const props = withDefaults(
  defineProps<{
    size?: InputSize
    suffix?: string
    disabled?: boolean
  }>(),
  { size: 'Small', suffix: undefined, disabled: false },
)

const model = defineModel<string | number | null>()

const SIZES: Record<InputSize, string> = {
  Small: 'h-control-sm px-3',
  Default: 'h-control-md px-3',
  Large: 'h-control-lg px-4',
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
    data-ds="Input"
    :data-ds-size="size"
    :data-ds-content="content"
    :data-ds-state="state"
    class="relative"
  >
    <input
      v-model="model"
      v-bind="$attrs"
      :disabled="disabled"
      :class="[
        'block w-full rounded-control border border-line-input bg-surface-card text-base text-fg-primary shadow-sm placeholder:text-fg-muted focus:border-line-focus focus:outline-none focus-visible:ring-1 focus-visible:ring-line-focus disabled:cursor-not-allowed disabled:opacity-50',
        SIZES[size],
        suffix && 'pr-10',
      ]"
    />
    <span
      v-if="suffix"
      class="pointer-events-none absolute inset-y-0 right-3 flex items-center text-base text-fg-muted"
      >{{ suffix }}</span
    >
  </div>
</template>
