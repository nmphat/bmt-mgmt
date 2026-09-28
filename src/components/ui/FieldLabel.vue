<script setup lang="ts">
// Figma set "Field Label" (components/field_label.py). `for` falls through to the <label>.
export type FieldLabelVariant = 'Default' | 'Small' | 'Caps' | 'Muted'

withDefaults(defineProps<{ variant?: FieldLabelVariant }>(), { variant: 'Default' })

const VARIANTS: Record<FieldLabelVariant, string> = {
  Default: 'text-sm font-bold text-fg-secondary',
  Small: 'text-xs font-medium text-fg-secondary',
  Caps: 'text-xs font-bold uppercase text-fg-muted',
  Muted: 'text-xs text-fg-muted',
}
</script>

<template>
  <label data-ds="Field Label" :data-ds-style="variant" :class="['block', VARIANTS[variant]]">
    <slot />
  </label>
</template>
