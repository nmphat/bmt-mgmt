import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { reactive, ref } from 'vue'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createMemoryHistory } from 'vue-router'
import SettingsView from '@/views/SettingsView.vue'
import { useLangStore } from '@/stores/lang'
import type { BankConfig, ShuttleType } from '@/types'

const h = vi.hoisted(() => ({
  store: null as any,
  shuttle: null as any,
  toast: { error: vi.fn(), success: vi.fn() },
}))

vi.mock('@/lib/supabase', () => ({ supabase: {} }))
vi.mock('@/stores/bankConfig', () => ({ useBankConfigStore: () => h.store }))
vi.mock('@/composables/useShuttleTypes', () => ({ useShuttleTypes: () => h.shuttle }))
vi.mock('vue-toastification', () => ({ useToast: () => h.toast }))

const bank = (id: string, is_active: boolean): BankConfig => ({
  id,
  bank_id: `B${id}`,
  account_number: `100${id}`,
  account_name: `NAME ${id}`,
  template: 'compact2',
  is_active,
})
const shuttleType = (id: string, is_active: boolean): ShuttleType =>
  ({ id, name: `Type ${id}`, tube_price: 95000, per_tube: 12, is_active }) as ShuttleType

function setup(opts: { configs?: BankConfig[]; types?: ShuttleType[] } = {}) {
  h.store = reactive({
    configs: opts.configs ?? [],
    loading: false,
    fetchConfigs: vi.fn().mockResolvedValue(undefined),
    createConfig: vi.fn().mockResolvedValue(undefined),
    setDefault: vi.fn().mockResolvedValue(undefined),
    deleteConfig: vi.fn().mockResolvedValue(undefined),
  })
  h.shuttle = {
    types: ref(opts.types ?? []),
    loading: ref(false),
    fetchTypes: vi.fn().mockResolvedValue(undefined),
    addType: vi.fn().mockResolvedValue(undefined),
    toggleActive: vi.fn().mockResolvedValue(undefined),
  }
}

async function mountSettings() {
  setActivePinia(createPinia())
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/:p(.*)*', component: { template: '<div />' } }],
  })
  router.push('/settings')
  await router.isReady()
  const w = mount(SettingsView, { global: { plugins: [router] } })
  await flushPromises()
  return w
}

type W = Awaited<ReturnType<typeof mountSettings>>
const t = (key: string) => useLangStore().t(key)
const buttonByText = (w: W, text: string) => w.findAll('button').find((b) => b.text() === text)!
const bankSection = (w: W) => w.findAll('section')[0]!
const shuttleSection = (w: W) => w.findAll('section')[1]!
const bankRows = (w: W) => bankSection(w).findAll('div.px-5.py-4.border-b.border-line-subtle')
const shuttleRows = (w: W) => shuttleSection(w).findAll('div.px-5.py-4.border-b.border-line-subtle')

async function openBankForm(w: W) {
  await buttonByText(w, t('settings.addBank')).trigger('click')
  return bankSection(w).get('form')
}

async function fillBank(w: W, values: [string, string, string, string]) {
  const inputs = bankSection(w).get('form').findAll('input')
  for (const [i, v] of values.entries()) await inputs[i]!.setValue(v)
}

