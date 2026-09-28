import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import RoleBadge from '@/components/ui/RoleBadge.vue'

describe('RoleBadge', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it.each([
    ['Admin', 'Brand', 'Quản trị viên', 'bg-surface-brand-muted'],
    ['Member', 'Neutral', 'Thành viên', 'bg-status-neutral'],
  ] as const)('Role %s', (role, tone, label, cls) => {
    const w = mount(RoleBadge, { props: { role } })
    expect(w.attributes('data-ds')).toBe('Role Badge')
    expect(w.attributes('data-ds-role')).toBe(role)
    const badge = w.get('[data-ds="Badge"]')
    expect(badge.attributes('data-ds-tone')).toBe(tone)
    expect(badge.classes()).toContain(cls)
    expect(badge.text()).toBe(label)
  })

  it.each([
    ['Default', 'text-sm'],
    ['Small', 'text-xs'],
  ] as const)('Size %s', (size, cls) => {
    const w = mount(RoleBadge, { props: { role: 'Member', size } })
    expect(w.attributes('data-ds-size')).toBe(size)
    const badge = w.get('[data-ds="Badge"]')
    expect(badge.attributes('data-ds-size')).toBe(size)
    expect(badge.classes()).toContain(cls)
  })

  it('defaults to Size Default', () => {
    const w = mount(RoleBadge, { props: { role: 'Admin' } })
    expect(w.attributes('data-ds-size')).toBe('Default')
  })
})
