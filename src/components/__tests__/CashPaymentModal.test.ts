import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import CashPaymentModal from '@/components/CashPaymentModal.vue'
import { useLangStore } from '@/stores/lang'

const h = vi.hoisted(() => ({
  rows: [] as any[],
  fetchError: null as any,
  fresh: {} as Record<string, any>,
  rpcError: {} as Record<string, any>,
  chains: [] as { table: string; calls: { m: string; args: any[] }[] }[],
  rpc: vi.fn(),
  toast: { error: vi.fn(), success: vi.fn(), info: vi.fn(), warning: vi.fn() },
}))

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn((table: string) => {
      const record = { table, calls: [] as { m: string; args: any[] }[] }
      h.chains.push(record)
      const builder: any = {}
      for (const method of ['select', 'eq', 'gt', 'order', 'single']) {
        builder[method] = vi.fn((...args: any[]) => {
          record.calls.push({ m: method, args })
          return builder
        })
      }
      builder.then = (resolve: any, reject: any) => {
        const id = record.calls.find((c) => c.m === 'eq' && c.args[0] === 'id')?.args[1]
        const result =
          table === 'view_member_session_details'
            ? { data: h.fetchError ? null : h.rows, error: h.fetchError }
            : { data: h.fresh[id], error: null }
        return Promise.resolve(result).then(resolve, reject)
      }
      return builder
    }),
    rpc: (...args: any[]) => h.rpc(...args),
  },
}))
vi.mock('vue-toastification', () => ({ useToast: () => h.toast }))

const t = (key: string, params?: any) => useLangStore().t(key, params)
const norm = (s: string) => s.replace(/\s/g, ' ')
const money = (n: number) =>
  norm(new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(n))

const rows = [
  {
    snapshot_id: 'a',
    session_title: 'Buổi A',
    start_time: '2026-09-01T10:00:00Z',
    remaining_amount: 50000,
  },
  {
    snapshot_id: 'b',
    session_title: 'Buổi B',
    start_time: '2026-09-08T10:00:00Z',
    remaining_amount: 30000,
  },
]

async function open(props: Record<string, any> = {}) {
  setActivePinia(createPinia())
  const w = mount(CashPaymentModal, {
    props: { show: false, memberId: 'm1', memberName: 'An', totalDebt: 80000, ...props },
  })
  await w.setProps({ show: true })
  await flushPromises()
  return w
}
const footerButtons = (w: any) => w.findAll('[data-ds="Modal Footer"] [data-ds="Button"]')

beforeEach(() => {
  h.rows = rows
  h.fetchError = null
  h.fresh = {
    a: { paid_amount: 0, final_amount: 50000 },
    b: { paid_amount: 0, final_amount: 30000 },
  }
  h.chains = []
  h.rpc.mockReset()
  h.rpc.mockResolvedValue({ error: null })
  vi.clearAllMocks()
})