describe('SettingsView (I/O matrix)', () => {
  beforeEach(() => {
    h.toast.error.mockReset()
    h.toast.success.mockReset()
    setup()
  })
  afterEach(() => vi.restoreAllMocks())

  it('add bank: exact createConfig payload, is_active when no configs; Loading and disabled while saving; form closes', async () => {
    let resolve!: () => void
    h.store.createConfig.mockReturnValue(new Promise<void>((r) => (resolve = r)))
    const w = await mountSettings()
    const form = await openBankForm(w)
    await fillBank(w, ['TPB', '10003392871', 'CLB CAU LONG BMT', 'compact2'])
    await form.trigger('submit')
    expect(h.store.createConfig).toHaveBeenCalledWith({
      bank_id: 'TPB',
      account_number: '10003392871',
      account_name: 'CLB CAU LONG BMT',
      template: 'compact2',
      is_active: true,
    })
    const save = bankSection(w).get('button[type="submit"]')
    expect(save.attributes('data-ds')).toBe('Button')
    expect(save.attributes('data-ds-size')).toBe('Default')
    expect(save.attributes('data-ds-state')).toBe('Loading')
    expect(save.attributes('disabled')).toBeDefined()

    resolve()
    await flushPromises()
    expect(bankSection(w).find('form').exists()).toBe(false)
  })

  it('add bank: is_active false when configs exist', async () => {
    setup({ configs: [bank('1', true)] })
    const w = await mountSettings()
    const form = await openBankForm(w)
    await fillBank(w, ['MB', '123', 'NGUYEN VAN A', 'compact'])
    await form.trigger('submit')
    await flushPromises()
    expect(h.store.createConfig).toHaveBeenCalledWith({
      bank_id: 'MB',
      account_number: '123',
      account_name: 'NGUYEN VAN A',
      template: 'compact',
      is_active: false,
    })
  })

  it('add bank: the bank id and account name inputs keep the uppercase class', async () => {
    const w = await mountSettings()
    await openBankForm(w)
    const inputs = bankSection(w).get('form').findAll('input')
    expect(inputs.map((i) => i.classes().includes('uppercase'))).toEqual([true, false, true, false])
  })

  it('add bank, blank field: createConfig not called, requiredError toast', async () => {
    const w = await mountSettings()
    const form = await openBankForm(w)
    await fillBank(w, ['TPB', '   ', 'CLB', 'compact2'])
    await form.trigger('submit')
    await flushPromises()
    expect(h.store.createConfig).not.toHaveBeenCalled()
    expect(h.toast.error).toHaveBeenCalledWith(t('settings.requiredError'))
  })

  it.each([
    ['loading', { loading: true, configs: [] }, 'common.loading'],
    ['empty', { loading: false, configs: [] }, 'settings.noBanks'],
  ] as const)('bank list %s: Empty State Plain Left Small', async (_, state, key) => {
    const w = await mountSettings()
    Object.assign(h.store, state)
    await flushPromises()
    const empty = bankSection(w).get('[data-ds="Empty State"]')
    expect(empty.attributes('data-ds-style')).toBe('Plain')
    expect(empty.attributes('data-ds-align')).toBe('Left')
    expect(empty.attributes('data-ds-size')).toBe('Small')
    expect(empty.text()).toBe(t(key))
    expect(bankRows(w)).toHaveLength(0)
  })

  it('bank list: one row per config; the active row shows Badge Small Success inUse', async () => {
    setup({ configs: [bank('1', true), bank('2', false)] })
    const w = await mountSettings()
    const rows = bankRows(w)
    expect(rows).toHaveLength(2)
    expect(bankSection(w).find('[data-ds="Empty State"]').exists()).toBe(false)
    const badge = rows[0]!.get('[data-ds="Badge"]')
    expect(badge.attributes('data-ds-size')).toBe('Small')
    expect(badge.attributes('data-ds-tone')).toBe('Success')
    expect(badge.text()).toBe(t('settings.inUse'))
    expect(rows[1]!.find('[data-ds="Badge"]').exists()).toBe(false)
    expect(rows[0]!.text()).toContain('1001 · NAME 1')
  })

  it('row busy: toggle spinner and disabled, delete Icon Button disabled', async () => {
    setup({ configs: [bank('1', true), bank('2', false)] })
    h.store.setDefault.mockReturnValue(new Promise(() => {}))
    const w = await mountSettings()
    const toggle = () => bankRows(w)[1]!.get(`button[aria-label="${t('settings.setDefault')}"]`)
    const del = () => bankRows(w)[1]!.get('[data-ds="Icon Button"]')
    expect(toggle().attributes('disabled')).toBeUndefined()
    expect(del().attributes('disabled')).toBeUndefined()

    await toggle().trigger('click')
    expect(toggle().find('svg.animate-spin').exists()).toBe(true)
    expect(toggle().attributes('disabled')).toBeDefined()
    expect(del().attributes('disabled')).toBeDefined()
    // the other row is not busy
    expect(bankRows(w)[0]!.get('[data-ds="Icon Button"]').attributes('disabled')).toBeUndefined()
  })

  it('set default: setDefault(config.id)', async () => {
    setup({ configs: [bank('1', true), bank('2', false)] })
    const w = await mountSettings()
    await bankRows(w)[1]!
      .get(`button[aria-label="${t('settings.setDefault')}"]`)
      .trigger('click')
    await flushPromises()
    expect(h.store.setDefault).toHaveBeenCalledWith('2')
  })

  it('delete: Icon Button Small Square Ghost; deleteConfig(config) after confirm', async () => {
    setup({ configs: [bank('1', true)] })
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true)
    const w = await mountSettings()
    const del = bankRows(w)[0]!.get('[data-ds="Icon Button"]')
    expect(del.attributes('data-ds-size')).toBe('Small')
    expect(del.attributes('data-ds-shape')).toBe('Square')
    expect(del.attributes('data-ds-style')).toBe('Ghost')
    expect(del.attributes('aria-label')).toBe(t('settings.deleteBank'))
    expect(del.attributes('title')).toBe(t('settings.deleteBank'))
    await del.trigger('click')
    await flushPromises()
    expect(confirm).toHaveBeenCalledWith(t('settings.deleteConfirm'))
    expect(h.store.deleteConfig).toHaveBeenCalledWith(bank('1', true))
  })

  it('delete: confirm false does not call deleteConfig', async () => {
    setup({ configs: [bank('1', true)] })
    vi.spyOn(window, 'confirm').mockReturnValue(false)
    const w = await mountSettings()
    await bankRows(w)[0]!.get('[data-ds="Icon Button"]').trigger('click')
    await flushPromises()
    expect(h.store.deleteConfig).not.toHaveBeenCalled()
  })

  it('add shuttle: addType with numbers', async () => {
    const w = await mountSettings()
    await buttonByText(w, t('shuttle.addType')).trigger('click')
    const form = shuttleSection(w).get('form')
    const inputs = form.findAll('input')
    await inputs[0]!.setValue('Yonex AS-30')
    await inputs[1]!.setValue('95000')
    await inputs[2]!.setValue('12')
    await form.trigger('submit')
    await flushPromises()
    expect(h.shuttle.addType).toHaveBeenCalledWith({
      name: 'Yonex AS-30',
      tube_price: 95000,
      per_tube: 12,
      is_active: true,
    })
    const payload = h.shuttle.addType.mock.calls[0]![0]
    expect(typeof payload.tube_price).toBe('number')
    expect(typeof payload.per_tube).toBe('number')
    expect(shuttleSection(w).find('form').exists()).toBe(false)
  })

  it.each([
    ['loading', true, 'common.loading'],
    ['empty', false, 'shuttle.catalogEmpty'],
  ] as const)('shuttle list %s', async (_, loading, key) => {
    const w = await mountSettings()
    h.shuttle.loading.value = loading
    await flushPromises()
    const empty = shuttleSection(w).get('[data-ds="Empty State"]')
    expect(empty.attributes('data-ds-align')).toBe('Left')
    expect(empty.attributes('data-ds-size')).toBe('Small')
    expect(empty.text()).toBe(t(key))
  })

  it('shuttle list: rows; clicking the toggle calls toggleActive(st)', async () => {
    const types = [shuttleType('s1', true), shuttleType('s2', false)]
    setup({ types })
    const w = await mountSettings()
    const rows = shuttleRows(w)
    expect(rows).toHaveLength(2)
    expect(rows[0]!.get('button').attributes('aria-label')).toBe(t('shuttle.active'))
    expect(rows[1]!.get('button').attributes('aria-label')).toBe(t('shuttle.inactive'))
    await rows[1]!.get('button').trigger('click')
    await flushPromises()
    expect(h.shuttle.toggleActive).toHaveBeenCalledWith(types[1])
  })

  it('headers: Page Header Icon Title, Section Header Caps and Plain Title with Ghost actions', async () => {
    const w = await mountSettings()
    const page = w.get('[data-ds="Page Header"]')
    expect(page.attributes('data-ds-layout')).toBe('Icon Title')
    expect(page.get('h1').text()).toBe(t('settings.title'))
    const headers = w.findAll('[data-ds="Section Header"]')
    expect(headers.map((x) => x.attributes('data-ds-style'))).toEqual(['Caps', 'Plain Title'])
    for (const header of headers) {
      const action = header.get('[data-ds="Button"]')
      expect(action.attributes('data-ds-style')).toBe('Ghost')
      expect(action.attributes('type')).toBe('button')
    }
    const back = w.get('a[data-ds="Button"]')
    expect(back.attributes('href')).toBe('/')
    expect(back.text()).toBe(t('common.backToHome'))
  })
})
