import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createMemoryHistory } from 'vue-router'
import ShuttleUsageEditor from '@/components/session/ShuttleUsageEditor.vue'
import { supabase } from '@/lib/supabase'
import { useLangStore } from '@/stores/lang'
import type { ShuttleUsageEntry } from '@/types'

const catalogue = [
  { id: 'a', name: 'Vina', tube_price: 315000, per_tube: 12, is_active: true },
  { id: 'b', name: 'Victor', tube_price: 360000, per_tube: 12, is_active: true },
]

// Per-test catalogue state; reset in beforeEach so the original tests see the two active types.
const h = vi.hoisted(() => ({
  types: [] as any[],
  fetchError: false,
  toast: { error: vi.fn(), success: vi.fn(), info: vi.fn() },
}))

vi.mock('@/composables/useShuttleTypes', async () => {
  const { ref } = await import('vue')
  return {
    useShuttleTypes: () => ({
      activeTypes: ref(h.types),
      loading: ref(false),
      fetchTypes: vi.fn(() =>
        h.fetchError ? Promise.reject(new Error('boom')) : Promise.resolve(undefined),
      ),
    }),
  }
})

vi.mock('@/lib/supabase', () => ({
  supabase: { rpc: vi.fn().mockResolvedValue({ data: null, error: null }) },
}))
vi.mock('vue-toastification', () => ({ useToast: () => h.toast }))

beforeEach(() => {
  h.types = catalogue
  h.fetchError = false
  vi.clearAllMocks()
})

const t = (key: string) => useLangStore().t(key)

const usage: ShuttleUsageEntry[] = [
  { type_id: 'a', name: 'Vina', tube_price: 315000, per_tube: 12, used: 3 },
]

async function mountEditor(u = usage, disabled = false) {
  setActivePinia(createPinia())
  const w = mount(ShuttleUsageEditor, {
    props: { sessionId: 's1', usage: u, disabled },
  })
  await flushPromises()
  return w
}

describe('ShuttleUsageEditor', () => {
  it('shows the running total', async () => {
    const w = await mountEditor()
    expect(w.get('[data-testid="shuttle-total"]').text()).toContain('78.750')
  })

  it('increments the count with the plus stepper', async () => {
    const w = await mountEditor()
    await w.get('[data-testid="inc-0"]').trigger('click')
    expect(w.get('[data-testid="shuttle-total"]').text()).toContain('105.000')
  })

  it('never goes below zero', async () => {
    const w = await mountEditor([{ ...usage[0]!, used: 0 }])
    await w.get('[data-testid="dec-0"]').trigger('click')
    expect(w.get('[data-testid="used-0"]').attributes('value')).toBe('0')
  })

  it('falls back to 0 instead of NaN on a non-numeric used input', async () => {
    const w = await mountEditor()
    const input = w.get('[data-testid="used-0"]')
    ;(input.element as HTMLInputElement).value = '12abc'
    await input.trigger('change')
    expect(w.get('[data-testid="used-0"]').attributes('value')).toBe('0')
  })

  it('steppers recover from an already-NaN used value instead of propagating it', async () => {
    const w = await mountEditor([{ ...usage[0]!, used: NaN }])
    await w.get('[data-testid="inc-0"]').trigger('click')
    expect(w.get('[data-testid="used-0"]').attributes('value')).toBe('1')

    const w2 = await mountEditor([{ ...usage[0]!, used: NaN }])
    await w2.get('[data-testid="dec-0"]').trigger('click')
    expect(w2.get('[data-testid="used-0"]').attributes('value')).toBe('0')
  })

  it('shows an empty state when nothing is recorded', async () => {
    const w = await mountEditor([])
    expect(w.text()).toContain('Chưa nhập cầu nào')
  })

  it('adds a row when clicking add', async () => {
    const w = await mountEditor([])
    await w.get('[data-testid="add-row"]').trigger('click')
    expect(w.findAll('[data-testid^="used-"]')).toHaveLength(1)
  })

  it('picks up usage that arrives after mount, once the parent fetch fills it in', async () => {
    const w = await mountEditor([])
    expect(w.text()).toContain('Chưa nhập cầu nào')
    expect(w.get('[data-testid="shuttle-total"]').text()).toContain('0')

    await w.setProps({ usage })
    await flushPromises()

    expect(w.get('[data-testid="used-0"]').attributes('value')).toBe('3')
    expect(w.get('[data-testid="shuttle-total"]').text()).toContain('78.750')
  })
})

