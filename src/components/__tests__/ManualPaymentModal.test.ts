import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import ManualPaymentModal from '@/components/ManualPaymentModal.vue'
import { useLangStore } from '@/stores/lang'
import type { CostSnapshot } from '@/types'

const h = vi.hoisted(() => ({
  rpc: vi.fn(),
  toast: { error: vi.fn(), success: vi.fn(), info: vi.fn() },
}))

vi.mock('@/lib/supabase', () => ({ supabase: { rpc: (...a: any[]) => h.rpc(...a) } }))
vi.mock('vue-toastification', () => ({ useToast: () => h.toast }))

const t = (key: string, params?: any) => useLangStore().t(key, params)
const norm = (s: string) => s.replace(/\s/g, ' ')
const money = (n: number) =>
  norm(new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(n))

const snapshot = { id: 'snap1', final_amount: 54000, paid_amount: 0 } as CostSnapshot

async function open(props: Record<string, any> = {}) {
  setActivePinia(createPinia())
  const w = mount(ManualPaymentModal, {
    props: { show: false, snapshot, memberName: 'An', ...props },
  })
  await w.setProps({ show: true })
  await flushPromises()
  return w
}
const footerButtons = (w: any) => w.findAll('[data-ds="Modal Footer"] [data-ds="Button"]')

beforeEach(() => {
  h.rpc.mockReset()
  h.rpc.mockResolvedValue({ error: null })
  vi.clearAllMocks()
})

describe('ManualPaymentModal (I/O matrix)', () => {
  it('hidden: nothing rendered', () => {
    setActivePinia(createPinia())
    const w = mount(ManualPaymentModal, { props: { show: false, snapshot: null, memberName: '' } })
    expect(w.html()).toBe('<!--v-if-->')
  })

  it('entry: Alert Info, Read-only Field, Amount Panel Warning, amount and note inputs', async () => {
    const w = await open()
    expect(w.get('#manual-payment-title').text()).toBe(t('payment.manualTitle'))
    const alerts = w.findAll('[data-ds="Alert"]')
    expect(alerts).toHaveLength(1)
    expect(alerts[0]!.attributes('data-ds-tone')).toBe('Info')
    expect(alerts[0]!.html()).toContain(t('payment.amountReceived', { name: 'An' }))
    expect(w.get('[data-ds="Read-only Field"]').text()).toBe('An')
    const panel = w.get('[data-ds="Amount Panel"]')
    expect(panel.attributes('data-ds-tone')).toBe('Warning')
    expect(w.get('[data-ds="Manual Payment Body"]').attributes('data-ds-step')).toBe('Entry')
    expect(w.get('[data-ds="Read-only Field"]').attributes('data-ds-size')).toBe('Default')
    expect(norm(panel.text())).toContain(money(54000))
    const amount = w.get('input#amount')
    expect((amount.element as HTMLInputElement).value).toBe('54000')
    expect(amount.attributes('step')).toBe('1000')
    expect(amount.attributes('min')).toBe('0')
    expect(w.get('input#amount').element.closest('[data-ds="Input"]')!.textContent).toContain('₫')
    expect((w.get('input#note').element as HTMLInputElement).value).toBe(t('payment.cash'))
    expect(w.get('label[for="amount"]').text()).toBe(t('payment.amountCollected'))
  })

  it('amount 0 then confirm: positive-amount error toast, stays on entry', async () => {
    const w = await open()
    await w.get('input#amount').setValue('0')
    await footerButtons(w)[0].trigger('click')
    expect(h.toast.error).toHaveBeenCalledWith(t('payment.amountPositiveError'))
    expect(w.find('input#amount').exists()).toBe(true)
  })

  it('review via Enter: Alert Warning and four Key Value Rows; confirm calls the rpc', async () => {
    const w = await open()
    await w.get('input#amount').trigger('keyup.enter')
    expect(w.get('#manual-payment-title').text()).toBe(t('payment.cashReviewTitle'))
    expect(w.get('[data-ds="Alert"]').attributes('data-ds-tone')).toBe('Warning')
    const rows = w.findAll('[data-ds="Key Value Row"]')
    expect(rows.map((r) => r.attributes('data-ds-value-tone'))).toEqual([
      'Primary',
      'Brand',
      'Primary',
      'Regular',
    ])
    expect(w.get('[data-ds="Manual Payment Body"]').attributes('data-ds-step')).toBe('Review')
    expect(
      rows.every(
        (r) =>
          r.attributes('data-ds-layout') === 'Inline Divided' &&
          r.attributes('data-ds-tone') === 'Neutral' &&
          r.attributes('data-ds-align') === 'Left' &&
          r.attributes('data-ds-style') === undefined,
      ),
    ).toBe(true)
    expect(rows[3]!.text()).toContain('Tiền mặt')

    const [confirm] = footerButtons(w)
    expect(confirm.attributes('data-ds-style')).toBe('Success')
    await confirm.trigger('click')
    await flushPromises()
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.rpc).toHaveBeenCalledWith('add_manual_payment', {
      p_snapshot_id: 'snap1',
      p_amount: 54000,
      p_note: 'Tiền mặt',
    })
    expect(w.emitted('success')).toHaveLength(1)
    expect(w.emitted('close')).toHaveLength(1)
  })

  it('review: Back returns to entry', async () => {
    const w = await open()
    await footerButtons(w)[0].trigger('click')
    const back = footerButtons(w)[1]
    expect(back.attributes('data-ds-style')).toBe('Secondary')
    expect(back.find('svg.lucide-arrow-left').exists()).toBe(true)
    expect(back.text()).toBe(t('payment.backToEdit'))
    await back.trigger('click')
    expect(w.find('input#amount').exists()).toBe(true)
  })

  it('rpc error: error toast, no success', async () => {
    const log = vi.spyOn(console, 'error').mockImplementation(() => {})
    h.rpc.mockResolvedValue({ error: { message: 'nope' } })
    const w = await open()
    await footerButtons(w)[0].trigger('click')
    await footerButtons(w)[0].trigger('click')
    await flushPromises()
    expect(h.toast.error).toHaveBeenCalledWith(t('toast.error', { message: 'nope' }))
    expect(w.emitted('success')).toBeUndefined()
    log.mockRestore()
  })

  it('close: Cancel and X emit close; Disabled header while submitting', async () => {
    const w = await open()
    expect(w.get('[data-ds="Modal Header"]').attributes('data-ds-close')).toBe('Default')
    expect(w.get('[data-ds="Modal Footer"]').attributes('data-ds-background')).toBe('Gray')
    expect(footerButtons(w)[1].text()).toBe(t('common.cancel'))
    await footerButtons(w)[1].trigger('click')
    await w.get('[data-ds="Modal Header"] button').trigger('click')
    expect(w.emitted('close')).toHaveLength(2)

    let release: (v: any) => void = () => {}
    h.rpc.mockReturnValue(new Promise((r) => (release = r)))
    await footerButtons(w)[0].trigger('click')
    await footerButtons(w)[0].trigger('click')
    await flushPromises()
    expect(w.get('[data-ds="Modal Header"]').attributes('data-ds-close')).toBe('Disabled')
    await w.get('[data-ds="Modal Scrim"]').trigger('click')
    expect(w.emitted('close')).toHaveLength(2)
    release({ error: null })
    await flushPromises()
  })
})
