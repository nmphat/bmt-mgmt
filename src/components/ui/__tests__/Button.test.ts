import { describe, it, expect } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createRouter, createMemoryHistory } from 'vue-router'
import { Plus } from 'lucide-vue-next'
import Button from '@/components/ui/Button.vue'

describe('Button', () => {
  it('defaults to the Figma set default and names its set', () => {
    const w = mount(Button, { slots: { default: 'Save' } })
    expect(w.attributes('data-ds')).toBe('Button')
    expect(w.attributes('data-ds-size')).toBe('Small')
    expect(w.attributes('data-ds-style')).toBe('Primary')
    expect(w.attributes('data-ds-state')).toBe('Default')
    expect(w.text()).toBe('Save')
  })

  it.each([
    ['Small', 'h-control-sm'],
    ['Default', 'h-control-md'],
    ['Large', 'h-control-lg'],
  ] as const)('Size %s', (size, cls) => {
    const w = mount(Button, { props: { size } })
    expect(w.attributes('data-ds-size')).toBe(size)
    expect(w.classes()).toContain(cls)
    expect(w.classes()).toContain('rounded-control')
  })

  it.each([
    ['Primary', 'bg-surface-brand'],
    ['Secondary', 'border-line-input'],
    ['Success', 'bg-surface-success'],
    ['Danger', 'bg-status-danger-action'],
    ['Inverse', 'bg-surface-card'],
    ['Outline Brand', 'border-line-brand'],
    ['Outline Success', 'border-line-success'],
    ['Outline Danger', 'border-status-danger-border'],
    ['Ghost', 'text-fg-brand'],
  ] as const)('Style %s', (variant, cls) => {
    const w = mount(Button, { props: { variant } })
    expect(w.attributes('data-ds-style')).toBe(variant)
    expect(w.classes()).toContain(cls)
  })

  it('State Disabled: native disabled, 50 % opacity', () => {
    const w = mount(Button, { props: { disabled: true } })
    expect(w.attributes('data-ds-state')).toBe('Disabled')
    expect(w.attributes('disabled')).toBeDefined()
    expect(w.classes()).toContain('opacity-50')
  })

  it('State Loading: spinner, aria-busy, not disabled', () => {
    const w = mount(Button, { props: { loading: true, leadingIcon: Plus } })
    expect(w.attributes('data-ds-state')).toBe('Loading')
    expect(w.attributes('aria-busy')).toBe('true')
    expect(w.attributes('disabled')).toBeUndefined()
    expect(w.find('svg.animate-spin').exists()).toBe(true)
    expect(w.find('svg.lucide-plus').exists()).toBe(false)
  })

  it('State Pressed: Outline Danger only, aria-pressed', () => {
    const w = mount(Button, { props: { variant: 'Outline Danger', pressed: true } })
    expect(w.attributes('data-ds-state')).toBe('Pressed')
    expect(w.attributes('aria-pressed')).toBe('true')
    expect(w.classes()).toContain('bg-status-danger-subtle')
    const off = mount(Button, { props: { variant: 'Outline Danger', pressed: false } })
    expect(off.attributes('data-ds-state')).toBe('Default')
    expect(off.attributes('aria-pressed')).toBe('false')
    const other = mount(Button, { props: { variant: 'Primary', pressed: true } })
    expect(other.attributes('data-ds-state')).toBe('Default')
    expect(other.attributes('aria-pressed')).toBeUndefined()
  })

  it('renders icons and passes native attributes and listeners through', async () => {
    const w = mount(Button, {
      props: { leadingIcon: Plus, trailingIcon: Plus },
      attrs: { type: 'submit' },
    })
    expect(w.findAll('svg.lucide-plus')).toHaveLength(2)
    expect(w.attributes('type')).toBe('submit')
    await w.trigger('click')
    expect(w.emitted()).toHaveProperty('click')
  })

  it('renders as a link without the disabled attribute', () => {
    const w = mount(Button, { props: { as: 'a', disabled: true }, attrs: { href: '/x' } })
    expect(w.element.tagName).toBe('A')
    expect(w.attributes('href')).toBe('/x')
    expect(w.attributes('disabled')).toBeUndefined()
    expect(w.attributes('aria-disabled')).toBe('true')
  })

  it("renders as the app's RouterLink by name", async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: '/:p(.*)*', component: { template: '<div />' } }],
    })
    router.push('/')
    await router.isReady()
    const w = mount(Button, {
      props: { as: 'RouterLink', size: 'Default' },
      attrs: { to: '/create-session?from=sessions' },
      slots: { default: 'New' },
      global: { plugins: [router] },
    })
    await flushPromises()
    expect(w.element.tagName).toBe('A')
    expect(w.attributes('href')).toBe('/create-session?from=sessions')
    expect(w.attributes('data-ds-size')).toBe('Default')
  })
})
