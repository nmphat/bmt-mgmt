import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { CreditCard } from 'lucide-vue-next'
import SectionHeader from '@/components/ui/SectionHeader.vue'

describe('SectionHeader', () => {
  it.each([
    ['Tinted', ['px-6', 'bg-surface-subtle'], ['text-xl', 'font-bold', 'text-fg-primary']],
    ['Caps', ['px-5'], ['text-sm', 'font-bold', 'uppercase', 'tracking-wider', 'text-fg-muted']],
    ['Plain Title', ['px-5'], ['text-xl', 'font-bold', 'text-fg-primary']],
  ] as const)('Style %s', (variant, root, title) => {
    const w = mount(SectionHeader, { props: { variant, title: 'Payments' } })
    expect(w.attributes('data-ds')).toBe('Section Header')
    expect(w.attributes('data-ds-style')).toBe(variant)
    expect(w.classes()).toEqual(
      expect.arrayContaining([
        ...root,
        'border-b',
        'border-line-divider',
        'py-4',
        'justify-between',
      ]),
    )
    const h = w.get('h2')
    expect(h.text()).toBe('Payments')
    expect(h.classes()).toEqual(expect.arrayContaining(title))
  })

  it('defaults to Style Caps, level 2, no icon', () => {
    const w = mount(SectionHeader, { props: { title: 'Payments' } })
    expect(w.attributes('data-ds-style')).toBe('Caps')
    expect(w.find('h2').exists()).toBe(true)
    expect(w.find('svg').exists()).toBe(false)
  })

  it('level 3 renders an h3', () => {
    const w = mount(SectionHeader, { props: { title: 'Debt', level: 3 } })
    expect(w.find('h2').exists()).toBe(false)
    expect(w.get('h3').text()).toBe('Debt')
  })

  it('icon: size-4 text-fg-disabled', () => {
    const w = mount(SectionHeader, { props: { title: 'Bank', icon: CreditCard } })
    const svg = w.get('svg')
    expect(svg.classes()).toEqual(expect.arrayContaining(['size-4', 'text-fg-disabled']))
    expect(svg.attributes('aria-hidden')).toBe('true')
  })

  it('actions slot', () => {
    const w = mount(SectionHeader, {
      props: { title: 'Bank' },
      slots: { actions: '<button type="button">Add</button>' },
    })
    expect(w.get('button').text()).toBe('Add')
  })

  it('suffix renders a muted span inside the heading', () => {
    const w = mount(SectionHeader, { props: { title: 'Costs', suffix: '(live)' } })
    const span = w.get('h2 span')
    expect(span.text()).toBe('(live)')
    expect(span.classes()).toEqual(['text-sm', 'font-normal', 'text-fg-muted'])
    expect(w.get('h2').text()).toBe('Costs (live)')
    expect(
      mount(SectionHeader, { props: { title: 'Costs' } })
        .find('h2 span')
        .exists(),
    ).toBe(false)
  })

  it('badge slot renders under the title', () => {
    const w = mount(SectionHeader, {
      props: { title: 'Attendance' },
      slots: { badge: '<span data-testid="badge">Locked</span>' },
    })
    const title = w.get('h2')
    const badge = w.get('[data-testid="badge"]')
    expect(badge.text()).toBe('Locked')
    expect(
      title.element.compareDocumentPosition(badge.element) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy()
  })
})
