import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import Alert from '@/components/ui/Alert.vue'

describe('Alert', () => {
  it.each([
    ['Danger', 'bg-status-danger-subtle'],
    ['Warning', 'bg-status-warning-subtle'],
    ['Info', 'bg-status-info-subtle'],
    ['Success', 'bg-status-success-subtle'],
    ['Neutral', 'bg-surface-subtle'],
  ] as const)('Tone %s', (tone, cls) => {
    const w = mount(Alert, { props: { tone }, slots: { default: 'Msg' } })
    expect(w.attributes('data-ds')).toBe('Alert')
    expect(w.attributes('data-ds-tone')).toBe(tone)
    expect(w.classes()).toContain(cls)
    expect(w.attributes('role')).toBe(tone === 'Danger' ? 'alert' : undefined)
    expect(w.text()).toBe('Msg')
  })

  it.each([
    ['Default', 'p-4'],
    ['Small', 'py-1.5'],
  ] as const)('Size %s', (size, cls) => {
    const w = mount(Alert, { props: { size } })
    expect(w.attributes('data-ds-size')).toBe(size)
    expect(w.classes()).toContain(cls)
  })

  it.each([
    ['Box', 'rounded-xl'],
    ['Banner', 'border-l-4'],
  ] as const)('Style %s', (variant, cls) => {
    const w = mount(Alert, { props: { variant, tone: 'Neutral' } })
    expect(w.attributes('data-ds-style')).toBe(variant)
    expect(w.classes()).toContain(cls)
  })

  it.each([
    ['Left', false],
    ['Center', true],
  ] as const)('Align %s', (align, centered) => {
    const w = mount(Alert, { props: { align, tone: 'Neutral' } })
    expect(w.attributes('data-ds-align')).toBe(align)
    expect(w.classes().includes('text-center')).toBe(centered)
  })

  it('renders the action slot', () => {
    const w = mount(Alert, { slots: { default: 'Msg', action: '<button>Retry</button>' } })
    expect(w.get('button').text()).toBe('Retry')
  })
})
