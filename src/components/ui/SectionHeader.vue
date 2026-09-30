<script setup lang="ts">
import type { Component } from 'vue'

// Figma set "Section Header" (components/section_header.py): header bar of a card section. The exposed action
// (a Button Ghost) goes in the `actions` slot; the optional Badge goes in the `badge` slot, under the title.
export type SectionHeaderVariant = 'Tinted' | 'Caps' | 'Plain Title'

withDefaults(
  defineProps<{
    variant?: SectionHeaderVariant
    title: string
    // muted inline note after the title, e.g. "(live)"
    suffix?: string
    icon?: Component
    // heading element level (keeps the page's current outline)
    level?: 2 | 3
  }>(),
  { variant: 'Caps', suffix: undefined, icon: undefined, level: 2 },
)

const VARIANTS: Record<SectionHeaderVariant, string> = {
  Tinted: 'bg-surface-subtle px-6',
  Caps: 'px-5',
  'Plain Title': 'px-5',
}
const TITLES: Record<SectionHeaderVariant, string> = {
  Tinted: 'text-xl font-bold text-fg-primary',
  Caps: 'text-sm font-bold uppercase tracking-wider text-fg-muted',
  'Plain Title': 'text-xl font-bold text-fg-primary',
}
</script>

<template>
  <div
    data-ds="Section Header"
    :data-ds-style="variant"
    :class="[
      'flex items-center justify-between gap-3 border-b border-line-divider py-4',
      VARIANTS[variant],
    ]"
  >
    <div class="flex flex-col items-start gap-2">
      <div class="flex items-center gap-2">
        <component
          :is="icon"
          v-if="icon"
          class="size-4 shrink-0 text-fg-disabled"
          aria-hidden="true"
        />
        <component :is="`h${level}`" :class="TITLES[variant]">
          {{ title }}
          <template v-if="suffix">
            <span class="text-sm font-normal text-fg-muted">{{ suffix }}</span>
          </template>
        </component>
      </div>
      <slot name="badge" />
    </div>
    <slot name="actions" />
  </div>
</template>
