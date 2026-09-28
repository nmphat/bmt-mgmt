<script setup lang="ts">
import { computed, type Component } from 'vue'
import { LoaderCircle } from 'lucide-vue-next'

// Figma set "Button" (tools/figma-sync/projects/bmt-mgmt/components/button.py).
export type ButtonSize = 'Small' | 'Default' | 'Large'
export type ButtonVariant =
  | 'Primary'
  | 'Secondary'
  | 'Success'
  | 'Danger'
  | 'Inverse'
  | 'Outline Brand'
  | 'Outline Success'
  | 'Outline Danger'
  | 'Ghost'

const props = withDefaults(
  defineProps<{
    size?: ButtonSize
    variant?: ButtonVariant
    disabled?: boolean
    loading?: boolean
    // Outline Danger only (the absent toggle); undefined = not a toggle
    pressed?: boolean
    leadingIcon?: Component
    trailingIcon?: Component
    // 'RouterLink' resolves the globally registered router link by name
    as?: 'button' | 'a' | 'RouterLink' | Component
  }>(),
  {
    size: 'Small',
    variant: 'Primary',
    disabled: false,
    loading: false,
    pressed: undefined,
    leadingIcon: undefined,
    trailingIcon: undefined,
    as: 'button',
  },
)

const SIZES: Record<ButtonSize, string> = {
  Small: 'h-control-sm px-3 text-sm font-semibold',
  Default: 'h-control-md px-4 text-sm font-bold',
  Large: 'h-control-lg px-5 text-base font-bold',
}
const ICON_SIZES: Record<ButtonSize, string> = {
  Small: 'size-4',
  Default: 'size-5',
  Large: 'size-5',
}
const VARIANTS: Record<ButtonVariant, string> = {
  Primary: 'bg-surface-brand text-fg-on-brand shadow-sm hover:bg-fg-brand-strong',
  Secondary: 'border border-line-input bg-surface-card text-fg-secondary hover:bg-surface-subtle',
  Success: 'bg-surface-success text-fg-on-brand shadow-sm hover:bg-surface-success/90',
  Danger: 'bg-status-danger-action text-fg-on-brand shadow-sm hover:bg-status-danger-action/90',
  Inverse: 'bg-surface-card text-fg-brand hover:bg-surface-brand-subtle',
  'Outline Brand':
    'border border-line-brand bg-surface-card text-fg-brand hover:bg-surface-brand-subtle',
  'Outline Success':
    'border border-line-success bg-surface-card text-fg-success hover:bg-status-success-subtle',
  'Outline Danger':
    'border border-status-danger-border text-fg-danger hover:bg-status-danger-subtle',
  Ghost: 'text-fg-brand hover:text-fg-brand-strong',
}

const isNative = computed(() => props.as === 'button')
const isPressed = computed(() => props.variant === 'Outline Danger' && props.pressed === true)
const state = computed(() =>
  props.loading ? 'Loading' : props.disabled ? 'Disabled' : isPressed.value ? 'Pressed' : 'Default',
)
</script>

<template>
  <component
    :is="as"
    data-ds="Button"
    :data-ds-size="size"
    :data-ds-style="variant"
    :data-ds-state="state"
    :type="isNative ? 'button' : undefined"
    :disabled="isNative ? disabled : undefined"
    :aria-disabled="!isNative && disabled ? 'true' : undefined"
    :aria-busy="loading ? 'true' : undefined"
    :aria-pressed="variant === 'Outline Danger' && pressed !== undefined ? pressed : undefined"
    :class="[
      'inline-flex items-center justify-center gap-2 rounded-control transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-line-focus focus-visible:ring-offset-2',
      SIZES[size],
      VARIANTS[variant],
      variant === 'Outline Danger' && (isPressed ? 'bg-status-danger-subtle' : 'bg-surface-card'),
      disabled && 'cursor-not-allowed opacity-50',
    ]"
  >
    <LoaderCircle v-if="loading" :class="[ICON_SIZES[size], 'shrink-0 animate-spin']" />
    <component :is="leadingIcon" v-else-if="leadingIcon" :class="[ICON_SIZES[size], 'shrink-0']" />
    <slot />
    <component :is="trailingIcon" v-if="trailingIcon" :class="[ICON_SIZES[size], 'shrink-0']" />
  </component>
</template>
