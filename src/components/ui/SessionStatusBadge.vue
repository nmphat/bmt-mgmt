<script setup lang="ts">
import { computed } from 'vue'
import { useLangStore } from '@/stores/lang'
import Badge, { type BadgeTone } from './Badge.vue'

// Figma set "Session Status Badge" (components/session_status_badge.py). The caller maps the DB status to the
// Figma value; the label comes back from the existing common.<db status> key.
export type SessionStatus = 'Open' | 'Waiting For Payment' | 'Done' | 'Cancelled'

const props = defineProps<{ status: SessionStatus }>()

const STATUSES: Record<SessionStatus, { tone: BadgeTone; key: string }> = {
  Open: { tone: 'Info', key: 'common.open' },
  'Waiting For Payment': { tone: 'Warning', key: 'common.waiting_for_payment' },
  Done: { tone: 'Success', key: 'common.done' },
  Cancelled: { tone: 'Neutral', key: 'common.cancelled' },
}

const langStore = useLangStore()
const entry = computed(() => STATUSES[props.status])
</script>

<template>
  <span data-ds="Session Status Badge" :data-ds-status="status" class="inline-flex shrink-0">
    <Badge size="Default" :tone="entry.tone">{{ langStore.t(entry.key) }}</Badge>
  </span>
</template>
