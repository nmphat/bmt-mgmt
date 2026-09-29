<script setup lang="ts">
import Badge from './Badge.vue'

// Figma set "Count Pill" (components/count_pill.py): a numeric pill with Badge Small metrics. Default slot = the count.
export type CountPillTone = 'Danger'

withDefaults(defineProps<{ tone?: CountPillTone }>(), { tone: 'Danger' })
</script>

<template>
  <span data-ds="Count Pill" :data-ds-tone="tone" class="inline-flex shrink-0">
    <Badge size="Small" :tone="tone"><slot /></Badge>
  </span>
</template>
