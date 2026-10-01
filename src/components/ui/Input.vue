<script setup lang="ts">
import { computed, nextTick, useAttrs } from 'vue'

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

// Controlled: renders modelValue, emits update:modelValue on every input event (IME composition included), or on
// change with the `lazy` model modifier, and writes modelValue back when the caller kept or clamped the value.
const [model, modifiers] = defineModel<string | number | null, 'lazy' | 'number' | 'trim'>()
const attrs = useAttrs()
let composing = false
function setComposing(v: boolean) {
  composing = v
}

// Like Vue's looseToNumber: parseFloat, keep the string when it is NaN.
function cast(raw: string): string | number {
  if (attrs.type === 'number' || modifiers.number) {
    const n = parseFloat(raw)
    return isNaN(n) ? raw : n
  }
  return modifiers.trim ? raw.trim() : raw
}

function commit(e: Event) {
  const target = e.target as HTMLInputElement
  const value = cast(target.value)
  model.value = value
  nextTick(() => {
    if (composing || (e as InputEvent).isComposing) return
    const current = model.value ?? ''
    if (cast(target.value) !== current) target.value = String(current)
  })
}

function onInput(e: Event) {
  if (!modifiers.lazy) commit(e)
}

function onChange(e: Event) {
  if (modifiers.lazy) commit(e)
}

const NUMBER_CLASSES =
  '[appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none'

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
      v-bind="$attrs"
      :value="model ?? ''"
      @input="onInput"
      @change="onChange"
      @compositionstart="setComposing(true)"
      @compositionend="setComposing(false)"
      :disabled="disabled"
      :class="[
        'block w-full rounded-control border border-line-input bg-surface-card text-base text-fg-primary shadow-sm placeholder:text-fg-muted focus:border-line-focus focus:outline-none focus-visible:ring-1 focus-visible:ring-line-focus disabled:cursor-not-allowed disabled:opacity-50',
        SIZES[size],
        suffix && 'pr-10',
        $attrs.type === 'number' && NUMBER_CLASSES,
      ]"
    />
    <span
      v-if="suffix"
      class="pointer-events-none absolute inset-y-0 right-3 flex items-center text-base text-fg-muted"
      >{{ suffix }}</span
    >
  </div>
</template>
