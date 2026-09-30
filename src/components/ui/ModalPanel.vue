<script setup lang="ts">
// Figma set "Modal Panel" (components/modal_panel.py): the dialog surface only. The dialog root, the centering
// wrapper and the scrim stay in each modal file. Slots: `header`, default (scrolling body), `footer`.
export type ModalPanelWidth = 'md' | 'lg'

withDefaults(defineProps<{ width?: ModalPanelWidth }>(), { width: 'md' })

const WIDTHS: Record<ModalPanelWidth, string> = { md: 'sm:max-w-md', lg: 'sm:max-w-lg' }
</script>

<template>
  <div
    data-ds="Modal Panel"
    :data-ds-width="width"
    :class="[
      'relative z-10 flex max-h-[88dvh] w-full flex-col overflow-hidden rounded-t-2xl bg-surface-card text-left shadow-xl sm:rounded-xl',
      WIDTHS[width],
    ]"
  >
    <slot name="header" />
    <div class="flex-1 overflow-y-auto px-4 sm:px-6">
      <slot />
    </div>
    <slot name="footer" />
  </div>
</template>
