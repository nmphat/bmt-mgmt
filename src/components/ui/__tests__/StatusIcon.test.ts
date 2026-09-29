import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import StatusIcon from '@/components/ui/StatusIcon.vue'

describe('StatusIcon', () => {
  it.each([
    ['Check', 'lucide-check', 'text-fg-success-soft'],
    ['Circle', 'lucide-circle', 'text-fg-faint'],
    ['Cross', 'lucide-x', 'text-fg-faint'],
    ['Lock', 'lucide-lock', 'text-fg-disabled'],
    ['Card', 'lucide-credit-card', 'text-fg-disabled'],
  ] as const)('Kind %s', (kind, icon, color) => {
    const w = mount(StatusIcon, { props: { kind, label: 'Paid' } })
    expect(w.attributes('data-ds')).toBe('Status Icon')
    expect(w.attributes('data-ds-kind')).toBe(kind)
    expect(w.classes()).toEqual(expect.arrayContaining(['inline-flex', 'shrink-0', color]))
    const svg = w.get('svg')
    expect(svg.classes()).toContain(icon)
    expect(svg.attributes('aria-hidden')).toBe('true')
  })

  it.each([
    ['16', 'size-4'],
    ['20', 'size-5'],
  ] as const)('Size %s', (size, cls) => {
    const w = mount(StatusIcon, { props: { size, label: 'Paid' } })
    expect(w.attributes('data-ds-size')).toBe(size)
    expect(w.classes()).toContain(cls)
    expect(w.get('svg').classes()).toContain(cls)
  })

  it('defaults to Kind Check, Size 16', () => {
    const w = mount(StatusIcon, { props: { label: 'Paid' } })
    expect(w.attributes('data-ds-kind')).toBe('Check')
    expect(w.attributes('data-ds-size')).toBe('16')
  })

  it('renders the label sr-only', () => {
    const w = mount(StatusIcon, { props: { kind: 'Lock', label: 'Locked' } })
    const label = w.get('span.sr-only')
    expect(label.text()).toBe('Locked')
  })
})
