import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createMemoryHistory } from 'vue-router'
import DashboardView from '@/views/DashboardView.vue'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'

// Result of the next view_session_summary query; a pending promise keeps the view loading.
let nextResult: Promise<{ data: unknown; error: unknown }>

function makeQueryBuilder() {
  const builder: any = {
    select: vi.fn(() => builder),
    order: vi.fn(() => builder),
    in: vi.fn(() => builder),
    then: (resolve: any, reject: any) => nextResult.then(resolve, reject),
  }
  return builder
}

vi.mock('@/lib/supabase', () => ({
  supabase: { from: vi.fn(() => makeQueryBuilder()) },
}))

vi.mock('vue-toastification', () => ({
  useToast: () => ({ error: vi.fn(), success: vi.fn() }),
}))

const session = (id: string, status: string) => ({
  id,
  title: `Buổi ${id}`,
  status,
  session_date: '2026-09-14T11:00:00Z',
  total_intervals: 4,
  total_registrations: 8,
})

async function mountDashboard(isAdmin: boolean) {
  setActivePinia(createPinia())
  const authStore = useAuthStore()
  authStore.profile = isAdmin
    ? { id: 'a1', role: 'admin', display_name: 'Admin' }
    : ({ id: 'm1', role: 'member', display_name: 'Member' } as any)
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/:p(.*)*', component: { template: '<div />' } }],
  })
  router.push('/sessions')
  await router.isReady()
  const w = mount(DashboardView, { global: { plugins: [router] } })
  await flushPromises()
  return w
}

describe('DashboardView (I/O matrix: Sessions admin)', () => {
  beforeEach(() => {
    nextResult = Promise.resolve({ data: [], error: null })
  })

  it('admin: a Button Primary Default links to /create-session?from=sessions with a Plus icon', async () => {
    const w = await mountDashboard(true)
    const btn = w.get('a[data-ds="Button"]')
    expect(btn.attributes('href')).toBe('/create-session?from=sessions')
    expect(btn.attributes('data-ds-style')).toBe('Primary')
    expect(btn.attributes('data-ds-size')).toBe('Default')
    expect(btn.find('svg.lucide-plus').exists()).toBe(true)
  })

  it('non-admin: the create Button is absent', async () => {
    const w = await mountDashboard(false)
    expect(w.find('[data-ds="Button"]').exists()).toBe(false)
    expect(w.find('a[href="/create-session?from=sessions"]').exists()).toBe(false)
  })
})

describe('DashboardView (I/O matrix: Sessions states)', () => {
  it('loading: Spinner 48 Brand only', async () => {
    nextResult = new Promise(() => {})
    const w = await mountDashboard(true)
    const spinner = w.get('[data-ds="Spinner"]')
    expect(spinner.attributes('data-ds-size')).toBe('48')
    expect(spinner.attributes('data-ds-tone')).toBe('Brand')
    expect(w.find('[data-ds="Empty State"]').exists()).toBe(false)
    expect(w.find('[data-ds="Session Status Badge"]').exists()).toBe(false)
  })

  it('error: Alert Danger Box, with the empty state below it as today', async () => {
    nextResult = Promise.resolve({ data: null, error: new Error('boom') })
    const w = await mountDashboard(true)
    const alert = w.get('[data-ds="Alert"]')
    expect(alert.attributes('data-ds-tone')).toBe('Danger')
    expect(alert.attributes('data-ds-style')).toBe('Box')
    expect(alert.attributes('role')).toBe('alert')
    expect(alert.text()).toBe(useLangStore().t('dashboard.loadError'))
    expect(w.find('[data-ds="Spinner"]').exists()).toBe(false)
    // the error block is its own v-if; the loading/empty/list chain still runs
    expect(w.find('[data-ds="Empty State"]').exists()).toBe(true)
  })

  it('empty: Empty State Card', async () => {
    nextResult = Promise.resolve({ data: [], error: null })
    const w = await mountDashboard(true)
    const empty = w.get('[data-ds="Empty State"]')
    expect(empty.attributes('data-ds-style')).toBe('Card')
    expect(w.find('[data-ds="Alert"]').exists()).toBe(false)
    expect(w.find('[data-ds="Spinner"]').exists()).toBe(false)
  })

  it('list: Session Cards with a Session Status Badge each', async () => {
    nextResult = Promise.resolve({
      data: [session('s1', 'open'), session('s2', 'done')],
      error: null,
    })
    const w = await mountDashboard(true)
    const cards = w.findAll('a[href^="/session/"]')
    expect(cards).toHaveLength(2)
    expect(cards[0]!.attributes('href')).toBe('/session/s1')
    for (const card of cards) {
      expect(card.find('[data-ds="Session Status Badge"]').exists()).toBe(true)
    }
    expect(w.find('[data-ds="Empty State"]').exists()).toBe(false)
    expect(w.find('[data-ds="Spinner"]').exists()).toBe(false)
  })
})

describe('DashboardView (I/O matrix: Status map)', () => {
  it.each([
    ['open', 'Open', 'Info', 'Đang mở'],
    ['waiting_for_payment', 'Waiting For Payment', 'Warning', 'Chờ thu'],
    ['done', 'Done', 'Success', 'Hoàn tất'],
    ['cancelled', 'Cancelled', 'Neutral', 'Đã hủy'],
    ['something_else', 'Cancelled', 'Neutral', 'Đã hủy'],
  ])('%s -> %s', async (db, ds, tone, label) => {
    nextResult = Promise.resolve({ data: [session('s1', db)], error: null })
    const w = await mountDashboard(true)
    const badge = w.get('[data-ds="Session Status Badge"]')
    expect(badge.attributes('data-ds-status')).toBe(ds)
    expect(badge.get('[data-ds="Badge"]').attributes('data-ds-tone')).toBe(tone)
    expect(badge.text()).toBe(label)
  })
})
