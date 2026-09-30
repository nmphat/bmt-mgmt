import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import SessionExtraCharges from '@/components/SessionExtraCharges.vue'
import { useLangStore } from '@/stores/lang'
import type { Member } from '@/types'

// One Supabase chain builder per `from()` call; each chain resolves with the next queued result (default: the
// charges list). The record keeps the chain for exact payload assertions.
const h = vi.hoisted(() => ({
  charges: [] as any[],
  queue: [] as any[],
  chains: [] as { table: string; calls: { m: string; args: any[] }[] }[],
  toast: { error: vi.fn(), success: vi.fn(), info: vi.fn() },
}))

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn((table: string) => {
      const record = { table, calls: [] as { m: string; args: any[] }[] }
      h.chains.push(record)
      const result = h.queue.length ? h.queue.shift() : { data: h.charges, error: null }
      const builder: any = {}
      for (const method of ['select', 'eq', 'order', 'insert', 'delete']) {
        builder[method] = vi.fn((...args: any[]) => {
          record.calls.push({ m: method, args })
          return builder
        })
      }
      builder.then = (resolve: any, reject: any) =>
        (result instanceof Promise ? result : Promise.resolve(result)).then(resolve, reject)
      return builder
    }),
  },
}))
vi.mock('vue-toastification', () => ({ useToast: () => h.toast }))

const t = (key: string) => useLangStore().t(key)

const members: Member[] = [
  { id: 'm1', display_name: 'An', role: 'member', is_active: true },
  { id: 'm2', display_name: 'Binh', role: 'member', is_active: true },
]
const charge = { id: 'c1', session_id: 's1', member_id: 'm1', amount: 20000, note: 'Nước' }
const refund = { id: 'c2', session_id: 's1', member_id: 'm2', amount: -5000, note: '' }
const FETCH_CALLS = [
  { m: 'select', args: ['*, member:members(display_name)'] },
  { m: 'eq', args: ['session_id', 's1'] },
  { m: 'order', args: ['created_at', { ascending: true }] },
]

async function mountCharges(props: { isAdmin?: boolean; isReadOnly?: boolean } = {}) {
  setActivePinia(createPinia())
  const w = mount(SessionExtraCharges, {
    props: { sessionId: 's1', members, isAdmin: true, isReadOnly: false, ...props },
  })
  await flushPromises()
  return w
}

type W = Awaited<ReturnType<typeof mountCharges>>
const addToggle = (w: W) =>
  w.findAll('[data-ds="Section Header"] button').find((b) => b.attributes('data-ds') === 'Button')

beforeEach(() => {
  h.charges = []
  h.queue = []
  h.chains = []
  vi.clearAllMocks()
})
afterEach(() => vi.unstubAllGlobals())

