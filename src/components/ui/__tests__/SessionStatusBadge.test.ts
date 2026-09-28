import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import SessionStatusBadge from '@/components/ui/SessionStatusBadge.vue'

describe('SessionStatusBadge', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it.each([
    ['Open', 'Info', 'Đang mở'],
    ['Waiting For Payment', 'Warning', 'Chờ thu'],
    ['Done', 'Success', 'Hoàn tất'],
    ['Cancelled', 'Neutral', 'Đã hủy'],
  ] as const)('Status %s', (status, tone, label) => {
    const w = mount(SessionStatusBadge, { props: { status } })
    expect(w.attributes('data-ds')).toBe('Session Status Badge')
    expect(w.attributes('data-ds-status')).toBe(status)
    const badge = w.get('[data-ds="Badge"]')
    expect(badge.attributes('data-ds-tone')).toBe(tone)
    expect(badge.attributes('data-ds-size')).toBe('Default')
    expect(badge.text()).toBe(label)
  })
})
