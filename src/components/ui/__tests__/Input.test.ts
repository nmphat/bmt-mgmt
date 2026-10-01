import { describe, it, expect, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import Input from '@/components/ui/Input.vue'

// Types into the field: sets the value and fires only `input` (VTU's setValue also fires `change`).
async function type(
  w: { element: Element; trigger: (e: string) => Promise<void> },
  value: string | number,
) {
  ;(w.element as HTMLInputElement).value = String(value)
  await w.trigger('input')
}

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

  function controlled(props: Record<string, unknown> = {}, attrs: Record<string, unknown> = {}) {
    const w = mount(Input, {
      props: {
        modelValue: 3,
        'onUpdate:modelValue': vi.fn(),
        ...props,
      },
      attrs,
    })
    return w
  }

  it('emits on every input event, also during composition', async () => {
    const w = mount(Input, { props: { modelValue: '' } })
    const input = w.get('input')
    await input.trigger('compositionstart')
    await type(input, 'a')
    await type(input, 'an')
    expect(w.emitted('update:modelValue')).toEqual([['a'], ['an']])
  })

  it('casts to a number for type="number"', async () => {
    const w = controlled({}, { type: 'number' })
    await w.get('input').setValue('5')
    expect(w.emitted('update:modelValue')).toEqual([[5]])
  })

  it('writes the model back when the caller keeps or clamps the value', async () => {
    const w = controlled({ modelValue: 0 }, { type: 'number' })
    await w.get('input').setValue('-2')
    expect(w.get('input').element.value).toBe('0')
  })

  it('does not rewrite an equal number typed in another form', async () => {
    const w = controlled({ modelValue: 1 }, { type: 'number' })
    await w.get('input').setValue('1.0')
    expect(w.get('input').element.value).toBe('1.0')
  })

  it('does not write back while composing', async () => {
    const w = controlled({ modelValue: 'a' }, { type: 'text' })
    const input = w.get('input')
    await input.trigger('compositionstart')
    await type(input, 'an')
    expect(input.element.value).toBe('an')
  })

  it('lazy emits on change only', async () => {
    const w = controlled({ modelValue: 'a', modelModifiers: { lazy: true } }, { type: 'text' })
    const input = w.get('input')
    await type(input, 'abc')
    expect(w.emitted('update:modelValue')).toBeUndefined()
    expect(input.element.value).toBe('abc')
    await input.trigger('change')
    expect(w.emitted('update:modelValue')).toEqual([['abc']])
  })

  it('hides the native spinner only for type="number"', () => {
    expect(controlled({}, { type: 'number' }).get('input').classes()).toContain(
      '[appearance:textfield]',
    )
    expect(controlled({}, { type: 'text' }).get('input').classes()).not.toContain(
      '[appearance:textfield]',
    )
  })

  it('shows a suffix', () => {
    const w = mount(Input, { props: { suffix: '₫' } })
    expect(w.get('span.pointer-events-none').text()).toBe('₫')
  })
})
