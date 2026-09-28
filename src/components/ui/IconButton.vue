<script setup lang="ts">
import { computed, type Component } from 'vue'

// Figma set "Icon Button" (components/icon_button.py).
export type IconButtonSize = 'Small' | 'Default'
export type IconButtonShape = 'Round' | 'Square'
export type IconButtonVariant =
  | 'Ghost'
  | 'Ghost Brand'
  | 'Ghost Success'
  | 'Ghost Danger'
  | 'Outline'

const props = withDefaults(
  defineProps<{
    icon: Component
    label: string
    size?: IconButtonSize
    shape?: IconButtonShape
    variant?: IconButtonVariant
    disabled?: boolean
    // spins the icon (prod RefreshCcw); does not disable
    loading?: boolean
  }>(),
  { size: 'Small', shape: 'Round', variant: 'Ghost', disabled: false, loading: false },
)

const SIZES: Record<IconButtonSize, string> = {
  Small: 'size-8',
  Default: 'h-control-md w-control-md',
}
const ICON_SIZES: Record<IconButtonSize, string> = { Small: 'size-4', Default: 'size-5' }
const SHAPES: Record<IconButtonShape, string> = { Round: 'rounded-full', Square: 'rounded-control' }
const VARIANTS: Record<IconButtonVariant, string> = {
  Ghost: 'text-fg-muted hover:bg-surface-muted',
  'Ghost Brand': 'text-fg-brand hover:bg-surface-brand-subtle',
  'Ghost Success': 'text-fg-success hover:bg-status-success-subtle',
  'Ghost Danger': 'text-fg-danger hover:bg-status-danger-subtle',
  Outline: 'border border-line-input bg-surface-card text-fg-secondary hover:bg-surface-subtle',
}

const state = computed(() => (props.disabled ? 'Disabled' : 'Default'))
</script>

<template>
  <button
    data-ds="Icon Button"
    :data-ds-size="size"
    :data-ds-shape="shape"
    :data-ds-style="variant"
    :data-ds-state="state"
    type="button"
    :disabled="disabled"
    :aria-label="label"
    :aria-busy="loading ? 'true' : undefined"
    :class="[
      'inline-flex shrink-0 items-center justify-center transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-line-focus focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50',
      SIZES[size],
      SHAPES[shape],
      VARIANTS[variant],
    ]"
  >
    <component :is="icon" :class="[ICON_SIZES[size], loading && 'animate-spin']" />
  </button>
</template>
