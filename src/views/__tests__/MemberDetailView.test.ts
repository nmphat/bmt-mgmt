import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createMemoryHistory } from 'vue-router'
import MemberDetailView from '@/views/MemberDetailView.vue'
import { useLangStore } from '@/stores/lang'

// One Supabase chain builder per `from()` call, keyed by table; `rpc` records its arguments.
const h = vi.hoisted(() => ({
  tables: {} as Record<string, any>,
  rpc: { data: null, error: null } as any,
  rpcCalls: [] as any[],
  toast: { error: vi.fn(), success: vi.fn(), info: vi.fn() },
}))

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn((table: string) => {
      const builder: any = {}
      for (const method of ['select', 'eq', 'order', 'in', 'single']) {
        builder[method] = vi.fn(() => builder)
      }
      builder.then = (resolve: any) => resolve(h.tables[table] ?? { data: null, error: null })
      return builder
    }),
    rpc: vi.fn((...args: any[]) => {
      h.rpcCalls.push(args)
      return Promise.resolve(h.rpc)
    }),
  },
}))
vi.mock('vue-toastification', () => ({ useToast: () => h.toast }))

// A render-function stub: the runtime-only Vue build cannot compile `template` strings.
vi.mock('@/components/PaymentQRModal.vue', async () => {
  const { h } = await import('vue')
  return {
    default: {
      name: 'PaymentQRModal',
      props: {
        show: Boolean,
        snapshot: { default: null },
        groupData: { default: null },
        memberName: { default: '' },
      },
      setup(props: any) {
        return () =>
          h('div', {
            'data-testid': 'payment-modal',
            'data-show': String(props.show),
            'data-snapshot': JSON.stringify(props.snapshot),
            'data-group': JSON.stringify(props.groupData),
            'data-member': String(props.memberName),
          })
      },
    },
  }
})

const t = (key: string, params?: Record<string, unknown>) => useLangStore().t(key, params as any)
const money = (value: number) =>
  new Intl.NumberFormat('vi-VN', {
    style: 'currency',
    currency: 'VND',
    maximumFractionDigits: 0,
  }).format(value)

const session = (over: Record<string, unknown> = {}) => ({
  snapshot_id: 's1',
  session_id: 'sess1',
  session_title: 'Buổi tối Thứ Tư',
  start_time: '2026-09-12T18:00:00.000Z',
  status: 'pending',
  final_amount: 120000,
  court_fee_amount: 100000,
  shuttle_fee_amount: 20000,
  paid_amount: 0,
  remaining_amount: 120000,
  payment_code: 'PC1',
  ...over,
})

// `debt` overrides the whole view_member_debt_summary response (e.g. a pending promise for the loading state).
function setup(opts: { debt?: any; debtTotal?: number; sessions?: any[] } = {}) {
  h.tables = {}
  h.tables['view_member_debt_summary'] =
    opts.debt ??
    ({ data: [{ display_name: 'An Nguyen', total_debt: opts.debtTotal ?? 0 }], error: null } as any)
  h.tables['view_member_session_details'] = { data: opts.sessions ?? [], error: null }
  h.tables['interval_presence'] = { data: [], error: null }
}

async function mountDetail() {
  setActivePinia(createPinia())
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/member/:id', component: { template: '<div />' } },
      { path: '/session/:id', component: { template: '<div />' } },
    ],
  })
  router.push('/member/m1')
  await router.isReady()
  const push = vi.spyOn(router, 'push')
  const back = vi.spyOn(router, 'back').mockImplementation(() => {})
  const w = mount(MemberDetailView, { global: { plugins: [router] } })
  await flushPromises()
  await flushPromises()
  return { w, push, back }
}