describe('SessionExtraCharges (I/O matrix)', () => {
  // Row: Extra fetch
  it('fetches the session charges on mount', async () => {
    await mountCharges()
    expect(h.chains).toEqual([{ table: 'session_extra_charges', calls: FETCH_CALLS }])
  })

  it('fetch error is logged and the list stays empty', async () => {
    const log = vi.spyOn(console, 'error').mockImplementation(() => {})
    h.queue.push({ data: null, error: { message: 'down' } })
    const w = await mountCharges()
    expect(log).toHaveBeenCalledWith('Error fetching extra charges:', { message: 'down' })
    expect(w.find('[data-ds="Extra Charge Item"]').exists()).toBe(false)
    expect(w.get('[data-ds="Empty State"]').text()).toBe(t('extraCharge.noCharges'))
    log.mockRestore()
  })

  // Row: Extra loading / empty
  it('pending: Spinner 32', async () => {
    h.queue.push(new Promise(() => {}))
    setActivePinia(createPinia())
    const w = mount(SessionExtraCharges, {
      props: { sessionId: 's1', members, isAdmin: true },
    })
    await flushPromises()
    expect(w.get('[data-ds="Spinner"]').attributes('data-ds-size')).toBe('32')
    expect(w.find('[data-ds="Empty State"]').exists()).toBe(false)
  })

  it('0 rows: Empty State Plain Center Small with the Receipt icon', async () => {
    const w = await mountCharges()
    const empty = w.get('[data-ds="Empty State"]')
    expect(empty.attributes('data-ds-style')).toBe('Plain')
    expect(empty.attributes('data-ds-align')).toBe('Center')
    expect(empty.attributes('data-ds-size')).toBe('Small')
    expect(empty.find('svg.lucide-receipt').exists()).toBe(true)
    expect(empty.text()).toBe(t('extraCharge.noCharges'))
    expect(w.find('[data-ds="Spinner"]').exists()).toBe(false)
  })

  // Row: Extra rows
  it('charge and refund: Item and Table Row Sign, tone and note or dash', async () => {
    h.charges = [
      { ...charge, member: { display_name: 'An' } },
      { ...refund, member: { display_name: 'Binh' } },
    ]
    const w = await mountCharges()

    const items = w.findAll('[data-ds="Extra Charge Item"]')
    expect(items.map((i) => i.attributes('data-ds-sign'))).toEqual(['Charge', 'Refund'])
    const itemAmounts = items.map((i) => i.get('span.font-bold'))
    expect(itemAmounts[0]!.classes()).toContain('text-fg-danger')
    expect(itemAmounts[0]!.text()).toMatch(/^\+20\.000/)
    expect(itemAmounts[1]!.classes()).toContain('text-fg-success')
    expect(itemAmounts[1]!.text()).toMatch(/^-5\.000/)
    expect(items[0]!.text()).toContain('Nước')

    const rows = w.findAll('tr[data-ds="Extra Charge Table Row"]')
    expect(rows.map((r) => r.attributes('data-ds-sign'))).toEqual(['Charge', 'Refund'])
    const cells = rows.map((r) => r.findAll('td'))
    expect(cells[0]![0]!.text()).toBe('An')
    expect(cells[0]![1]!.classes()).toContain('text-fg-danger')
    expect(cells[0]![1]!.text()).toMatch(/^\+20\.000/)
    expect(cells[0]![2]!.text()).toBe('Nước')
    expect(cells[1]![1]!.classes()).toContain('text-fg-success')
    expect(cells[1]![2]!.text()).toBe('—')
    for (const td of rows.flatMap((r) => r.findAll('td'))) {
      expect(td.classes()).toContain('whitespace-nowrap')
    }
  })

  // Row: Extra header
  it('admin: Ghost Button toggles the form between addCharge and close', async () => {
    const w = await mountCharges()
    const toggle = addToggle(w)!
    expect(toggle.attributes('data-ds-style')).toBe('Ghost')
    expect(toggle.text()).toBe(t('extraCharge.addCharge'))
    expect(toggle.attributes('aria-expanded')).toBe('false')
    expect(w.find('[data-ds="Extra Charge Form"]').exists()).toBe(false)

    await toggle.trigger('click')
    expect(addToggle(w)!.text()).toBe(t('common.close'))
    expect(addToggle(w)!.attributes('aria-expanded')).toBe('true')
    const forms = w.findAll('[data-ds="Extra Charge Form"]')
    expect(forms.map((f) => f.attributes('data-ds-viewport'))).toEqual(['Mobile', 'Desktop'])

    await addToggle(w)!.trigger('click')
    expect(w.find('[data-ds="Extra Charge Form"]').exists()).toBe(false)
  })

  it.each([
    { name: 'guest', props: { isAdmin: false } },
    { name: 'read only', props: { isAdmin: true, isReadOnly: true } },
  ])('$name: no add button and no delete', async ({ props }) => {
    h.charges = [{ ...charge, member: { display_name: 'An' } }]
    const w = await mountCharges(props)
    expect(addToggle(w)).toBeUndefined()
    expect(w.find(`button[aria-label="${t('common.delete')}"]`).exists()).toBe(false)
    expect(w.findAll('th')).toHaveLength(3)
  })

  // Row: Extra add
  it('add: inserts the charge, refetches, emits changed and closes the form', async () => {
    const w = await mountCharges()
    await addToggle(w)!.trigger('click')
    const form = w.get('form[data-ds-viewport="Desktop"]')
    const submit = form.get('button[type="submit"]')
    expect(submit.attributes('disabled')).toBeDefined()

    await form.get('select').setValue('m1')
    expect(submit.attributes('disabled')).toBeDefined() // amount still 0
    const [amount, note] = form.findAll('input')
    await amount!.setValue('20000')
    await note!.setValue('x')
    expect(submit.attributes('disabled')).toBeUndefined()

    h.queue.push({ data: null, error: null })
    await form.trigger('submit')
    await flushPromises()

    expect(h.chains[1]).toEqual({
      table: 'session_extra_charges',
      calls: [
        { m: 'insert', args: [{ session_id: 's1', member_id: 'm1', amount: 20000, note: 'x' }] },
      ],
    })
    expect(h.chains[2]).toEqual({ table: 'session_extra_charges', calls: FETCH_CALLS })
    expect(w.emitted('changed')).toEqual([[]])
    expect(w.find('[data-ds="Extra Charge Form"]').exists()).toBe(false)
  })

  it('add without a member keeps submit disabled', async () => {
    const w = await mountCharges()
    await addToggle(w)!.trigger('click')
    const form = w.get('form[data-ds-viewport="Mobile"]')
    await form.findAll('input')[0]!.setValue('20000')
    expect(form.get('button[type="submit"]').attributes('disabled')).toBeDefined()
  })

  it('add error shows a toast', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    const w = await mountCharges()
    await addToggle(w)!.trigger('click')
    const form = w.get('form[data-ds-viewport="Desktop"]')
    await form.get('select').setValue('m1')
    await form.findAll('input')[0]!.setValue('20000')
    h.queue.push({ data: null, error: { message: 'insert failed' } })
    await form.trigger('submit')
    await flushPromises()
    expect(h.toast.error).toHaveBeenCalledWith('insert failed')
    expect(w.emitted('changed')).toBeUndefined()
    vi.mocked(console.error).mockRestore()
  })

  // Row: Extra delete
  it('delete confirmed: deletes by id and emits changed', async () => {
    vi.stubGlobal(
      'confirm',
      vi.fn(() => true),
    )
    h.charges = [{ ...charge, member: { display_name: 'An' } }]
    const w = await mountCharges()
    const del = w.get(`tr button[aria-label="${t('common.delete')}"]`)
    expect(del.attributes('data-ds')).toBe('Icon Button')
    expect(del.attributes('data-ds-size')).toBe('Small')
    h.queue.push({ data: null, error: null })
    await del.trigger('click')
    await flushPromises()
    expect(confirm).toHaveBeenCalledWith(t('extraCharge.deleteConfirm'))
    expect(h.chains[1]).toEqual({
      table: 'session_extra_charges',
      calls: [
        { m: 'delete', args: [] },
        { m: 'eq', args: ['id', 'c1'] },
      ],
    })
    expect(w.emitted('changed')).toEqual([[]])
  })

  it('delete cancelled: no call', async () => {
    vi.stubGlobal(
      'confirm',
      vi.fn(() => false),
    )
    h.charges = [{ ...charge, member: { display_name: 'An' } }]
    const w = await mountCharges()
    await w.get(`[data-ds="Extra Charge Item"] button`).trigger('click')
    await flushPromises()
    expect(h.chains).toHaveLength(1)
    expect(w.emitted('changed')).toBeUndefined()
  })

  it('delete error shows a toast', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    vi.stubGlobal(
      'confirm',
      vi.fn(() => true),
    )
    h.charges = [{ ...charge, member: { display_name: 'An' } }]
    const w = await mountCharges()
    h.queue.push({ data: null, error: { message: 'delete failed' } })
    await w.get(`tr button[aria-label="${t('common.delete')}"]`).trigger('click')
    await flushPromises()
    expect(h.toast.error).toHaveBeenCalledWith('delete failed')
    expect(w.emitted('changed')).toBeUndefined()
    vi.mocked(console.error).mockRestore()
  })
})
