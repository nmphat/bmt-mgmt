<script setup lang="ts">
import type { Component } from 'vue'

// Figma set "Alert" (components/alert.py). Default slot = the message; `action` slot = a Button in the tone's
// action style (Danger -> Outline Danger, others -> Secondary).
export type AlertTone = 'Danger' | 'Warning' | 'Info' | 'Success' | 'Neutral'
export type AlertSize = 'Default' | 'Small'
export type AlertVariant = 'Box' | 'Banner'
export type AlertAlign = 'Left' | 'Center'

withDefaults(
  defineProps<{
    tone?: AlertTone
    size?: AlertSize
    variant?: AlertVariant
    align?: AlertAlign
    icon?: Component
  }>(),
  { tone: 'Danger', size: 'Default', variant: 'Box', align: 'Left', icon: undefined },
)

const TONES: Record<AlertTone, string> = {
  Danger: 'border-status-danger-border bg-status-danger-subtle text-status-danger-strong',
  Warning: 'border-status-warning-border bg-status-warning-subtle text-status-warning-strong',
  Info: 'border-status-info-border bg-status-info-subtle text-status-info-strong',
  Success: 'border-status-success-border bg-status-success-subtle text-status-success-strong',
  Neutral: 'border-line-divider bg-surface-subtle text-fg-secondary',
}
const SIZES: Record<AlertSize, string> = { Default: 'p-4 text-sm', Small: 'px-2 py-1.5 text-xs' }
const GAPS: Record<AlertSize, string> = { Default: 'gap-3', Small: 'gap-1.5' }
const ICON_SIZES: Record<AlertSize, string> = { Default: 'size-5', Small: 'size-3.5' }
</script>

<template>
  <div
    data-ds="Alert"
    :data-ds-tone="tone"
    :data-ds-size="size"
    :data-ds-style="variant"
    :data-ds-align="align"
    :role="tone === 'Danger' ? 'alert' : undefined"
    :class="[
      'flex flex-col gap-3',
      SIZES[size],
      variant === 'Banner'
        ? 'border-l-4 border-line-strong bg-surface-subtle text-fg-secondary'
        : ['rounded-xl border', TONES[tone]],
      align === 'Center' && 'items-center text-center',
    ]"
  >
    <div :class="['flex', GAPS[size], align === 'Center' && 'justify-center']">
      <component
        :is="icon"
        v-if="icon"
        :class="[ICON_SIZES[size], 'shrink-0', variant === 'Banner' && 'text-fg-disabled']"
      />
      <div class="flex min-w-0 flex-col gap-1">
        <slot />
      </div>
    </div>
    <slot name="action" />
  </div>
</template>
