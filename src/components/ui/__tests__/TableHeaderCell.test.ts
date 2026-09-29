import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import TableHeaderCell from '@/components/ui/TableHeaderCell.vue'

const mountCell = (props: Record<string, unknown> = {}, slot = 'Tên') =>
  mount(TableHeaderCell, { props, slots: { default: slot } })

describe('TableHeaderCell', () => {
  it('renders a th scope col with the h44 header style and Figma defaults', () => {
    const w = mountCell()
    expect(w.element.tagName).toBe('TH')
    expect(w.attributes('scope')).toBe('col')
    expect(w.attributes('data-ds')).toBe('Table Header Cell')
    expect(w.attributes('data-ds-content')).toBe('Text')
    expect(w.attributes('data-ds-align')).toBe('Left')
    expect(w.attributes('data-ds-density')).toBe('Default')
    expect(w.classes()).toEqual(
      expect.arrayContaining([
        'h-11',
        'py-3',
        'whitespace-nowrap',
        'bg-surface-subtle',
        'text-sm',
        'font-bold',
        'uppercase',
        'tracking-wider',
        'text-fg-muted',
      ]),
    )
    expect(w.text()).toBe('Tên')
  })

  it.each([
    ['Text', 'Tên'],
    ['Checkbox', ''],
    ['Empty', ''],
  ] as const)('Content %s', (content, text) => {
    const slot = content === 'Checkbox' ? '<input type="checkbox" />' : 'Tên'
    const w = mountCell({ content }, slot)
    expect(w.attributes('data-ds-content')).toBe(content)
    expect(w.text()).toBe(text)
    expect(w.find('input[type="checkbox"]').exists()).toBe(content === 'Checkbox')
  })

  it.each([
    ['Left', 'text-left'],
    ['Center', 'text-center'],
    ['Right', 'text-right'],
  ] as const)('Align %s', (align, cls) => {
    const w = mountCell({ align })
    expect(w.attributes('data-ds-align')).toBe(align)
    expect(w.classes()).toContain(cls)
  })

  it.each([
    ['Default', 'px-6', 'px-3'],
    ['Compact', 'px-3', 'px-6'],
  ] as const)('Density %s', (density, cls, other) => {
    const w = mountCell({ density })
    expect(w.attributes('data-ds-density')).toBe(density)
    expect(w.classes()).toContain(cls)
    expect(w.classes()).not.toContain(other)
  })
})
