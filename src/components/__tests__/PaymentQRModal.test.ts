import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import PaymentQRModal from '@/components/PaymentQRModal.vue'
import { useLangStore } from '@/stores/lang'
import type { CostSnapshot, GroupPaymentData } from '@/types'

// One Supabase chain per `from()` call; the record keeps the calls for exact assertions. `bank_config` resolves
// with one bank, every other table with `h.poll`.
const h = vi.hoisted(() => ({
  poll: { data: null, error: null } as any,
  chains: [] as { table: string; calls: { m: string; args: any[] }[] }[],
  toast: { error: vi.fn(), success: vi.fn(), info: vi.fn() },
}))

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn((table: string) => {
      const record = { table, calls: [] as { m: string; args: any[] }[] }
      h.chains.push(record)
      const result =
        table === 'bank_config'
          ? {
              data: [
                {
                  id: 'b1',
                  bank_id: 'tpb',
                  account_number: '123',
                  account_name: 'CLB',
                  template: 'compact2',
                  is_active: true,
                },
              ],
              error: null,
            }
          : h.poll
      const builder: any = {}
      for (const method of ['select', 'eq', 'order', 'in', 'single']) {
        builder[method] = vi.fn((...args: any[]) => {
          record.calls.push({ m: method, args })
          return builder
        })
      }
      builder.then = (resolve: any, reject: any) => Promise.resolve(result).then(resolve, reject)
      return builder
    }),
  },
}))
vi.mock('vue-toastification', () => ({ useToast: () => h.toast }))

const t = (key: string, params?: any) => useLangStore().t(key, params)
const norm = (s: string) => s.replace(/\s/g, ' ')
const money = (n: number) =>
  norm(new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(n))

const snapshot = {
  id: 'snap1',
  final_amount: 54000,
  paid_amount: 0,
  payment_code: 'CL8F3A21',
} as CostSnapshot
const group: GroupPaymentData = {
  group_code: 'GRP1',
  total_amount: 90000,
  snapshot_ids: ['s1', 's2'],
  member_count: 2,
  members: [
    { name: 'An', amount: 40000 },
    { name: 'Binh', amount: 50000 },
  ],
}

async function open(props: Record<string, any> = {}) {
  setActivePinia(createPinia())
  const w = mount(PaymentQRModal, {
    props: { show: false, snapshot, memberName: 'An', ...props },
  })
  await w.setProps({ show: true })
  await flushPromises()
  return w
}
const pollCalls = () => h.chains.filter((c) => c.table === 'session_costs_snapshot')

beforeEach(() => {
  vi.useFakeTimers()
  h.poll = { data: null, error: null }
  h.chains = []
  vi.clearAllMocks()
})
afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllGlobals()
})

