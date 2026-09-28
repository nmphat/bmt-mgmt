import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import Input from '@/components/ui/Input.vue'

describe('Input', () => {
  it.each([
    ['Small', 'h-control-sm'],
    ['Default', 'h-control-md'],
    ['Large', 'h-control-lg'],
  ] as const)('Size %s', (size, cls) => {
    const w = mount(Input, { props: { size } })
    expect(w.attributes('data-ds')).toBe('Input')
    expect(w.attributes('data-ds-size')).toBe(size)
    expect(w.get('input').classes()).toContain(cls)
    expect(w.get('input').classes()).toContain('border-line-input')
    expect(w.get('input').classes()).toContain('rounded-control')
  })

  it('Content from the bound value', () => {
    expect(mount(Input, { props: { modelValue: '' } }).attributes('data-ds-content')).toBe(
      'Placeholder',
    )
    expect(mount(Input, { props: { modelValue: 'x' } }).attributes('data-ds-content')).toBe(
      'Filled',
    )
    expect(mount(Input, { props: { modelValue: 0 } }).attributes('data-ds-content')).toBe('Filled')
  })

  it('State from disabled', () => {
    const w = mount(Input, { props: { disabled: true } })
    expect(w.attributes('data-ds-state')).toBe('Disabled')
    expect(w.get('input').attributes('disabled')).toBeDefined()
    expect(mount(Input).attributes('data-ds-state')).toBe('Default')
  })

  it('v-model updates the parent', async () => {
    const w = mount(Input, {
      props: {
        modelValue: 'a',
        'onUpdate:modelValue': (v: unknown) => w.setProps({ modelValue: v as string }),
      },
    })
    expect(w.get('input').element.value).toBe('a')
    await w.get('input').setValue('bc')
    expect(w.props('modelValue')).toBe('bc')
    expect(w.attributes('data-ds-content')).toBe('Filled')
  })

  it('passes native attributes to the <input>, not the root', () => {
    const w = mount(Input, {
      attrs: {
        id: 'title',
        type: 'number',
        min: '0',
        step: '1000',
        required: '',
        'aria-invalid': 'true',
      },
    })
    const input = w.get('input')
    expect(input.attributes('id')).toBe('title')
    expect(input.attributes('type')).toBe('number')
    expect(input.attributes('min')).toBe('0')
    expect(input.attributes('step')).toBe('1000')
    expect(input.attributes('required')).toBeDefined()
    expect(input.attributes('aria-invalid')).toBe('true')
    expect(w.attributes('id')).toBeUndefined()
  })

  it('shows a suffix', () => {
    const w = mount(Input, { props: { suffix: '₫' } })
    expect(w.get('span.pointer-events-none').text()).toBe('₫')
  })
})
