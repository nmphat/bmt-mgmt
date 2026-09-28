<script setup lang="ts">
import type { Component } from 'vue'

// Figma set "Badge" (components/badge.py).
export type BadgeSize = 'Default' | 'Small'
export type BadgeTone = 'Info' | 'Warning' | 'Success' | 'Danger' | 'Neutral' | 'Brand'

withDefaults(defineProps<{ size?: BadgeSize; tone?: BadgeTone; icon?: Component }>(), {
  size: 'Default',
  tone: 'Info',
  icon: undefined,
})

const SIZES: Record<BadgeSize, string> = {
  Default: 'px-3 py-1 text-sm font-bold',
  Small: 'px-2 py-0.5 text-xs font-semibold',
}
const ICON_SIZES: Record<BadgeSize, string> = { Default: 'size-3.5', Small: 'size-3' }
const TONES: Record<BadgeTone, string> = {
  Info: 'bg-status-info text-status-info-strong',
  Warning: 'bg-status-warning text-status-warning-strong',
  Success: 'bg-status-success text-status-success-strong',
  Danger: 'bg-status-danger text-status-danger-strong',
  Neutral: 'bg-status-neutral text-status-neutral-strong',
  Brand: 'bg-surface-brand-muted text-fg-brand-strong',
}
</script>

<template>
  <span
    data-ds="Badge"
    :data-ds-size="size"
    :data-ds-tone="tone"
    :class="[
      'inline-flex items-center gap-1 whitespace-nowrap rounded-full',
      SIZES[size],
      TONES[tone],
    ]"
  >
    <component :is="icon" v-if="icon" :class="[ICON_SIZES[size], 'shrink-0']" />
    <slot />
  </span>
</template>
