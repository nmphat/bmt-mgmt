import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { Receipt } from 'lucide-vue-next'
import EmptyState from '@/components/ui/EmptyState.vue'

describe('EmptyState', () => {
  it.each([
    ['Plain', 'p-6'],
    ['Card', 'bg-surface-card'],
    ['Dashed', 'border-dashed'],
    ['Dashed Muted', 'bg-surface-subtle'],
  ] as const)('Style %s', (variant, cls) => {
    const w = mount(EmptyState, { props: { variant }, slots: { default: 'Nothing' } })
    expect(w.attributes('data-ds')).toBe('Empty State')
    expect(w.attributes('data-ds-style')).toBe(variant)
    expect(w.classes()).toContain(cls)
    expect(w.text()).toBe('Nothing')
  })

  it.each([
    ['Center', 'text-center'],
    ['Left', 'items-start'],
  ] as const)('Align %s', (align, cls) => {
    const w = mount(EmptyState, { props: { align } })
    expect(w.attributes('data-ds-align')).toBe(align)
    expect(w.classes()).toContain(cls)
  })

  it.each([
    ['Default', 'text-base', 'size-16'],
    ['Small', 'text-sm', 'size-8'],
  ] as const)('Size %s', (size, body, icon) => {
    const w = mount(EmptyState, { props: { size, icon: Receipt, heading: 'Clear' } })
    expect(w.attributes('data-ds-size')).toBe(size)
    expect(w.findAll('p')[1]!.classes()).toContain(body)
    expect(w.get('svg').classes()).toContain(icon)
    expect(w.findAll('p')[0]!.text()).toBe('Clear')
  })
})
