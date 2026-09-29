import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createMemoryHistory } from 'vue-router'
import BottomNav from '@/components/BottomNav.vue'

async function mountAt(path: string) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: ['/', '/members', '/sessions', '/member/:id', '/session/:id', '/login'].map((p) => ({
      path: p,
      component: { template: '<div />' },
    })),
  })
  router.push(path)
  await router.isReady()
  return mount(BottomNav, { global: { plugins: [router] } })
}

describe('BottomNav (I/O matrix)', () => {
  beforeEach(() => setActivePinia(createPinia()))

  // Row: Bottom nav
  it.each([
    ['/', 'Home', 0],
    ['/member/x', 'Members', 1],
    ['/session/y', 'Sessions', 2],
    ['/login', 'None', -1],
  ] as const)('route %s: Active %s', async (path, active, index) => {
    const w = await mountAt(path)
    const nav = w.get('nav')
    expect(nav.attributes('data-ds')).toBe('Bottom Nav')
    expect(nav.attributes('data-ds-active')).toBe(active)
    expect(nav.attributes('aria-label')).toBe('Primary mobile navigation')
    const items = w.findAll('[data-ds="Bottom Nav Item"]')
    expect(items.map((i) => i.attributes('href'))).toEqual(['/', '/members', '/sessions'])
    items.forEach((item, i) => {
      const on = i === index
      expect(item.attributes('aria-current')).toBe(on ? 'page' : undefined)
      expect(item.attributes('data-ds-state')).toBe(on ? 'Active' : 'Inactive')
      expect(item.classes()).toContain(on ? 'bg-surface-brand-subtle' : 'text-fg-secondary')
      expect(item.get('svg').classes()).toContain('size-5')
    })
  })
})
