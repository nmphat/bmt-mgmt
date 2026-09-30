<script setup lang="ts">
// Figma set "Modal Footer" (components/modal_footer.py). Gray: primary then secondary, stacked below `sm`,
// reversed row from `sm`. White: secondary then primary, equal-width row. Slots: `primary`, `secondary`.
export type ModalFooterBackground = 'Gray' | 'White'
export type ModalFooterButtons = 'One' | 'Two'

withDefaults(defineProps<{ background?: ModalFooterBackground; buttons?: ModalFooterButtons }>(), {
  background: 'Gray',
  buttons: 'One',
})
</script>

<template>
  <div
    data-ds="Modal Footer"
    :data-ds-background="background"
    :data-ds-buttons="buttons"
    :class="[
      'flex shrink-0 gap-3 border-t border-line-divider px-4 py-3 sm:px-6',
      background === 'Gray'
        ? 'flex-col bg-surface-subtle sm:flex-row-reverse [&>*]:w-full sm:[&>*]:w-auto'
        : 'bg-surface-card [&>*]:flex-1',
    ]"
  >
    <template v-if="background === 'Gray'">
      <slot name="primary" />
      <slot name="secondary" />
    </template>
    <template v-else>
      <slot name="secondary" />
      <slot name="primary" />
    </template>
  </div>
</template>
