import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { computed, ref } from 'vue'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createMemoryHistory } from 'vue-router'
import ProfileView from '@/views/ProfileView.vue'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { formatCurrency } from '@/utils/formatters'

const h = vi.hoisted(() => ({
  debt: null as unknown as Promise<{ data: unknown }>,
  bank: null as any,
}))

vi.mock('@/lib/supabase', () => {
  const builder: any = {
    select: () => builder,
    eq: () => builder,
    single: () => h.debt,
  }
  return {
    supabase: { from: vi.fn(() => builder), auth: { signOut: vi.fn() } },
    detachSupabaseVisibilityHandler: vi.fn(),
  }
})
vi.mock('@/composables/useBankConfig', () => ({ useBankConfig: () => h.bank }))

const bank = (id: string, is_active: boolean) => ({
  id,
  bank_id: `B${id}`,
  account_number: `100${id}`,
  account_name: `NAME ${id}`,
  template: 'compact2',
  is_active,
})

function setupBank(configs: ReturnType<typeof bank>[] = [bank('1', true)]) {
  const list = ref(configs)
  h.bank = {
    configs: list,
    activeBank: computed(() => list.value[0]),
    loading: ref(false),
    usingFallback: computed(() => list.value.length === 0),
    setActive: vi.fn().mockResolvedValue(undefined),
    addConfig: vi.fn().mockResolvedValue({ error: null }),
    removeConfig: vi.fn().mockResolvedValue(undefined),
  }
}

type Who = 'guest' | 'admin' | 'member'

async function mountProfile(who: Who) {
  setActivePinia(createPinia())
  const auth = useAuthStore()
  if (who !== 'guest') {
    auth.user = { id: 'u1', email: 'an@club.vn' } as any
    auth.profile = { id: 'm1', role: who, display_name: 'an Nguyen' }
  }
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/:p(.*)*', component: { template: '<div />' } }],
  })
  router.push('/profile')
  await router.isReady()
  const push = vi.spyOn(router, 'push')
  const w = mount(ProfileView, { global: { plugins: [router] } })
  await flushPromises()
  return { w, auth, push }
}

type W = Awaited<ReturnType<typeof mountProfile>>['w']
const t = (key: string, params?: Record<string, unknown>) => useLangStore().t(key, params as any)
const buttonByText = (w: W, text: string) => w.findAll('button').find((b) => b.text() === text)!
const debtCard = (w: W) => w.findAll('[data-ds="Section Header"]')[0]!.element.parentElement!

