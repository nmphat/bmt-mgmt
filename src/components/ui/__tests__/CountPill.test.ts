import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import CountPill from '@/components/ui/CountPill.vue'

describe('CountPill', () => {
  it('Tone Danger (default): Badge Small Danger with the count', () => {
    const w = mount(CountPill, { slots: { default: '3' } })
    expect(w.attributes('data-ds')).toBe('Count Pill')
    expect(w.attributes('data-ds-tone')).toBe('Danger')
    const badge = w.get('[data-ds="Badge"]')
    expect(badge.attributes('data-ds-size')).toBe('Small')
    expect(badge.attributes('data-ds-tone')).toBe('Danger')
    expect(badge.classes()).toEqual(
      expect.arrayContaining([
        'px-2',
        'py-0.5',
        'text-xs',
        'font-semibold',
        'rounded-full',
        'whitespace-nowrap',
        'bg-status-danger',
        'text-status-danger-strong',
      ]),
    )
    expect(badge.text()).toBe('3')
  })
})
