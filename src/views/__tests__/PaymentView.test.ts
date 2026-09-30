import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createMemoryHistory } from 'vue-router'
import PaymentView from '@/views/PaymentView.vue'
import { useLangStore } from '@/stores/lang'

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn(() => {
      const builder: any = {}
      builder.select = vi.fn(() => builder)
      builder.order = vi.fn(() => builder)
      builder.then = (resolve: any) => Promise.resolve({ data: [], error: null }).then(resolve)
      return builder
    }),
  },
}))
vi.mock('vue-toastification', () => ({
  useToast: () => ({ error: vi.fn(), success: vi.fn() }),
}))

const t = (key: string, params?: any) => useLangStore().t(key, params)
const norm = (s: string) => s.replace(/\s/g, ' ')

async function mountPay(url: string) {
  setActivePinia(createPinia())
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/:p(.*)*', name: 'any', component: { template: '<div />' } }],
  })
  router.push(url)
  await router.isReady()
  const w = mount(PaymentView, { global: { plugins: [router] } })
  await flushPromises()
  return w
}

afterEach(() => vi.unstubAllGlobals())
beforeEach(() => vi.clearAllMocks())

describe('PaymentView (I/O matrix)', () => {
  it('renders the Payment Page Card with amount, code and QR', async () => {
    const w = await mountPay('/pay?code=BMT123&amount=150000')
    const card = w.get('[data-ds="Payment Page Card"]')
    expect(card.attributes('data-ds-style')).toBe('Default')
    expect(norm(w.get('[data-ds="Amount Panel"]').text())).toContain(
      norm(new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(150000)),
    )
    expect(w.get('[data-ds="Amount Panel"]').attributes('data-ds-style')).toBe('Hero')
    expect(w.get('[data-ds="Transfer Code Card"]').text()).toContain('BMT123')
    expect(w.get('[data-ds="QR Image"]').attributes('src')).toContain(
      'amount=150000&addInfo=BMT123',
    )
    expect(w.get('[data-ds="Waiting Pill"]').text()).toBe(t('payment.waitingTransfer'))
    expect(w.html()).not.toMatch(new RegExp('dark' + ':'))
  })

  it('copy: writes the code and shows the Copied state', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    vi.stubGlobal('navigator', { clipboard: { writeText } })
    const w = await mountPay('/pay?code=BMT123&amount=150000')
    const card = w.get('[data-ds="Transfer Code Card"]')
    expect(card.attributes('data-ds-state')).toBe('Default')
    await card.trigger('click')
    await flushPromises()
    expect(writeText).toHaveBeenCalledWith('BMT123')
    expect(w.get('[data-ds="Transfer Code Card"]').attributes('data-ds-state')).toBe('Copied')
    expect(w.get('[data-ds="Icon Tile"]').attributes('data-ds-style')).toBe('White Raised Done')
  })

  it('share: Button Large loading while sharing; a share error is logged', async () => {
    const log = vi.spyOn(console, 'error').mockImplementation(() => {})
    let fail: (e: Error) => void = () => {}
    vi.stubGlobal(
      'fetch',
      vi.fn(() => new Promise((_, reject) => (fail = reject))),
    )
    const w = await mountPay('/pay?code=BMT123&amount=150000')
    const share = w.get('[data-ds="Button"]')
    expect(share.attributes('data-ds-size')).toBe('Large')
    expect(share.attributes('data-ds-state')).toBe('Default')
    await share.trigger('click')
    expect(w.get('[data-ds="Button"]').attributes('data-ds-state')).toBe('Loading')
    expect(w.get('[data-ds="Button"]').attributes('disabled')).toBeDefined()
    fail(new Error('boom'))
    await flushPromises()
    expect(log).toHaveBeenCalledWith('Share failed:', expect.any(Error))
    expect(w.get('[data-ds="Button"]').attributes('data-ds-state')).toBe('Default')
    log.mockRestore()
  })

  it('empty route renders with 0 amount', async () => {
    const w = await mountPay('/pay')
    expect(norm(w.get('[data-ds="Amount Panel"]').text())).toContain('0')
    expect(w.get('[data-ds="Transfer Code Card"]').exists()).toBe(true)
  })
})
