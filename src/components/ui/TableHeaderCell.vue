<script setup lang="ts">
// Figma set "Table Header Cell" (components/table_header_cell.py): a <th> of every desktop table, h44, sm/Bold
// uppercase muted on surface/subtle. Default slot = the label (Text) or the checkbox (Checkbox); Empty has none.
export type TableHeaderCellContent = 'Text' | 'Checkbox' | 'Empty'
export type TableHeaderCellAlign = 'Left' | 'Center' | 'Right'
export type TableHeaderCellDensity = 'Default' | 'Compact'

withDefaults(
  defineProps<{
    content?: TableHeaderCellContent
    align?: TableHeaderCellAlign
    density?: TableHeaderCellDensity
  }>(),
  { content: 'Text', align: 'Left', density: 'Default' },
)

const ALIGNS: Record<TableHeaderCellAlign, string> = {
  Left: 'text-left',
  Center: 'text-center',
  Right: 'text-right',
}
const DENSITIES: Record<TableHeaderCellDensity, string> = { Default: 'px-6', Compact: 'px-3' }
</script>

<template>
  <th
    scope="col"
    data-ds="Table Header Cell"
    :data-ds-content="content"
    :data-ds-align="align"
    :data-ds-density="density"
    :class="[
      'h-11 whitespace-nowrap bg-surface-subtle py-3 text-sm font-bold uppercase tracking-wider text-fg-muted',
      ALIGNS[align],
      DENSITIES[density],
    ]"
  >
    <slot v-if="content !== 'Empty'" />
  </th>
</template>
