import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import Checkbox from '@/components/ui/Checkbox.vue'

describe('Checkbox', () => {
  it.each([
    ['16', 'size-4'],
    ['20', 'size-5'],
    ['24', 'size-6'],
  ] as const)('Size %s', (size, cls) => {
    const w = mount(Checkbox, { props: { size } })
    expect(w.element.tagName).toBe('INPUT')
    expect(w.attributes('type')).toBe('checkbox')
    expect(w.attributes('data-ds')).toBe('Checkbox')
    expect(w.attributes('data-ds-size')).toBe(size)
    expect(w.classes()).toContain(cls)
    expect(w.classes()).toContain('accent-surface-brand')
  })

  it.each([
    [false, false, 'Unchecked'],
    [true, false, 'Checked'],
    [false, true, 'Disabled Unchecked'],
    [true, true, 'Disabled Checked'],
  ] as const)('State checked=%s disabled=%s -> %s', (modelValue, disabled, state) => {
    const w = mount(Checkbox, { props: { modelValue, disabled } })
    expect(w.attributes('data-ds-state')).toBe(state)
  })

  it('v-model with an array and a value', async () => {
    const w = mount(Checkbox, {
      props: {
        modelValue: [] as unknown[],
        value: 'm1',
        'onUpdate:modelValue': (v: unknown) => w.setProps({ modelValue: v as unknown[] }),
      },
    })
    await w.get('input').setValue(true)
    expect(w.props('modelValue')).toEqual(['m1'])
    expect(w.attributes('data-ds-state')).toBe('Checked')
  })
})
