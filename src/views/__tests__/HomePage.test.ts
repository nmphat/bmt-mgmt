import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createMemoryHistory } from 'vue-router'
import HomePage from '@/views/HomePage.vue'
import HomeDebtTable from '@/components/HomeDebtTable.vue'
import { useLangStore } from '@/stores/lang'

// One Supabase chain builder per `from()` call; each takes the next queued result (else `h.result`) and the record
// keeps the chain for exact payload assertions.
const h = vi.hoisted(() => ({
  result: { data: [], count: 0, error: null } as any,
  queue: [] as any[],
  chains: [] as { table: string; calls: { m: string; args: any[] }[] }[],
  rpc: vi.fn(),
  toast: { error: vi.fn(), success: vi.fn(), info: vi.fn() },
}))

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn((table: string) => {
      const record = { table, calls: [] as { m: string; args: any[] }[] }
      h.chains.push(record)
      const result = h.queue.length ? h.queue.shift() : h.result
      const builder: any = {}
      for (const method of ['select', 'eq', 'order', 'ilike', 'range', 'in', 'neq']) {
        builder[method] = vi.fn((...args: any[]) => {
          record.calls.push({ m: method, args })
          return builder
        })
      }
      builder.then = (resolve: any) => resolve(result)
      return builder
    }),
    rpc: (...args: any[]) => h.rpc(...args),
  },
}))
vi.mock('vue-toastification', () => ({ useToast: () => h.toast }))

const t = (key: string, params?: Record<string, unknown>) => useLangStore().t(key, params as any)

const countChain = (search?: string) => ({
  table: 'view_member_debt_summary',
  calls: [
    { m: 'select', args: ['*', { count: 'exact', head: true }] },
    ...(search ? [{ m: 'ilike', args: ['display_name', `%${search}%`] }] : []),
  ],
})
const dataChain = (search?: string) => ({
  table: 'view_member_debt_summary',
  calls: [
    { m: 'select', args: ['*'] },
    { m: 'order', args: ['total_debt', { ascending: false }] },
    ...(search ? [{ m: 'ilike', args: ['display_name', `%${search}%`] }] : []),
    { m: 'range', args: [0, 19] },
  ],
})

async function mountHome() {
  setActivePinia(createPinia())
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: { template: '<div />' } },
      { path: '/member/:id', component: { template: '<div />' } },
    ],
  })
  router.push('/')
  await router.isReady()
  const w = mount(HomePage, {
    global: {
      plugins: [router],
      stubs: { PaymentQRModal: true, CashPaymentModal: true },
    },
  })
  await flushPromises()
  return { w }
}

describe('HomePage (I/O matrix)', () => {
  beforeEach(() => {
    h.result = { data: [], count: 0, error: null }
    h.queue = []
    h.chains = []
    h.rpc.mockReset()
    h.toast.error.mockReset()
    h.toast.info.mockReset()
  })
  afterEach(() => vi.restoreAllMocks())

  // Row: Home fetch
  it('fetch: count chain then data chain; a search adds ilike to both', async () => {
    const { w } = await mountHome()
    expect(h.chains).toEqual([countChain(), dataChain()])
    h.chains = []
    w.getComponent(HomeDebtTable).vm.$emit('update:search', 'an')
    await flushPromises()
    expect(h.chains).toEqual([countChain('an'), dataChain('an')])
  })

  it('fetch error: Alert Danger with debt.errorState and toast.error', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    h.result = { data: null, count: null, error: { message: 'x' } }
    const { w } = await mountHome()
    const alert = w.get('[data-ds="Alert"]')
    expect(alert.attributes('data-ds-tone')).toBe('Danger')
    expect(alert.text()).toBe(t('debt.errorState'))
    expect(h.toast.error).toHaveBeenCalledWith(t('debt.errorState'))
  })

  // Row: Home header
  it('header: Page Header Title with debt.title as h1', async () => {
    const { w } = await mountHome()
    const header = w.get('[data-ds="Page Header"]')
    expect(header.attributes('data-ds-layout')).toBe('Title')
    expect(header.classes()).toContain('mb-6')
    expect(header.get('h1').text()).toBe(t('debt.title'))
  })

  // Row: Pay single (HomePage)
  it('pay single: unpaid snapshots of the member, then create_group_payment with their ids', async () => {
    vi.spyOn(console, 'log').mockImplementation(() => {})
    const { w } = await mountHome()
    h.chains = []
    h.queue = [
      {
        data: [
          {
            id: 's1',
            final_amount: 30000,
            paid_amount: 0,
            member_id: 'm1',
            members: { display_name: 'an' },
          },
          {
            id: 's2',
            final_amount: 24000,
            paid_amount: 0,
            member_id: 'm1',
            members: { display_name: 'an' },
          },
        ],
        error: null,
      },
    ]
    h.rpc.mockResolvedValue({ data: { group_code: 'G1', total_amount: 54000 }, error: null })
    w.getComponent(HomeDebtTable).vm.$emit('pay-single', 'm1')
    await flushPromises()
    expect(h.chains).toHaveLength(1)
    const chain = h.chains[0]!
    expect(chain.table).toBe('session_costs_snapshot')
    expect(chain.calls.map((c) => c.m)).toEqual(['select', 'in', 'neq'])
    expect(chain.calls[0]!.args).toHaveLength(1)
    expect(chain.calls[0]!.args[0].replace(/\s+/g, ' ').trim()).toBe(
      'id, final_amount, paid_amount, member_id, members ( display_name )',
    )
    expect(chain.calls[1]!.args).toEqual(['member_id', ['m1']])
    expect(chain.calls[2]!.args).toEqual(['status', 'paid'])
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.rpc).toHaveBeenCalledWith('create_group_payment', { p_snapshot_ids: ['s1', 's2'] })
  })

  it('pay single with no unpaid rows: toast.info(debt.noDebt), rpc not called', async () => {
    const { w } = await mountHome()
    h.queue = [{ data: [], error: null }]
    w.getComponent(HomeDebtTable).vm.$emit('pay-single', 'm1')
    await flushPromises()
    expect(h.toast.info).toHaveBeenCalledWith(t('debt.noDebt'))
    expect(h.rpc).not.toHaveBeenCalled()
  })
})