describe('CashPaymentModal (I/O matrix)', () => {
  it('hidden: nothing rendered', () => {
    setActivePinia(createPinia())
    const w = mount(CashPaymentModal, {
      props: { show: false, memberId: 'm1', memberName: 'An', totalDebt: 0 },
    })
    expect(w.html()).toBe('<!--v-if-->')
  })

  it('fetch: exact query and Spinner Success while loading', async () => {
    setActivePinia(createPinia())
    const w = mount(CashPaymentModal, {
      props: { show: true, memberId: 'm1', memberName: 'An', totalDebt: 80000 },
    })
    const spinner = w.get('[data-ds="Spinner"]')
    expect(spinner.attributes('data-ds-tone')).toBe('Success')
    expect(w.get('[data-ds="Cash Payment Body"]').attributes('data-ds-step')).toBe('Loading')
    expect(spinner.attributes('data-ds-size')).toBe('32')
    await flushPromises()
    expect(h.chains).toEqual([
      {
        table: 'view_member_session_details',
        calls: [
          { m: 'select', args: ['snapshot_id, session_title, start_time, remaining_amount'] },
          { m: 'eq', args: ['member_id', 'm1'] },
          { m: 'gt', args: ['remaining_amount', 0] },
          { m: 'order', args: ['start_time', { ascending: true }] },
        ],
      },
    ])
    expect(w.find('[data-ds="Spinner"]').exists()).toBe(false)
  })

  it('fetch error: error toast', async () => {
    const log = vi.spyOn(console, 'error').mockImplementation(() => {})
    h.fetchError = { message: 'down' }
    await open()
    expect(h.toast.error).toHaveBeenCalledWith(t('toast.error', { message: 'down' }))
    log.mockRestore()
  })

  it('empty: Empty State Plain and confirm disabled', async () => {
    h.rows = []
    const w = await open({ totalDebt: 0 })
    const empty = w.get('[data-ds="Empty State"]')
    expect(empty.attributes('data-ds-style')).toBe('Plain')
    expect(w.get('[data-ds="Cash Payment Body"]').attributes('data-ds-step')).toBe('Empty')
    expect(empty.text()).toBe(t('debt.noDebt'))
    expect(footerButtons(w)[0].attributes('disabled')).toBeDefined()
  })

  it('preview: amount = total debt, Allocation rows, blur clamps', async () => {
    const w = await open()
    expect(w.get('#cash-payment-title').text()).toBe(t('payment.manualTitle'))
    expect(w.get('[data-ds="Modal Panel"]').attributes('data-ds-width')).toBe('md')
    expect(w.get('[data-ds="Alert"]').attributes('data-ds-tone')).toBe('Success')
    expect(norm(w.get('[data-ds="Alert"]').text())).toContain(money(80000))
    expect(w.get('[data-ds="Cash Payment Body"]').attributes('data-ds-step')).toBeUndefined()
    const input = w.get('input[type="number"]')
    expect((input.element as HTMLInputElement).value).toBe('80000')
    expect(input.attributes('max')).toBe('80000')
    const items = w.findAll('[data-ds="Amount List Item"]')
    expect(items).toHaveLength(2)
    expect(items.every((i) => i.attributes('data-ds-style') === 'Allocation')).toBe(true)
    await input.setValue('999999')
    await input.trigger('blur')
    expect((input.element as HTMLInputElement).value).toBe('80000')
    await input.setValue('-5')
    await input.trigger('blur')
    expect((input.element as HTMLInputElement).value).toBe('0')
    expect(footerButtons(w)[0].attributes('disabled')).toBeDefined()
  })

  it('confirm: Result State Plain, Back with ArrowLeft, per-row re-fetch and rpc, emits success and close', async () => {
    const w = await open()
    expect(footerButtons(w)[0].attributes('data-ds-style')).toBe('Success')
    await footerButtons(w)[0].trigger('click')
    expect(w.get('#cash-payment-title').text()).toBe(t('payment.cashAllocationTitle'))
    expect(w.get('[data-ds="Cash Payment Body"]').attributes('data-ds-step')).toBe('Confirm')
    expect(w.get('[data-ds="Result State"]').attributes('data-ds-style')).toBe('Plain')
    const [back, confirm] = footerButtons(w)
    expect(back.attributes('data-ds-style')).toBe('Secondary')
    expect(back.find('svg.lucide-arrow-left').exists()).toBe(true)
    expect(back.find('svg.lucide-triangle-alert').exists()).toBe(false)
    expect(back.text()).toBe(t('common.back'))
    h.chains = []
    await confirm.trigger('click')
    await flushPromises()
    expect(h.chains).toEqual(
      ['a', 'b'].map((id) => ({
        table: 'session_costs_snapshot',
        calls: [
          { m: 'select', args: ['paid_amount, final_amount'] },
          { m: 'eq', args: ['id', id] },
          { m: 'single', args: [] },
        ],
      })),
    )
    expect(h.rpc.mock.calls).toEqual([
      ['add_manual_payment', { p_snapshot_id: 'a', p_amount: 50000, p_note: t('payment.cash') }],
      ['add_manual_payment', { p_snapshot_id: 'b', p_amount: 30000, p_note: t('payment.cash') }],
    ])
    expect(w.emitted('success')).toHaveLength(1)
    expect(w.emitted('close')).toHaveLength(1)
  })

  it('rpc error: partial warning toast', async () => {
    h.rpc.mockResolvedValueOnce({ error: { message: 'x' } })
    const w = await open()
    await footerButtons(w)[0].trigger('click')
    await footerButtons(w)[1].trigger('click')
    await flushPromises()
    expect(h.toast.warning).toHaveBeenCalledWith(
      t('payment.cashPaymentPartial', { success: 1, total: 2, error: 1 }),
    )
  })

  it('close: header X emits close; while submitting the header close is Disabled and nothing emits', async () => {
    const w = await open()
    expect(w.get('[data-ds="Modal Header"]').attributes('data-ds-close')).toBe('Default')
    expect(w.get('[data-ds="Modal Header"] button').attributes('aria-label')).toBe(
      t('common.cancel'),
    )
    await w.get('[data-ds="Modal Header"] button').trigger('click')
    expect(w.emitted('close')).toHaveLength(1)

    let release: (v: any) => void = () => {}
    h.rpc.mockReturnValue(new Promise((r) => (release = r)))
    await footerButtons(w)[0].trigger('click')
    await footerButtons(w)[1].trigger('click')
    await flushPromises()
    expect(w.get('[data-ds="Modal Header"]').attributes('data-ds-close')).toBe('Disabled')
    await w.get('[data-ds="Modal Scrim"]').trigger('click')
    expect(w.emitted('close')).toHaveLength(1)
    release({ error: null })
    await flushPromises()
  })
})
