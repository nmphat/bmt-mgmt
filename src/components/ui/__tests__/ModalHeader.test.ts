import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { DollarSign } from 'lucide-vue-next'
import ModalHeader from '@/components/ui/ModalHeader.vue'

const base = { title: 'Pay', titleId: 'title-1', closeLabel: 'Cancel' }

describe('ModalHeader', () => {
  it('renders the title with its id and a labelled close button', () => {
    const w = mount(ModalHeader, { props: base })
    expect(w.attributes('data-ds')).toBe('Modal Header')
    expect(w.classes()).toContain('border-line-divider')
    expect(w.find('h3#title-1').text()).toBe('Pay')
    expect(w.find('button').attributes('aria-label')).toBe('Cancel')
  })

  it('shows the icon only when given', () => {
    expect(mount(ModalHeader, { props: base }).find('h3 svg').exists()).toBe(false)
    const w = mount(ModalHeader, { props: { ...base, icon: DollarSign } })
    expect(w.find('h3 svg.lucide-dollar-sign').classes()).toContain('text-fg-success')
  })

  it('Close Default emits close', async () => {
    const w = mount(ModalHeader, { props: base })
    expect(w.attributes('data-ds-close')).toBe('Default')
    expect(w.find('button').attributes('disabled')).toBeUndefined()
    await w.find('button').trigger('click')
    expect(w.emitted('close')).toHaveLength(1)
  })

  it('Close Disabled disables the button and emits nothing', async () => {
    const w = mount(ModalHeader, { props: { ...base, close: 'Disabled' } })
    expect(w.attributes('data-ds-close')).toBe('Disabled')
    expect(w.find('button').attributes('disabled')).toBeDefined()
    await w.find('button').trigger('click')
    expect(w.emitted('close')).toBeUndefined()
  })
})
