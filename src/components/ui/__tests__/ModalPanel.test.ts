import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import ModalPanel from '@/components/ui/ModalPanel.vue'

const slots = { header: '<i id="h" />', default: '<b id="b" />', footer: '<u id="f" />' }

describe('ModalPanel', () => {
  it('names its set and renders header, body and footer in order', () => {
    const w = mount(ModalPanel, { slots })
    expect(w.attributes('data-ds')).toBe('Modal Panel')
    expect(w.classes()).toEqual(expect.arrayContaining(['bg-surface-card', 'rounded-t-2xl']))
    const order = w.findAll('#h, #b, #f').map((e) => e.attributes('id'))
    expect(order).toEqual(['h', 'b', 'f'])
    expect(w.find('.overflow-y-auto #b').exists()).toBe(true)
  })

  it.each([
    ['md', 'sm:max-w-md'],
    ['lg', 'sm:max-w-lg'],
  ] as const)('Width %s', (width, cls) => {
    const w = mount(ModalPanel, { props: { width }, slots })
    expect(w.attributes('data-ds-width')).toBe(width)
    expect(w.classes()).toContain(cls)
  })

  it('defaults to md', () => {
    expect(mount(ModalPanel).attributes('data-ds-width')).toBe('md')
  })
})