describe('PaymentQRModal (I/O matrix)', () => {
  it('hidden: nothing rendered', () => {
    setActivePinia(createPinia())
    const w = mount(PaymentQRModal, { props: { show: false, snapshot, memberName: 'An' } })
    expect(w.html()).toBe('<!--v-if-->')
  })

  it('pending single: title, Amount Panel Brand, QR url, code card, note, Primary footer', async () => {
    const w = await open()
    expect(w.get('#modal-title').text()).toBe(t('payment.paymentFor', { name: 'An' }))
    expect(w.get('[data-ds="Modal Panel"]').attributes('data-ds-width')).toBe('lg')
    const panel = w.get('[data-ds="Amount Panel"]')
    expect(panel.attributes('data-ds-tone')).toBe('Brand')
    expect(w.get('[data-ds="Payment QR Body"]').attributes('data-ds-state')).toBe('Pending')
    expect(norm(panel.text())).toContain(money(54000))
    expect(w.get('[data-ds="QR Image"] img').attributes('src')).toBe(
      'https://img.vietqr.io/image/TPB-123-compact2.png?amount=54000&addInfo=CL8F3A21%20An',
    )
    const card = w.get('[data-ds="Transfer Code Card"]')
    expect(card.attributes('data-ds-style')).toBe('Modal')
    expect(card.text()).toContain('CL8F3A21 An')
    const note = w.get('[data-ds="Alert"]')
    expect(note.attributes('data-ds-tone')).toBe('Neutral')
    expect(note.attributes('data-ds-align')).toBe('Center')
    expect(note.text()).toBe(t('payment.qrStatusNote'))
    const footerBtn = w.get('[data-ds="Modal Footer"] [data-ds="Button"]')
    expect(footerBtn.attributes('data-ds-style')).toBe('Primary')
    expect(footerBtn.text()).toBe(t('payment.doneButton'))
  })

  it('poll paid: queries the snapshot, emits payment-complete, shows Result State and Success footer', async () => {
    h.poll = { data: { paid_amount: 54000, final_amount: 54000, status: 'paid' }, error: null }
    const w = await open()
    await vi.advanceTimersByTimeAsync(5000)
    await flushPromises()
    expect(pollCalls()[0]).toEqual({
      table: 'session_costs_snapshot',
      calls: [
        { m: 'select', args: ['paid_amount, final_amount, status'] },
        { m: 'eq', args: ['id', 'snap1'] },
        { m: 'single', args: [] },
      ],
    })
    expect(w.emitted('payment-complete')).toHaveLength(1)
    expect(w.get('[data-ds="Payment QR Body"]').attributes('data-ds-state')).toBe('Paid')
    expect(w.get('[data-ds="Result State"]').attributes('data-ds-style')).toBe('Circle')
    expect(w.get('[data-ds="Icon Tile"]').attributes('data-ds-style')).toBe('Success Circle')
    const footerBtn = w.get('[data-ds="Modal Footer"] [data-ds="Button"]')
    expect(footerBtn.attributes('data-ds-style')).toBe('Success')
    expect(footerBtn.text()).toBe(t('payment.confirmAndClose'))
  })

  it('poll error: stays pending', async () => {
    const log = vi.spyOn(console, 'error').mockImplementation(() => {})
    h.poll = { data: null, error: { message: 'down' } }
    const w = await open()
    await vi.advanceTimersByTimeAsync(5000)
    await flushPromises()
    expect(w.emitted('payment-complete')).toBeUndefined()
    expect(w.find('[data-ds="Result State"]').exists()).toBe(false)
    log.mockRestore()
  })

  it('group: title, Amount List Item Simple rows, poll by ids', async () => {
    h.poll = { data: [], error: null }
    const w = await open({ snapshot: null, groupData: group })
    expect(w.get('#modal-title').text()).toBe(t('payment.groupPaymentFor', { count: 2 }))
    const rows = w.findAll('[data-ds="Amount List Item"]')
    expect(rows).toHaveLength(2)
    expect(rows.every((r) => r.attributes('data-ds-style') === 'Simple')).toBe(true)
    await vi.advanceTimersByTimeAsync(5000)
    await flushPromises()
    expect(pollCalls()[0]).toEqual({
      table: 'session_costs_snapshot',
      calls: [
        { m: 'select', args: ['id, paid_amount, final_amount, status'] },
        { m: 'in', args: ['id', ['s1', 's2']] },
      ],
    })
  })

  it('copy: writes the transfer content and shows the Copied state', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    vi.stubGlobal('navigator', { clipboard: { writeText } })
    const w = await open()
    await w.get('[data-ds="Copy Button"]').trigger('click')
    await flushPromises()
    expect(writeText).toHaveBeenCalledWith('CL8F3A21 An')
    expect(w.get('[data-ds="Copy Button"]').attributes('data-ds-state')).toBe('Copied')
    expect(w.get('[data-ds="Transfer Code Card"]').attributes('data-ds-state')).toBe('Copied')
  })

  it('copy without a clipboard: error toast', async () => {
    vi.stubGlobal('navigator', {})
    const w = await open()
    await w.get('[data-ds="Copy Button"]').trigger('click')
    expect(h.toast.error).toHaveBeenCalledWith(t('payment.copyFailed'))
  })

  it('close: header X, scrim and footer each emit close', async () => {
    const w = await open()
    await w.get('[data-ds="Modal Header"] button').trigger('click')
    await w.get('[data-ds="Modal Scrim"]').trigger('click')
    await w.get('[data-ds="Modal Footer"] button').trigger('click')
    expect(w.emitted('close')).toHaveLength(3)
    expect(w.get('[data-ds="Modal Scrim"]').attributes('data-ds-style')).toBe('Default')
  })
})
