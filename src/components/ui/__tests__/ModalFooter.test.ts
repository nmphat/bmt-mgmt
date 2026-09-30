import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import ModalFooter from '@/components/ui/ModalFooter.vue'

const slots = { primary: '<button id="p" />', secondary: '<button id="s" />' }
const order = (w: ReturnType<typeof mount>) => w.findAll('button').map((b) => b.attributes('id'))

describe('ModalFooter', () => {
  it('names its set and defaults to Gray One', () => {
    const w = mount(ModalFooter, { slots })
    expect(w.attributes('data-ds')).toBe('Modal Footer')
    expect(w.attributes('data-ds-background')).toBe('Gray')
    expect(w.attributes('data-ds-buttons')).toBe('One')
    expect(w.classes()).toEqual(expect.arrayContaining(['shrink-0', 'border-t']))
  })

  it('Background Gray: primary first, stacked below sm, reversed row from sm', () => {
    const w = mount(ModalFooter, { props: { background: 'Gray', buttons: 'Two' }, slots })
    expect(w.attributes('data-ds-buttons')).toBe('Two')
    expect(w.classes()).toEqual(
      expect.arrayContaining(['bg-surface-subtle', 'flex-col', 'sm:flex-row-reverse']),
    )
    expect(order(w)).toEqual(['p', 's'])
  })

  it('Background White: secondary first, equal-width row', () => {
    const w = mount(ModalFooter, { props: { background: 'White', buttons: 'Two' }, slots })
    expect(w.attributes('data-ds-background')).toBe('White')
    expect(w.classes()).toContain('bg-surface-card')
    expect(w.classes()).not.toContain('flex-col')
    expect(order(w)).toEqual(['s', 'p'])
  })

  it('Buttons One renders the primary slot alone', () => {
    const w = mount(ModalFooter, {
      props: { background: 'White' },
      slots: { primary: slots.primary },
    })
    expect(order(w)).toEqual(['p'])
  })
})