describe('ProfileView (I/O matrix)', () => {
  beforeEach(() => {
    h.debt = Promise.resolve({ data: { total_debt: 0, unpaid_session_count: 0 } })
    setupBank()
  })
  afterEach(() => vi.restoreAllMocks())

  it('guest: Empty State with User icon, guestPrompt and a Button Large Primary link to /login', async () => {
    const { w } = await mountProfile('guest')
    const empty = w.get('[data-ds="Empty State"]')
    expect(empty.attributes('data-ds-style')).toBe('Plain')
    expect(empty.attributes('data-ds-align')).toBe('Center')
    expect(empty.find('svg.lucide-user').exists()).toBe(true)
    expect(empty.get('p').text()).toBe(t('profile.guestPrompt'))
    const login = empty.get('a[data-ds="Button"]')
    expect(login.attributes('href')).toBe('/login')
    expect(login.attributes('data-ds-size')).toBe('Large')
    expect(login.attributes('data-ds-style')).toBe('Primary')
    expect(login.find('svg.lucide-log-in').exists()).toBe(true)
    expect(login.text()).toBe(t('auth.login'))
    expect(w.find('[data-ds="Avatar"]').exists()).toBe(false)
    expect(w.find('[data-ds="Section Header"]').exists()).toBe(false)
    expect(w.text()).not.toContain(t('auth.logout'))
    expect(w.text()).not.toContain(t('profile.bankConfig'))
    expect(w.text()).not.toContain(t('profile.addBank'))
  })

  it.each([
    ['admin', 'Admin'],
    ['member', 'Member'],
  ] as const)(
    'user card %s: Avatar 64 with the initial, Role Badge %s Small',
    async (who, role) => {
      const { w } = await mountProfile(who)
      const avatar = w.get('[data-ds="Avatar"]')
      expect(avatar.attributes('data-ds-size')).toBe('64')
      expect(avatar.text()).toBe('A')
      const badge = w.get('[data-ds="Role Badge"]')
      expect(badge.attributes('data-ds-role')).toBe(role)
      expect(badge.attributes('data-ds-size')).toBe('Small')
      expect(w.get('h2').text()).toBe('an Nguyen')
    },
  )

  it('debt loading: inline loading text with a spinner', async () => {
    h.debt = new Promise(() => {})
    const { w } = await mountProfile('member')
    const header = w.get('[data-ds="Section Header"]')
    expect(header.attributes('data-ds-style')).toBe('Caps')
    expect(header.get('h3').text()).toBe(t('profile.myDebt'))
    const loading = w.findAll('div.text-fg-disabled').find((d) => d.text() === t('common.loading'))!
    expect(loading.find('svg.animate-spin').exists()).toBe(true)
    expect(w.find('div.text-xl').exists()).toBe(false)
    expect(w.find('a[href^="/member/"]').exists()).toBe(false)
  })

  it('debt > 0: amount in text-fg-danger, unpaidSessions, history link to /member/<id>', async () => {
    h.debt = Promise.resolve({ data: { total_debt: 120000, unpaid_session_count: 3 } })
    const { w } = await mountProfile('member')
    const card = debtCard(w)
    const amount = w.findAll('div.text-xl').find((d) => d.text() === formatCurrency(120000))!
    expect(amount.classes()).toContain('text-fg-danger')
    expect(card.textContent).toContain(t('profile.unpaidSessions', { count: 3 }))
    const link = w.get('a[href="/member/m1"]')
    expect(link.attributes('data-ds')).toBe('Button')
    expect(link.attributes('data-ds-size')).toBe('Small')
    expect(link.attributes('data-ds-style')).toBe('Ghost')
  })

  it('debt 0: debtFree in text-fg-success', async () => {
    const { w } = await mountProfile('member')
    const clean = w.findAll('div.text-xl').find((d) => d.text() === t('profile.debtFree'))!
    expect(clean.classes()).toContain('text-fg-success')
    expect(debtCard(w).textContent).not.toContain(t('profile.unpaidSessions', { count: 0 }))
  })

  it('debt: no history link when the profile has no id', async () => {
    setActivePinia(createPinia())
    const auth = useAuthStore()
    auth.user = { id: 'u1', email: 'an@club.vn' } as any
    auth.profile = null
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: '/:p(.*)*', component: { template: '<div />' } }],
    })
    router.push('/profile')
    await router.isReady()
    const w = mount(ProfileView, { global: { plugins: [router] } })
    await flushPromises()
    expect(w.findAll('div.text-xl').some((d) => d.text() === t('profile.debtFree'))).toBe(true)
    expect(w.find('a[href^="/member/"]').exists()).toBe(false)
    expect(w.text()).not.toContain(t('profile.viewHistory'))
  })

  it('bank form: every Form Field label is tied to its input', async () => {
    const { w } = await mountProfile('admin')
    await buttonByText(w, t('profile.addBank')).trigger('click')
    const fields = w.findAll('[data-ds="Form Field"]')
    const keys = [
      'profile.bankId',
      'profile.templateLabel',
      'profile.accountNumber',
      'profile.accountName',
    ]
    expect(fields).toHaveLength(keys.length)
    fields.forEach((field, i) => {
      const id = field.get('input').attributes('id')
      expect(id).toBeTruthy()
      expect(field.get('label').attributes('for')).toBe(id)
      expect(field.get('label').text()).toBe(t(keys[i]!))
    })
  })

  it('bank section: hidden for a member, shown for an admin', async () => {
    const member = await mountProfile('member')
    expect(member.w.text()).not.toContain(t('profile.bankConfig'))
    const admin = await mountProfile('admin')
    const headers = admin.w.findAll('[data-ds="Section Header"]')
    expect(headers).toHaveLength(2)
    expect(headers[1]!.get('h3').text()).toBe(t('profile.bankConfig'))
    expect(headers[1]!.find('svg.lucide-credit-card').exists()).toBe(true)
  })

  it('bank add form: addConfig with upper-cased, trimmed values and default template compact2', async () => {
    const { w } = await mountProfile('admin')
    await buttonByText(w, t('profile.addBank')).trigger('click')
    const inputs = w.findAll('input')
    // DOM order: bank id, template, account number, account name
    expect(inputs.map((i) => i.classes().includes('uppercase'))).toEqual([true, false, false, true])
    await inputs[0]!.setValue(' tpb ')
    await inputs[1]!.setValue('  ')
    await inputs[2]!.setValue(' 10003392871 ')
    await inputs[3]!.setValue(' NGUYEN VAN A ')
    await buttonByText(w, t('profile.saveBank')).trigger('click')
    await flushPromises()
    expect(h.bank.addConfig).toHaveBeenCalledWith({
      bank_id: 'TPB',
      account_number: '10003392871',
      account_name: 'NGUYEN VAN A',
      template: 'compact2',
    })
    expect(w.find('input').exists()).toBe(false)
  })

  it('bank add form: missing field shows Field Message Error with icon; addConfig not called', async () => {
    const { w } = await mountProfile('admin')
    await buttonByText(w, t('profile.addBank')).trigger('click')
    await w.findAll('input')[0]!.setValue('TPB')
    await buttonByText(w, t('profile.saveBank')).trigger('click')
    await flushPromises()
    expect(h.bank.addConfig).not.toHaveBeenCalled()
    const msg = w.get('[data-ds="Field Message"]')
    expect(msg.attributes('data-ds-tone')).toBe('Error')
    expect(msg.attributes('data-ds-size')).toBe('Small')
    expect(msg.find('svg').exists()).toBe(true)
    expect(msg.text()).toBe('Vui lòng điền đầy đủ thông tin.')
  })

  it('bank add form: save disabled while addLoading', async () => {
    h.bank.addConfig.mockReturnValue(new Promise(() => {}))
    const { w } = await mountProfile('admin')
    await buttonByText(w, t('profile.addBank')).trigger('click')
    const inputs = w.findAll('input')
    await inputs[0]!.setValue('TPB')
    await inputs[2]!.setValue('1')
    await inputs[3]!.setValue('A')
    const save = () => buttonByText(w, t('profile.saveBank'))
    expect(save().attributes('disabled')).toBeUndefined()
    await save().trigger('click')
    expect(save().attributes('disabled')).toBeDefined()
    expect(save().attributes('data-ds-state')).toBe('Loading')
  })

  it('bank rows: Badge Small Success on the active row; toggle and delete call through', async () => {
    setupBank([bank('1', true), bank('2', false)])
    vi.spyOn(window, 'confirm').mockReturnValue(true)
    const { w } = await mountProfile('admin')
    const rows = w.findAll('div.px-5.py-4.border-b.border-line-subtle')
    expect(rows).toHaveLength(2)
    const badge = rows[0]!.get('[data-ds="Badge"]')
    expect(badge.attributes('data-ds-tone')).toBe('Success')
    expect(badge.text()).toBe(t('profile.activeLabel'))
    await rows[1]!.get(`button[title="${t('profile.activateBank')}"]`).trigger('click')
    expect(h.bank.setActive).toHaveBeenCalledWith('2')
    const del = rows[1]!.get('[data-ds="Icon Button"]')
    expect(del.attributes('aria-label')).toBe(t('settings.deleteBank'))
    await del.trigger('click')
    await flushPromises()
    expect(h.bank.removeConfig).toHaveBeenCalledWith('2')
  })

  it('fallback: Alert Warning with noBank, fallbackNote and the two detail lines', async () => {
    setupBank([])
    const { w } = await mountProfile('admin')
    const alert = w.get('[data-ds="Alert"]')
    expect(alert.attributes('data-ds-tone')).toBe('Warning')
    expect(alert.attributes('data-ds-style')).toBe('Box')
    expect(alert.find('svg.lucide-triangle-alert').exists()).toBe(true)
    const text = alert.text()
    expect(text).toContain(t('profile.noBank'))
    expect(text).toContain(t('profile.fallbackNote'))
    expect(text).toContain('Bank: TPB (TPBank)')
    expect(text).toContain('STK: 10003392871')
  })

  it('logout: signOut then push /login; disabled with a spinner while logging out', async () => {
    const { w, auth, push } = await mountProfile('member')
    let resolve!: () => void
    const signOut = vi.fn(() => new Promise<void>((r) => (resolve = r)))
    auth.signOut = signOut as any
    const logout = () => w.findAll('button').find((b) => b.text().includes(t('auth.logout')))!
    await logout().trigger('click')
    expect(signOut).toHaveBeenCalled()
    expect(push).not.toHaveBeenCalledWith('/login')
    expect(logout().attributes('disabled')).toBeDefined()
    expect(logout().find('svg.animate-spin').exists()).toBe(true)
    resolve()
    await flushPromises()
    expect(push).toHaveBeenCalledWith('/login')
  })
})
