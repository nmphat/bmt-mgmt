import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import Spinner from '@/components/ui/Spinner.vue'

describe('Spinner', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it('announces loading with the existing common.loading label', () => {
    const w = mount(Spinner)
    expect(w.attributes('role')).toBe('status')
    expect(w.get('.sr-only').text()).toBe('Đang tải...')
  })

  it.each([
    ['32', 'size-8'],
    ['48', 'size-12'],
  ] as const)('Size %s', (size, cls) => {
    const w = mount(Spinner, { props: { size } })
    expect(w.attributes('data-ds')).toBe('Spinner')
    expect(w.attributes('data-ds-size')).toBe(size)
    expect(w.classes()).toContain(cls)
  })

  it.each([
    ['Brand', 'border-line-brand'],
    ['Success', 'border-line-success'],
  ] as const)('Tone %s', (tone, cls) => {
    const w = mount(Spinner, { props: { tone } })
    expect(w.attributes('data-ds-tone')).toBe(tone)
    expect(w.classes()).toContain(cls)
  })
})
