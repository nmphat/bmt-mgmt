<script setup lang="ts">
import { computed } from 'vue'
import { useLangStore } from '@/stores/lang'
import Badge from './Badge.vue'

// Figma set "Member Active Badge" (components/member_active_badge.py): a Badge with a fixed label, from the existing
// member.activeStatus / member.inactiveStatus keys.
const props = defineProps<{ active: boolean }>()

const langStore = useLangStore()
const tone = computed(() => (props.active ? 'Success' : 'Neutral'))
const label = computed(() =>
  langStore.t(props.active ? 'member.activeStatus' : 'member.inactiveStatus'),
)
</script>

<template>
  <span data-ds="Member Active Badge" :data-ds-active="String(active)" class="inline-flex shrink-0">
    <Badge size="Default" :tone="tone">{{ label }}</Badge>
  </span>
</template>
