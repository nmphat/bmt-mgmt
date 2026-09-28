<script setup lang="ts">
import type { Component } from 'vue'

// Figma set "Empty State" (components/empty_state.py). Default slot = the body text; `action` slot = the
// exposed action (a Button) below it.
export type EmptyStateVariant = 'Plain' | 'Card' | 'Dashed' | 'Dashed Muted'
export type EmptyStateAlign = 'Center' | 'Left'
export type EmptyStateSize = 'Default' | 'Small'

withDefaults(
  defineProps<{
    variant?: EmptyStateVariant
    align?: EmptyStateAlign
    size?: EmptyStateSize
    icon?: Component
    heading?: string
  }>(),
  { variant: 'Plain', align: 'Center', size: 'Default', icon: undefined, heading: undefined },
)

const VARIANTS: Record<EmptyStateVariant, string> = {
  Plain: '',
  Card: 'rounded-xl border border-line-divider bg-surface-card shadow-sm',
  Dashed: 'rounded-xl border border-dashed border-line-input bg-surface-card',
  'Dashed Muted': 'rounded-xl border border-dashed border-line-input bg-surface-subtle',
}
const HEADINGS: Record<EmptyStateVariant, string> = {
  Plain: 'text-base font-bold text-fg-primary',
  Card: 'text-base font-bold text-fg-primary',
  Dashed: 'text-xl font-bold text-fg-success',
  'Dashed Muted': 'text-base font-bold text-fg-primary',
}
const BODIES: Record<EmptyStateVariant, string> = {
  Plain: 'text-fg-muted',
  Card: 'text-fg-muted',
  Dashed: 'text-fg-secondary',
  'Dashed Muted': 'text-fg-secondary',
}
const SIZES: Record<EmptyStateSize, string> = { Default: 'text-base', Small: 'text-sm' }
const ICON_SIZES: Record<EmptyStateSize, string> = { Default: 'size-16', Small: 'size-8' }
</script>

<template>
  <div
    data-ds="Empty State"
    :data-ds-style="variant"
    :data-ds-align="align"
    :data-ds-size="size"
    :class="[
      'flex flex-col gap-2 p-6',
      VARIANTS[variant],
      align === 'Center' ? 'items-center text-center' : 'items-start',
    ]"
  >
    <component :is="icon" v-if="icon" :class="[ICON_SIZES[size], 'shrink-0 text-fg-faint']" />
    <p v-if="heading" :class="HEADINGS[variant]">{{ heading }}</p>
    <p :class="[SIZES[size], BODIES[variant]]"><slot /></p>
    <slot name="action" />
  </div>
</template>
