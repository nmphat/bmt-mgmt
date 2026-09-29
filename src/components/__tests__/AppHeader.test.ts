import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createMemoryHistory } from 'vue-router'
import AppHeader from '@/components/AppHeader.vue'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'

// One Supabase chain builder per `from()` call; the record keeps the chain for exact payload assertions.
const h = vi.hoisted(() => ({
  result: { data: null, error: null } as any,
  chains: [] as { table: string; calls: { m: string; args: any[] }[] }[],
}))

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn((table: string) => {
      const record = { table, calls: [] as { m: string; args: any[] }[] }
      h.chains.push(record)
      const builder: any = {}
      for (const method of ['select', 'eq']) {
        builder[method] = vi.fn((...args: any[]) => {
          record.calls.push({ m: method, args })
          return builder
        })
      }
      builder.then = (resolve: any) => resolve(h.result)
      return builder
    }),
    auth: { signOut: vi.fn(async () => ({ error: null })) },
  },
  detachSupabaseVisibilityHandler: vi.fn(),
}))

const t = (key: string, params?: Record<string, unknown>) => useLangStore().t(key, params as any)

type Who = 'admin' | 'member' | 'guest'

async function mountHeader(who: Who) {
  setActivePinia(createPinia())
  const auth = useAuthStore()
  if (who !== 'guest') {
    auth.user = { id: 'u1', email: 'an@club.vn' } as any
    auth.profile = { id: 'm1', role: who, display_name: 'an' }
  }
  const router = createRouter({
    history: createMemoryHistory(),
    routes: ['/', '/sessions', '/members', '/member/:id', '/settings'].map((path) => ({
      path,
      component: { template: '<div />' },
    })),
  })
  router.push('/')
  await router.isReady()
  const w = mount(AppHeader, { global: { plugins: [router] } })
  await flushPromises()
  return { w, auth, router }
}

