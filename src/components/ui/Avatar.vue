<script setup lang="ts">
// Figma set "Avatar" (components/avatar.py): a member's initial in a circle, one bordered style.
export type AvatarSize = '32' | '64'

withDefaults(defineProps<{ size?: AvatarSize; initial: string }>(), { size: '32' })

const SIZES: Record<AvatarSize, string> = {
  '32': 'size-8 border text-sm font-semibold',
  '64': 'size-16 border-2 text-2xl font-bold',
}
</script>

<template>
  <div
    data-ds="Avatar"
    :data-ds-size="size"
    :class="[
      'flex shrink-0 items-center justify-center rounded-full border-line-brand-subtle bg-surface-brand-muted text-fg-brand-strong',
      SIZES[size],
    ]"
  >
    {{ initial }}
  </div>
</template>
