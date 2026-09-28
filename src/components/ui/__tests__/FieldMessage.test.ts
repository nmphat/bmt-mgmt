import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { TriangleAlert } from 'lucide-vue-next'
import FieldMessage from '@/components/ui/FieldMessage.vue'

describe('FieldMessage', () => {
  it.each([
    ['Help', 'text-fg-muted'],
    ['Error', 'text-status-danger-action'],
  ] as const)('Tone %s', (tone, cls) => {
    const w = mount(FieldMessage, { props: { tone }, slots: { default: 'msg' } })
    expect(w.attributes('data-ds')).toBe('Field Message')
    expect(w.attributes('data-ds-tone')).toBe(tone)
    expect(w.classes()).toContain(cls)
  })

  it.each([
    ['Default', 'text-sm'],
    ['Small', 'text-xs'],
  ] as const)('Size %s', (size, cls) => {
    const w = mount(FieldMessage, { props: { size } })
    expect(w.attributes('data-ds-size')).toBe(size)
    expect(w.classes()).toContain(cls)
  })

  it.each([
    ['Left', false],
    ['Center', true],
  ] as const)('Align %s', (align, centered) => {
    const w = mount(FieldMessage, { props: { align } })
    expect(w.attributes('data-ds-align')).toBe(align)
    expect(w.classes().includes('text-center')).toBe(centered)
  })

  it('shows an optional icon', () => {
    expect(mount(FieldMessage).find('svg').exists()).toBe(false)
    expect(
      mount(FieldMessage, { props: { icon: TriangleAlert } })
        .find('svg')
        .exists(),
    ).toBe(true)
  })
})
