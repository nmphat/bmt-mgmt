<script setup lang="ts">
import type { Component } from 'vue'
import { X } from 'lucide-vue-next'
import IconButton from './IconButton.vue'

// Figma set "Modal Header" (components/modal_header.py): title (+ optional icon) and the close button.
export type ModalHeaderClose = 'Default' | 'Disabled'

withDefaults(
  defineProps<{
    title: string
    titleId: string
    closeLabel: string
    icon?: Component
    close?: ModalHeaderClose
  }>(),
  { icon: undefined, close: 'Default' },
)

defineEmits<{ (e: 'close'): void }>()
</script>

<template>
  <div
    data-ds="Modal Header"
    :data-ds-close="close"
    class="flex shrink-0 items-start justify-between gap-3 border-b border-line-divider bg-surface-card p-4"
  >
    <h3 :id="titleId" class="flex items-center gap-2 text-xl font-bold text-fg-primary">
      <component :is="icon" v-if="icon" aria-hidden="true" class="size-6 text-fg-success" />
      {{ title }}
    </h3>
    <IconButton
      :icon="X"
      :label="closeLabel"
      size="Default"
      shape="Round"
      variant="Ghost"
      :disabled="close === 'Disabled'"
      @click="$emit('close')"
    />
  </div>
</template>
