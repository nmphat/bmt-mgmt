import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import Avatar from '@/components/ui/Avatar.vue'

describe('Avatar', () => {
  it.each([
    ['32', ['size-8', 'text-sm', 'font-semibold', 'border']],
    ['64', ['size-16', 'text-2xl', 'font-bold', 'border-2']],
  ] as const)('Size %s', (size, classes) => {
    const w = mount(Avatar, { props: { size, initial: 'A' } })
    expect(w.attributes('data-ds')).toBe('Avatar')
    expect(w.attributes('data-ds-size')).toBe(size)
    expect(w.classes()).toEqual(
      expect.arrayContaining([
        ...classes,
        'rounded-full',
        'border-line-brand-subtle',
        'bg-surface-brand-muted',
        'text-fg-brand-strong',
      ]),
    )
    expect(w.text()).toBe('A')
  })

  it('defaults to Size 32', () => {
    const w = mount(Avatar, { props: { initial: 'B' } })
    expect(w.attributes('data-ds-size')).toBe('32')
    expect(w.classes()).toContain('size-8')
  })
})
