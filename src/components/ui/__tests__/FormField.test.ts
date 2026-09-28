import { describe, it, expect } from 'vitest'
import { defineComponent, ref, nextTick } from 'vue'
import { mount } from '@vue/test-utils'
import FormField from '@/components/ui/FormField.vue'
import Input from '@/components/ui/Input.vue'

describe('FormField', () => {
  it.each(['Default', 'Small', 'Caps', 'Muted'] as const)('Label Style %s', (labelStyle) => {
    const w = mount(FormField, { props: { label: 'Title', labelStyle } })
    expect(w.attributes('data-ds')).toBe('Form Field')
    expect(w.attributes('data-ds-label-style')).toBe(labelStyle)
    expect(w.get('label').attributes('data-ds-style')).toBe(labelStyle)
    expect(w.classes()).toContain('gap-1')
  })

  it.each(['Input', 'Select'] as const)('Control %s', (control) => {
    const w = mount(FormField, { props: { label: 'Title', control } })
    expect(w.attributes('data-ds-control')).toBe(control)
  })

  it('links label, control and help message', () => {
    const w = mount(FormField, {
      props: { label: 'Fee', controlId: 'courtFee', message: 'Hint' },
      slots: {
        default: `<template #default="{ controlProps }"><input v-bind="controlProps" /></template>`,
      },
    })
    const input = w.get('input')
    expect(w.get('label').attributes('for')).toBe('courtFee')
    expect(input.attributes('id')).toBe('courtFee')
    const msg = w.get('[data-ds="Field Message"]')
    expect(input.attributes('aria-describedby')).toBe(msg.attributes('id'))
    expect(msg.attributes('data-ds-tone')).toBe('Help')
    expect(input.attributes('aria-invalid')).toBeUndefined()
  })

  it('generates an id when the control has none', () => {
    const w = mount(FormField, {
      props: { label: 'Title' },
      slots: {
        default: `<template #default="{ controlProps }"><input v-bind="controlProps" /></template>`,
      },
    })
    const id = w.get('input').attributes('id')
    expect(id).toBeTruthy()
    expect(w.get('label').attributes('for')).toBe(id)
    expect(w.get('input').attributes('aria-describedby')).toBeUndefined()
  })

  it('sets aria-invalid while an Error message slot is shown', async () => {
    const Host = defineComponent({
      components: { FormField, Input },
      setup: () => ({ invalid: ref(false), v: ref('') }),
      template: `
        <FormField label="End" control-id="endTime" message-tone="Error">
          <template #default="{ controlProps }"><Input v-model="v" v-bind="controlProps" /></template>
          <template v-if="invalid" #message>Bad</template>
        </FormField>`,
    })
    const w = mount(Host)
    expect(w.get('input').attributes('aria-invalid')).toBeUndefined()
    expect(w.find('[data-ds="Field Message"]').exists()).toBe(false)
    ;(w.vm as unknown as { invalid: boolean }).invalid = true
    await nextTick()
    const input = w.get('input')
    expect(input.attributes('id')).toBe('endTime')
    expect(input.attributes('aria-invalid')).toBe('true')
    const msg = w.get('[data-ds="Field Message"]')
    expect(msg.attributes('data-ds-tone')).toBe('Error')
    expect(input.attributes('aria-describedby')).toBe(msg.attributes('id'))
    expect(msg.text()).toBe('Bad')
  })
})
