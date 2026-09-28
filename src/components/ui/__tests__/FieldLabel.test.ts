import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import FieldLabel from '@/components/ui/FieldLabel.vue'

describe('FieldLabel', () => {
  it.each([
    ['Default', 'text-sm'],
    ['Small', 'font-medium'],
    ['Caps', 'uppercase'],
    ['Muted', 'text-fg-muted'],
  ] as const)('Style %s', (variant, cls) => {
    const w = mount(FieldLabel, {
      props: { variant },
      attrs: { for: 'x' },
      slots: { default: 'Title' },
    })
    expect(w.element.tagName).toBe('LABEL')
    expect(w.attributes('data-ds')).toBe('Field Label')
    expect(w.attributes('data-ds-style')).toBe(variant)
    expect(w.attributes('for')).toBe('x')
    expect(w.classes()).toContain(cls)
    expect(w.text()).toBe('Title')
  })
})