describe('ShuttleUsageEditor (I/O matrix)', () => {
  // Row: Shuttle stepper
  it('stepper State is Min at 0, Default at 3 and Disabled when disabled; dec is disabled at 0', async () => {
    const zero = await mountEditor([{ ...usage[0]!, used: 0 }])
    expect(zero.get('[data-ds="Stepper"]').attributes('data-ds-state')).toBe('Min')
    expect(zero.get('[data-testid="dec-0"]').attributes('disabled')).toBeDefined()
    expect(zero.get('[data-testid="inc-0"]').attributes('disabled')).toBeUndefined()

    const three = await mountEditor()
    expect(three.get('[data-ds="Stepper"]').attributes('data-ds-state')).toBe('Default')
    expect(three.get('[data-testid="dec-0"]').attributes('disabled')).toBeUndefined()
    expect(three.get('[data-testid="dec-0"]').attributes('aria-label')).toBe(t('shuttle.decrease'))
    expect(three.get('[data-testid="inc-0"]').attributes('aria-label')).toBe(t('shuttle.increase'))

    const off = await mountEditor(usage, true)
    expect(off.get('[data-ds="Stepper"]').attributes('data-ds-state')).toBe('Disabled')
    expect(off.get('[data-testid="dec-0"]').attributes('disabled')).toBeDefined()
    expect(off.get('[data-testid="inc-0"]').attributes('disabled')).toBeDefined()
    expect(off.get('[data-testid="used-0"]').attributes('disabled')).toBeDefined()
  })

  // Row: Shuttle remove
  it('remove is an Icon Button with the X icon; it removes the row and updates the total', async () => {
    const w = await mountEditor([
      { ...usage[0]! },
      { type_id: 'b', name: 'Victor', tube_price: 360000, per_tube: 12, used: 1 },
    ])
    const rows = w.findAll('[data-ds="Shuttle Usage Row"]')
    expect(rows).toHaveLength(2)
    const remove = rows[0]!.get(`button[aria-label="${t('common.remove')}"]`)
    expect(remove.attributes('data-ds')).toBe('Icon Button')
    expect(remove.find('svg.lucide-x').exists()).toBe(true)
    expect(w.text()).not.toContain('×')

    await remove.trigger('click')
    expect(w.findAll('[data-ds="Shuttle Usage Row"]')).toHaveLength(1)
    expect(w.get('[data-testid="used-0"]').attributes('value')).toBe('1')
    expect(w.get('[data-testid="shuttle-total"]').text()).toContain('30.000')
  })

  it('hides remove when disabled', async () => {
    const w = await mountEditor(usage, true)
    expect(w.find(`button[aria-label="${t('common.remove')}"]`).exists()).toBe(false)
  })

  // Row: Shuttle states
  it('load error shows a Field Message Error', async () => {
    h.fetchError = true
    const w = await mountEditor()
    const msg = w.get('[data-ds="Field Message"]')
    expect(msg.attributes('data-ds-tone')).toBe('Error')
    expect(msg.text()).toBe(t('shuttle.loadError'))
    expect(w.find('[data-ds="Shuttle Usage Row"]').exists()).toBe(false)
  })

  it('no active types shows the warning note with a link to /settings', async () => {
    h.types = []
    setActivePinia(createPinia())
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: '/:p(.*)*', component: { template: '<div />' } }],
    })
    const w = mount(ShuttleUsageEditor, {
      props: { sessionId: 's1', usage: [], disabled: false },
      global: { plugins: [router] },
    })
    await flushPromises()
    expect(w.text()).toContain(t('shuttle.noActiveTypes'))
    const link = w.get('a[href="/settings"]')
    expect(link.text()).toBe(t('shuttle.goToSettings'))
    expect(w.get('[data-testid="add-row"]').attributes('disabled')).toBeDefined()
  })

  it('0 rows shows Empty State Plain Center Small', async () => {
    const w = await mountEditor([])
    const empty = w.get('[data-ds="Empty State"]')
    expect(empty.attributes('data-ds-style')).toBe('Plain')
    expect(empty.attributes('data-ds-align')).toBe('Center')
    expect(empty.attributes('data-ds-size')).toBe('Small')
    expect(empty.text()).toBe(t('shuttle.empty'))
  })

  // Row: Shuttle save
  it('save calls the RPC with the rows, emits saved and shows loading while pending', async () => {
    let resolve!: (v: unknown) => void
    vi.mocked(supabase.rpc).mockImplementationOnce(() => new Promise((r) => (resolve = r)) as any)
    const w = await mountEditor()
    await w.get('[data-testid="save"]').trigger('click')
    const save = w.get('[data-testid="save"]')
    expect(save.attributes('data-ds-state')).toBe('Loading')
    expect(save.attributes('aria-busy')).toBe('true')
    expect(save.attributes('disabled')).toBeDefined()
    expect(supabase.rpc).toHaveBeenCalledWith('set_session_shuttle_usage', {
      p_session_id: 's1',
      p_usage: [{ type_id: 'a', name: 'Vina', tube_price: 315000, per_tube: 12, used: 3 }],
    })

    resolve({ data: null, error: null })
    await flushPromises()
    expect(w.emitted('saved')).toEqual([
      [[{ type_id: 'a', name: 'Vina', tube_price: 315000, per_tube: 12, used: 3 }]],
    ])
    expect(w.get('[data-testid="save"]').attributes('data-ds-state')).toBe('Default')
  })

  it('save error shows the error message in a toast', async () => {
    vi.mocked(supabase.rpc).mockResolvedValueOnce({
      data: null,
      error: { message: 'rpc failed' },
    } as any)
    const w = await mountEditor()
    await w.get('[data-testid="save"]').trigger('click')
    await flushPromises()
    expect(h.toast.error).toHaveBeenCalledWith('rpc failed')
    expect(w.emitted('saved')).toBeUndefined()
  })
})
