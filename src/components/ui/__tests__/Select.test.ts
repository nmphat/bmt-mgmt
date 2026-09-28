import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import Select from '@/components/ui/Select.vue'

const options = '<option value="">Pick</option><option value="a">A</option>'

describe('Select', () => {
  it.each([
    ['Small', 'h-control-sm'],
    ['Default', 'h-control-md'],
    ['Large', 'h-control-lg'],
  ] as const)('Size %s', (size, cls) => {
    const w = mount(Select, { props: { size }, slots: { default: options } })
    expect(w.attributes('data-ds')).toBe('Select')
    expect(w.attributes('data-ds-size')).toBe(size)
    expect(w.get('select').classes()).toContain(cls)
    expect(w.get('select').classes()).toContain('rounded-control')
    expect(w.find('svg.lucide-chevron-down').exists()).toBe(true)
  })

  it('Content from the bound value', () => {
    const p = mount(Select, { props: { modelValue: '' }, slots: { default: options } })
    expect(p.attributes('data-ds-content')).toBe('Placeholder')
    expect(p.get('select').classes()).toContain('text-fg-muted')
    const f = mount(Select, { props: { modelValue: 'a' }, slots: { default: options } })
    expect(f.attributes('data-ds-content')).toBe('Filled')
    expect(f.get('select').classes()).toContain('text-fg-primary')
  })

  it('State from disabled', () => {
    const w = mount(Select, { props: { disabled: true }, slots: { default: options } })
    expect(w.attributes('data-ds-state')).toBe('Disabled')
    expect(w.get('select').attributes('disabled')).toBeDefined()
  })

  it('v-model updates the parent and attributes reach the <select>', async () => {
    const w = mount(Select, {
      props: {
        modelValue: '',
        'onUpdate:modelValue': (v: unknown) => w.setProps({ modelValue: v }),
      },
      attrs: { id: 'pick' },
      slots: { default: options },
    })
    expect(w.get('select').attributes('id')).toBe('pick')
    await w.get('select').setValue('a')
    expect(w.props('modelValue')).toBe('a')
  })
})
