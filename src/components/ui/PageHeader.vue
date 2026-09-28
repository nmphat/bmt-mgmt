<script setup lang="ts">
import type { Component } from 'vue'

// Figma set "Page Header" (components/page_header.py). "Title Action Stacked" is "Title Action" below `sm`.
// Back Title: the back control (an IconButton with its own handler) goes in the `leading` slot.
export type PageHeaderLayout = 'Title' | 'Title Action' | 'Back Title' | 'Icon Title' | 'Centered'

withDefaults(
  defineProps<{
    layout?: PageHeaderLayout
    title: string
    subtitle?: string
    icon?: Component
    // heading element level (keeps the page's current outline)
    level?: 1 | 2
  }>(),
  { layout: 'Title', subtitle: undefined, icon: undefined, level: 1 },
)

const LAYOUTS: Record<PageHeaderLayout, string> = {
  Title: 'flex items-center',
  'Title Action': 'flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between',
  'Back Title': 'flex items-center gap-4',
  'Icon Title': 'flex items-start gap-3',
  Centered: 'flex flex-col items-center gap-3 text-center',
}
</script>

<template>
  <div data-ds="Page Header" :data-ds-layout="layout" :class="LAYOUTS[layout]">
    <template v-if="layout === 'Back Title' || layout === 'Icon Title'">
      <slot v-if="layout === 'Back Title'" name="leading" />
      <div
        v-else-if="icon"
        class="flex size-11 shrink-0 items-center justify-center rounded-xl bg-surface-brand-subtle text-fg-brand"
      >
        <component :is="icon" class="size-5" />
      </div>
      <div class="flex flex-col gap-1">
        <component :is="`h${level}`" class="text-xl font-bold text-fg-primary">{{
          title
        }}</component>
        <p
          v-if="subtitle"
          :class="['text-sm', layout === 'Back Title' ? 'text-fg-muted' : 'text-fg-secondary']"
        >
          {{ subtitle }}
        </p>
      </div>
    </template>
    <template v-else>
      <component :is="`h${level}`" class="text-xl font-bold text-fg-primary">{{ title }}</component>
      <p v-if="subtitle && layout === 'Centered'" class="text-sm text-fg-secondary">
        {{ subtitle }}
      </p>
      <slot v-if="layout === 'Title Action'" name="actions" />
    </template>
  </div>
</template>