describe('AppHeader (I/O matrix)', () => {
  beforeEach(() => {
    h.result = { data: null, error: null }
    h.chains = []
  })
  afterEach(() => vi.restoreAllMocks())

  // Row: Header guest
  it('guest: logo link to /, 3 nav links, Language Toggle; no Debt Chip, no user menu', async () => {
    const { w } = await mountHeader('guest')
    const header = w.get('header')
    expect(header.attributes('data-ds')).toBe('App Header')
    expect(header.attributes('data-ds-auth')).toBe('Guest')
    expect(header.classes()).toEqual(expect.arrayContaining(['px-4', 'sm:px-6', 'lg:px-8']))
    const logo = w.get('[data-ds="Brand Logo"]')
    expect(logo.attributes('href')).toBe('/')
    expect(logo.text()).toBe('Badminton Mgmt')
    const links = w.findAll('[data-ds="Header Nav Link"]')
    expect(links.map((l) => [l.attributes('href'), l.text()])).toEqual([
      ['/', t('nav.home')],
      ['/sessions', t('nav.sessions')],
      ['/members', t('nav.members')],
    ])
    expect(links[0]!.classes()).toEqual(
      expect.arrayContaining(['text-fg-brand', 'border-line-brand']),
    )
    const toggle = w.get('[data-ds="Language Toggle"]')
    expect(toggle.attributes('data-ds-lang')).toBe('VI')
    expect(toggle.attributes('aria-label')).toBe(t('shell.languageSwitcher'))
    expect(w.find('[data-ds="Debt Chip"]').exists()).toBe(false)
    expect(w.find('[data-ds="User Menu Trigger"]').exists()).toBe(false)
    expect(h.chains).toEqual([])
  })

  // Row: Header signed in
  it('signed in with debt: Debt Chip Debt with debt.prefix and the amount; exact debt query', async () => {
    h.result = { data: [{ total_debt: 54000 }], error: null }
    const { w } = await mountHeader('member')
    expect(w.get('header').attributes('data-ds-auth')).toBe('Signed In')
    expect(h.chains).toEqual([
      {
        table: 'view_member_debt_summary',
        calls: [
          { m: 'select', args: ['total_debt'] },
          { m: 'eq', args: ['member_id', 'm1'] },
        ],
      },
    ])
    const chip = w.get('[data-ds="Debt Chip"]')
    expect(chip.attributes('data-ds-state')).toBe('Debt')
    expect(chip.classes()).toEqual(expect.arrayContaining(['h-11', 'bg-status-danger-subtle']))
    expect(chip.text()).toMatch(new RegExp(`^${t('debt.prefix')}: 54\\.000`))
  })

  it('signed in without debt: Debt Chip Clean with debt.clean', async () => {
    h.result = { data: [{ total_debt: 0 }], error: null }
    const { w } = await mountHeader('member')
    const chip = w.get('[data-ds="Debt Chip"]')
    expect(chip.attributes('data-ds-state')).toBe('Clean')
    expect(chip.classes()).toContain('bg-status-success-subtle')
    expect(chip.text()).toBe(t('debt.clean'))
  })

  // Row: User menu
  it('user menu (admin): trigger opens the menu with name, email, profile and settings; logout signs out', async () => {
    h.result = { data: [], error: null }
    const { w, auth, router } = await mountHeader('admin')
    const signOut = vi.spyOn(auth, 'signOut').mockResolvedValue()
    const push = vi.spyOn(router, 'push')
    const trigger = w.get('[data-ds="User Menu Trigger"]')
    expect(trigger.attributes('aria-expanded')).toBe('false')
    expect(trigger.attributes('aria-haspopup')).toBe('menu')
    expect(trigger.get('[data-ds="Avatar"]').text()).toBe('A')
    expect(w.find('[role="menu"]').exists()).toBe(false)
    await trigger.trigger('click')
    expect(trigger.attributes('aria-expanded')).toBe('true')
    const menu = w.get('[role="menu"]')
    expect(menu.attributes('data-ds')).toBe('User Menu')
    expect(menu.text()).toContain('an')
    expect(menu.text()).toContain('an@club.vn')
    const items = menu.findAll('[role="menuitem"]')
    expect(
      items.map((i) => [i.attributes('data-ds'), i.attributes('data-ds-tone'), i.text()]),
    ).toEqual([
      ['Menu Item', 'Default', t('auth.profile')],
      ['Menu Item', 'Default', t('auth.admin_settings')],
      ['Menu Item', 'Danger', t('auth.logout')],
    ])
    expect(items[0]!.attributes('href')).toBe('/member/m1')
    expect(items[1]!.attributes('href')).toBe('/settings')
    await items[2]!.trigger('click')
    await flushPromises()
    expect(signOut).toHaveBeenCalledTimes(1)
    expect(push).toHaveBeenCalledWith('/')
    expect(signOut.mock.invocationCallOrder[0]!).toBeLessThan(push.mock.invocationCallOrder[0]!)
    expect(w.find('[role="menu"]').exists()).toBe(false)
  })

  it('user menu (member): no settings item', async () => {
    h.result = { data: [], error: null }
    const { w } = await mountHeader('member')
    await w.get('[data-ds="User Menu Trigger"]').trigger('click')
    const items = w.get('[role="menu"]').findAll('[role="menuitem"]')
    expect(items.map((i) => i.text())).toEqual([t('auth.profile'), t('auth.logout')])
  })

  // Row: Language
  it('language: the toggle switches vi to en', async () => {
    const { w } = await mountHeader('guest')
    const lang = useLangStore()
    const setLang = vi.spyOn(lang, 'setLang')
    await w.get('[data-ds="Language Toggle"]').trigger('click')
    expect(setLang).toHaveBeenCalledWith('en')
    expect(w.get('[data-ds="Language Toggle"]').attributes('data-ds-lang')).toBe('EN')
  })
})
