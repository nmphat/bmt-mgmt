import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { X } from 'lucide-vue-next'
import IconButton from '@/components/ui/IconButton.vue'

const base = { icon: X, label: 'Close' }

describe('IconButton', () => {
  it('names its set and labels the icon-only control', () => {
    const w = mount(IconButton, { props: base })
    expect(w.attributes('data-ds')).toBe('Icon Button')
    expect(w.attributes('aria-label')).toBe('Close')
    expect(w.find('svg.lucide-x').exists()).toBe(true)
  })

  it('defaults to type="button"; a caller type wins', () => {
    expect(mount(IconButton, { props: base }).attributes('type')).toBe('button')
    expect(mount(IconButton, { props: base, attrs: { type: 'submit' } }).attributes('type')).toBe(
      'submit',
    )
  })

  it.each([
    ['Small', 'size-8'],
    ['Default', 'h-control-md'],
  ] as const)('Size %s', (size, cls) => {
    const w = mount(IconButton, { props: { ...base, size } })
    expect(w.attributes('data-ds-size')).toBe(size)
    expect(w.classes()).toContain(cls)
  })

  it.each([
    ['Round', 'rounded-full'],
    ['Square', 'rounded-control'],
  ] as const)('Shape %s', (shape, cls) => {
    const w = mount(IconButton, { props: { ...base, shape } })
    expect(w.attributes('data-ds-shape')).toBe(shape)
    expect(w.classes()).toContain(cls)
  })

  it.each([
    ['Ghost', 'text-fg-muted'],
    ['Ghost Brand', 'text-fg-brand'],
    ['Ghost Success', 'text-fg-success'],
    ['Ghost Danger', 'text-fg-danger'],
    ['Outline', 'border-line-input'],
  ] as const)('Style %s', (variant, cls) => {
    const w = mount(IconButton, { props: { ...base, variant } })
    expect(w.attributes('data-ds-style')).toBe(variant)
    expect(w.classes()).toContain(cls)
  })

  it('State from disabled; loading spins without disabling', () => {
    const d = mount(IconButton, { props: { ...base, disabled: true } })
    expect(d.attributes('data-ds-state')).toBe('Disabled')
    expect(d.attributes('disabled')).toBeDefined()
    const l = mount(IconButton, { props: { ...base, loading: true } })
    expect(l.attributes('data-ds-state')).toBe('Default')
    expect(l.attributes('disabled')).toBeUndefined()
    expect(l.attributes('aria-busy')).toBe('true')
    expect(l.find('svg').classes()).toContain('animate-spin')
  })
})
