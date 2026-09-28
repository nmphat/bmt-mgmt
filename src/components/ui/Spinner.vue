<script setup lang="ts">
import { computed } from 'vue'
import { useLangStore } from '@/stores/lang'

// Figma set "Spinner" (components/spinner.py): a ring with a 2 px bottom border.
export type SpinnerSize = '32' | '48'
export type SpinnerTone = 'Brand' | 'Success'

withDefaults(defineProps<{ size?: SpinnerSize; tone?: SpinnerTone }>(), {
  size: '32',
  tone: 'Brand',
})

// only for the sr-only label (existing key common.loading)
const langStore = useLangStore()
const t = computed(() => langStore.t)

const SIZES: Record<SpinnerSize, string> = { '32': 'size-8', '48': 'size-12' }
const TONES: Record<SpinnerTone, string> = {
  Brand: 'border-line-brand',
  Success: 'border-line-success',
}
</script>

<template>
  <div
    role="status"
    data-ds="Spinner"
    :data-ds-size="size"
    :data-ds-tone="tone"
    :class="['shrink-0 animate-spin rounded-full border-b-2', SIZES[size], TONES[tone]]"
  >
    <span class="sr-only">{{ t('common.loading') }}</span>
  </div>
</template>
