<script setup lang="ts">
import type { Component } from 'vue'

// Figma set "Field Message" (components/field_message.py).
export type FieldMessageTone = 'Help' | 'Error'
export type FieldMessageSize = 'Default' | 'Small'
export type FieldMessageAlign = 'Left' | 'Center'

withDefaults(
  defineProps<{
    tone?: FieldMessageTone
    size?: FieldMessageSize
    align?: FieldMessageAlign
    icon?: Component
  }>(),
  { tone: 'Help', size: 'Default', align: 'Left', icon: undefined },
)

const TONES: Record<FieldMessageTone, string> = {
  Help: 'text-fg-muted',
  Error: 'text-status-danger-action',
}
const SIZES: Record<FieldMessageSize, string> = { Default: 'text-sm', Small: 'text-xs' }
const ICON_SIZES: Record<FieldMessageSize, string> = { Default: 'size-4', Small: 'size-3.5' }
</script>

<template>
  <p
    data-ds="Field Message"
    :data-ds-tone="tone"
    :data-ds-size="size"
    :data-ds-align="align"
    :class="[
      'flex items-center gap-1',
      TONES[tone],
      SIZES[size],
      align === 'Center' && 'justify-center text-center',
    ]"
  >
    <component :is="icon" v-if="icon" :class="[ICON_SIZES[size], 'shrink-0']" />
    <slot />
  </p>
</template>