type W = Awaited<ReturnType<typeof mountDetail>>['w']
const debtCard = (w: W) => w.get('div.p-6.rounded-xl')
const amount = (w: W) => w.get('span.text-3xl')
const payAll = (w: W) => w.findAll('[data-ds="Button"]').find((b) => b.text() === t('debt.payAll'))
const modal = (w: W) => w.get('[data-testid="payment-modal"]')
const mobileItems = (w: W) => w.findAll('article[role="link"]')
const tableRows = (w: W) => w.findAll('tr[role="link"]')
const mobileQr = (w: W, i = 0) => mobileItems(w)[i]!.findAll('[data-ds="Button"]')[0]!
const showMore = (w: W) => w.get('[data-ds="Button"][data-ds-style="Outline Brand"]')

describe('MemberDetailView (I/O matrix)', () => {
  beforeEach(() => {
    h.tables = {}
    h.rpc = { data: null, error: null }
    h.rpcCalls = []
    h.toast.error.mockReset()
    h.toast.success.mockReset()
    h.toast.info.mockReset()
  })
  afterEach(() => vi.restoreAllMocks())

  // Row: Member detail header
  it('header: Page Header Back Title with the name and debt.history; back Icon Button calls router.back()', async () => {
    setup()
    const { w, back } = await mountDetail()
    const header = w.get('[data-ds="Page Header"]')
    expect(header.attributes('data-ds-layout')).toBe('Back Title')
    expect(header.get('h1').text()).toBe('An Nguyen')
    expect(header.get('p').text()).toBe(t('debt.history'))

    const iconBtn = header.get('[data-ds="Icon Button"]')
    expect(iconBtn.attributes('data-ds-size')).toBe('Default')
    expect(iconBtn.attributes('data-ds-shape')).toBe('Round')
    expect(iconBtn.attributes('data-ds-style')).toBe('Ghost')
    expect(iconBtn.attributes('type')).toBe('button')
    expect(iconBtn.attributes('aria-label')).toBe(t('common.back'))
    expect(iconBtn.find('svg.lucide-arrow-left').exists()).toBe(true)

    await iconBtn.trigger('click')
    expect(back).toHaveBeenCalledTimes(1)
  })

  // Row: Debt summary
  it.each([
    [120000, 'text-fg-danger', true],
    [0, 'text-fg-primary', false],
  ] as const)(
    'debt summary: total %i -> amount %s, Pay all button %s',
    async (total, cls, hasPayAll) => {
      setup({ debtTotal: total })
      const { w } = await mountDetail()
      const card = debtCard(w)
      expect(card.text()).toContain(t('debt.totalDebt'))
      expect(card.get('span').text()).toBe(t('debt.totalDebt'))
      const value = amount(w)
      expect(value.text()).toBe(money(total))
      expect(value.classes()).toContain(cls)

      const button = payAll(w)
      expect(!!button).toBe(hasPayAll)
      if (button) {
        expect(button.attributes('data-ds-size')).toBe('Default')
        expect(button.attributes('data-ds-style')).toBe('Primary')
        expect(button.attributes('aria-label')).toBe(`${t('debt.payAll')}: An Nguyen`)
        expect(button.find('svg.lucide-credit-card').exists()).toBe(true)
      }
    },
  )

  // Row: Pay all
  it('pay all: rpc create_group_payment with the unpaid ids and the modal opens with the group data', async () => {
    setup({
      debtTotal: 70000,
      sessions: [
        session({ snapshot_id: 'a', status: 'pending', remaining_amount: 50000 }),
        session({ snapshot_id: 'b', status: 'partial', remaining_amount: 20000 }),
        session({ snapshot_id: 'c', status: 'paid', remaining_amount: 0 }),
      ],
    })
    h.rpc = { data: { group_code: 'G1', total_amount: 70000 }, error: null }
    const { w } = await mountDetail()

    await payAll(w)!.trigger('click')
    await flushPromises()

    expect(h.rpcCalls.at(-1)).toEqual(['create_group_payment', { p_snapshot_ids: ['a', 'b'] }])
    expect(modal(w).attributes('data-show')).toBe('true')
    expect(JSON.parse(modal(w).attributes('data-snapshot')!)).toBe(null)
    expect(JSON.parse(modal(w).attributes('data-group')!)).toEqual({
      group_code: 'G1',
      total_amount: 70000,
      snapshot_ids: ['a', 'b'],
      member_count: 1,
      members: [{ name: 'An Nguyen', amount: 70000 }],
    })
    expect(modal(w).attributes('data-member')).toBe('An Nguyen')
  })

  it('pay all: rpc error -> toast.error with the message and no modal', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    setup({ debtTotal: 120000, sessions: [session()] })
    h.rpc = { data: null, error: new Error('boom') }
    const { w } = await mountDetail()
    expect(modal(w).attributes('data-show')).toBe('false')
    await payAll(w)!.trigger('click')
    await flushPromises()
    expect(h.toast.error).toHaveBeenCalledWith('boom')
    expect(modal(w).attributes('data-show')).toBe('false')
  })

  // Row: Session history
  it('session history loading: Spinner 32', async () => {
    setup({ debt: new Promise(() => {}) })
    const { w } = await mountDetail()
    expect(w.get('[data-ds="Spinner"]').attributes('data-ds-size')).toBe('32')
    expect(mobileItems(w)).toHaveLength(0)
    expect(tableRows(w)).toHaveLength(0)
  })

  it('session history empty: Empty State Plain Center with debt.emptyBody', async () => {
    setup({ sessions: [] })
    const { w } = await mountDetail()
    const empty = w.get('[data-ds="Empty State"]')
    expect(empty.attributes('data-ds-style')).toBe('Plain')
    expect(empty.attributes('data-ds-align')).toBe('Center')
    expect(empty.text()).toBe(t('debt.emptyBody'))
    expect(mobileItems(w)).toHaveLength(0)
    expect(tableRows(w)).toHaveLength(0)
  })

  it('session history: one item and one row per session, each with its Payment Status Badge', async () => {
    setup({
      sessions: [
        session({ snapshot_id: 'a', status: 'paid' }),
        session({ snapshot_id: 'b', status: 'partial' }),
        session({ snapshot_id: 'c', status: 'pending' }),
      ],
    })
    const { w } = await mountDetail()
    expect(mobileItems(w)).toHaveLength(3)
    expect(tableRows(w)).toHaveLength(3)

    const badges = w.findAll('[data-ds="Payment Status Badge"]')
    expect(badges).toHaveLength(6)
    expect(badges.map((b) => b.attributes('data-ds-status'))).toEqual([
      'Paid',
      'Partial',
      'Pending',
      'Paid',
      'Partial',
      'Pending',
    ])
    expect(badges.map((b) => b.text())).toEqual([
      t('payment.paid'),
      t('payment.partial'),
      t('payment.pending'),
      t('payment.paid'),
      t('payment.partial'),
      t('payment.pending'),
    ])

    const heads = w.findAll('[data-ds="Table Header Cell"]')
    expect(heads.map((x) => x.attributes('data-ds-align'))).toEqual([
      'Left',
      'Right',
      'Left',
      'Right',
      'Right',
      'Right',
      'Center',
      'Center',
    ])
    expect(heads.every((x) => x.attributes('data-ds-density') === 'Default')).toBe(true)
  })

  // Row: Session QR and open
  it('session QR: an unpaid item opens the modal with the snapshot and does not navigate', async () => {
    setup({ sessions: [session({ snapshot_id: 'a', session_id: 'sess1', status: 'pending' })] })
    const { w, push } = await mountDetail()
    await mobileQr(w).trigger('click')
    await flushPromises()
    expect(push).not.toHaveBeenCalled()
    expect(modal(w).attributes('data-show')).toBe('true')
    expect(JSON.parse(modal(w).attributes('data-snapshot')!)).toEqual({
      id: 'a',
      payment_code: 'PC1',
      final_amount: 120000,
      paid_amount: 0,
      member_id: 'm1',
    })
    expect(JSON.parse(modal(w).attributes('data-group')!)).toBe(null)
  })

  it('session QR: the desktop row QR opens the modal and does not navigate', async () => {
    setup({ sessions: [session({ snapshot_id: 'a', session_id: 'sess1', status: 'pending' })] })
    const { w, push } = await mountDetail()
    await tableRows(w)[0]!.get('[data-ds="Icon Button"]').trigger('click')
    await flushPromises()
    expect(push).not.toHaveBeenCalled()
    expect(modal(w).attributes('data-show')).toBe('true')
    expect(JSON.parse(modal(w).attributes('data-snapshot')!).id).toBe('a')
  })

  it('session open: click, Enter and Space on a mobile item push /session/<id>', async () => {
    setup({ sessions: [session({ snapshot_id: 'a', session_id: 'sess1' })] })
    const { w, push } = await mountDetail()
    const item = () => mobileItems(w)[0]!

    await item().trigger('click')
    expect(push).toHaveBeenCalledWith('/session/sess1')

    push.mockClear()
    await item().trigger('keydown', { key: 'Enter' })
    expect(push).toHaveBeenCalledWith('/session/sess1')

    push.mockClear()
    await item().trigger('keydown', { key: ' ' })
    expect(push).toHaveBeenCalledWith('/session/sess1')
  })

  it('session open: click, Enter and Space on a row push /session/<id>', async () => {
    setup({ sessions: [session({ snapshot_id: 'a', session_id: 'sess1' })] })
    const { w, push } = await mountDetail()
    const row = () => tableRows(w)[0]!

    expect(row().attributes('role')).toBe('link')
    expect(row().attributes('tabindex')).toBe('0')
    expect(row().attributes('aria-label')).toBe(
      t('dashboard.sessionCardAria', { title: 'Buổi tối Thứ Tư' }),
    )

    await row().trigger('click')
    expect(push).toHaveBeenCalledWith('/session/sess1')

    push.mockClear()
    await row().trigger('keydown', { key: 'Enter' })
    expect(push).toHaveBeenCalledWith('/session/sess1')

    push.mockClear()
    await row().trigger('keydown', { key: ' ' })
    expect(push).toHaveBeenCalledWith('/session/sess1')
  })

  it('session QR: a paid session has no QR control', async () => {
    setup({ sessions: [session({ status: 'paid' })] })
    const { w } = await mountDetail()
    expect(mobileItems(w)[0]!.findAll('[data-ds="Button"]')).toHaveLength(0)
    expect(tableRows(w)[0]!.find('[data-ds="Icon Button"]').exists()).toBe(false)
  })

  // Row: Mobile show more
  it('mobile show more: 4 items, then all, with showMoreSessions / showFewerSessions labels', async () => {
    setup({
      sessions: Array.from({ length: 6 }, (_, i) =>
        session({ snapshot_id: `s${i}`, session_id: `sess${i}` }),
      ),
    })
    const { w } = await mountDetail()
    expect(mobileItems(w)).toHaveLength(4)
    const button = showMore(w)
    expect(button.attributes('data-ds-size')).toBe('Default')
    expect(button.attributes('data-ds-style')).toBe('Outline Brand')
    expect(button.text()).toBe(t('debt.showMoreSessions', { count: 2 }))

    await button.trigger('click')
    expect(mobileItems(w)).toHaveLength(6)
    expect(showMore(w).text()).toBe(t('debt.showFewerSessions'))
  })

  it('mobile show more: no button with 4 or fewer sessions', async () => {
    setup({
      sessions: Array.from({ length: 4 }, (_, i) => session({ snapshot_id: `s${i}` })),
    })
    const { w } = await mountDetail()
    expect(mobileItems(w)).toHaveLength(4)
    expect(w.find('[data-ds="Button"][data-ds-style="Outline Brand"]').exists()).toBe(false)
  })
})
