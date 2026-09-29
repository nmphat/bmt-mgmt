<script setup lang="ts">
import type { Component } from 'vue'
import { Check, Circle, CreditCard, Lock, X } from 'lucide-vue-next'

// Figma set "Status Icon" (components/status_icon.py): a colored icon fixed per kind. `label` is required and
// rendered sr-only; the caller passes the existing key that states what the icon means in that place.
export type StatusIconKind = 'Check' | 'Circle' | 'Cross' | 'Lock' | 'Card'
export type StatusIconSize = '16' | '20'

withDefaults(defineProps<{ kind?: StatusIconKind; size?: StatusIconSize; label: string }>(), {
  kind: 'Check',
  size: '16',
})

const KINDS: Record<StatusIconKind, { icon: Component; color: string }> = {
  Check: { icon: Check, color: 'text-fg-success-soft' },
  Circle: { icon: Circle, color: 'text-fg-faint' },
  Cross: { icon: X, color: 'text-fg-faint' },
  Lock: { icon: Lock, color: 'text-fg-disabled' },
  Card: { icon: CreditCard, color: 'text-fg-disabled' },
}
const SIZES: Record<StatusIconSize, string> = { '16': 'size-4', '20': 'size-5' }
</script>

<template>
  <span
    data-ds="Status Icon"
    :data-ds-kind="kind"
    :data-ds-size="size"
    :class="['inline-flex shrink-0 items-center justify-center', SIZES[size], KINDS[kind].color]"
  >
    <component :is="KINDS[kind].icon" :class="SIZES[size]" aria-hidden="true" />
    <span class="sr-only">{{ label }}</span>
  </span>
</template>
