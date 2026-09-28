import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { CreditCard } from 'lucide-vue-next'
import PageHeader from '@/components/ui/PageHeader.vue'

describe('PageHeader', () => {
  it('Layout Title', () => {
    const w = mount(PageHeader, { props: { title: 'Sessions' } })
    expect(w.attributes('data-ds')).toBe('Page Header')
    expect(w.attributes('data-ds-layout')).toBe('Title')
    const h = w.get('h1')
    expect(h.text()).toBe('Sessions')
    expect(h.classes()).toContain('text-xl')
    expect(h.classes()).toContain('text-fg-primary')
  })

  it('Layout Title Action: row from sm, stacked below', () => {
    const w = mount(PageHeader, {
      props: { layout: 'Title Action', title: 'Sessions' },
      slots: { actions: '<a href="/new">New</a>' },
    })
    expect(w.attributes('data-ds-layout')).toBe('Title Action')
    expect(w.classes()).toEqual(expect.arrayContaining(['flex-col', 'sm:flex-row']))
    expect(w.get('a').text()).toBe('New')
  })

  it('Layout Centered with subtitle and heading level', () => {
    const w = mount(PageHeader, {
      props: { layout: 'Centered', title: 'Sign in', subtitle: 'Sub', level: 2 },
    })
    expect(w.attributes('data-ds-layout')).toBe('Centered')
    expect(w.classes()).toContain('text-center')
    expect(w.get('h2').text()).toBe('Sign in')
    expect(w.get('p').classes()).toContain('text-fg-secondary')
  })

  it('Layout Back Title', () => {
    const w = mount(PageHeader, {
      props: { layout: 'Back Title', title: 'Member', subtitle: 'History' },
      slots: { leading: '<button aria-label="Back">x</button>' },
    })
    expect(w.attributes('data-ds-layout')).toBe('Back Title')
    expect(w.get('button').attributes('aria-label')).toBe('Back')
    expect(w.get('p').classes()).toContain('text-fg-muted')
  })

  it('Layout Icon Title', () => {
    const w = mount(PageHeader, {
      props: { layout: 'Icon Title', title: 'Settings', subtitle: 'Bank', icon: CreditCard },
    })
    expect(w.attributes('data-ds-layout')).toBe('Icon Title')
    expect(w.find('.bg-surface-brand-subtle svg').exists()).toBe(true)
  })
})
