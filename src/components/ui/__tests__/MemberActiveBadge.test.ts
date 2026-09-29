import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import MemberActiveBadge from '@/components/ui/MemberActiveBadge.vue'

describe('MemberActiveBadge', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it.each([
    [true, 'true', 'Success', 'bg-status-success', 'Đang hoạt động'],
    [false, 'false', 'Neutral', 'bg-status-neutral', 'Ngừng hoạt động'],
  ] as const)('Active %s', (active, value, tone, cls, label) => {
    const w = mount(MemberActiveBadge, { props: { active } })
    expect(w.attributes('data-ds')).toBe('Member Active Badge')
    expect(w.attributes('data-ds-active')).toBe(value)
    const badge = w.get('[data-ds="Badge"]')
    expect(badge.attributes('data-ds-tone')).toBe(tone)
    expect(badge.attributes('data-ds-size')).toBe('Default')
    expect(badge.classes()).toContain(cls)
    expect(badge.text()).toBe(label)
  })
})
