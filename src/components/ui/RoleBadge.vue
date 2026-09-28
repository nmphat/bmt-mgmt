<script setup lang="ts">
import { computed } from 'vue'
import { useLangStore } from '@/stores/lang'
import Badge, { type BadgeSize, type BadgeTone } from './Badge.vue'

// Figma set "Role Badge" (components/role_badge.py): a Badge with a fixed label per role, from the existing
// common.admin / common.member keys.
export type Role = 'Admin' | 'Member'

const props = withDefaults(defineProps<{ role: Role; size?: BadgeSize }>(), { size: 'Default' })

const ROLES: Record<Role, { tone: BadgeTone; key: string }> = {
  Admin: { tone: 'Brand', key: 'common.admin' },
  Member: { tone: 'Neutral', key: 'common.member' },
}

const langStore = useLangStore()
const entry = computed(() => ROLES[props.role])
</script>

<template>
  <span data-ds="Role Badge" :data-ds-role="role" :data-ds-size="size" class="inline-flex shrink-0">
    <Badge :size="size" :tone="entry.tone">{{ langStore.t(entry.key) }}</Badge>
  </span>
</template>
