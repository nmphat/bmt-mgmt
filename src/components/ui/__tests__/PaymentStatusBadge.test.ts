import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import PaymentStatusBadge from '@/components/ui/PaymentStatusBadge.vue'

describe('PaymentStatusBadge', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it.each([
    ['Paid', 'Success', 'bg-status-success', 'Đã đóng'],
    ['Partial', 'Warning', 'bg-status-warning', 'Chưa đủ'],
    ['Pending', 'Danger', 'bg-status-danger', 'Chưa đóng'],
  ] as const)('Status %s', (status, tone, cls, label) => {
    const w = mount(PaymentStatusBadge, { props: { status } })
    expect(w.attributes('data-ds')).toBe('Payment Status Badge')
    expect(w.attributes('data-ds-status')).toBe(status)
    const badge = w.get('[data-ds="Badge"]')
    expect(badge.attributes('data-ds-tone')).toBe(tone)
    expect(badge.attributes('data-ds-size')).toBe('Default')
    expect(badge.classes()).toContain(cls)
    expect(badge.text()).toBe(label)
  })
})
