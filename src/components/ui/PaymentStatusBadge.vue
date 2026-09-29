<script setup lang="ts">
import { computed } from 'vue'
import { useLangStore } from '@/stores/lang'
import Badge, { type BadgeTone } from './Badge.vue'

// Figma set "Payment Status Badge" (components/payment_status_badge.py). The caller maps the snapshot status to the
// Figma value; the label comes from the existing payment.<status> key.
export type PaymentStatus = 'Paid' | 'Partial' | 'Pending'

const props = defineProps<{ status: PaymentStatus }>()

const STATUSES: Record<PaymentStatus, { tone: BadgeTone; key: string }> = {
  Paid: { tone: 'Success', key: 'payment.paid' },
  Partial: { tone: 'Warning', key: 'payment.partial' },
  Pending: { tone: 'Danger', key: 'payment.pending' },
}

const langStore = useLangStore()
const entry = computed(() => STATUSES[props.status])
</script>

<template>
  <span data-ds="Payment Status Badge" :data-ds-status="status" class="inline-flex shrink-0">
    <Badge size="Default" :tone="entry.tone">{{ langStore.t(entry.key) }}</Badge>
  </span>
</template>
