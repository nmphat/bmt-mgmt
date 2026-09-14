import { describe, it, expect, vi } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import ShuttleUsageEditor from '@/components/session/ShuttleUsageEditor.vue'
import type { ShuttleUsageEntry } from '@/types'

vi.mock('@/composables/useShuttleTypes', () => ({
  useShuttleTypes: () => ({
    activeTypes: {
      value: [
        { id: 'a', name: 'Vina', tube_price: 315000, per_tube: 12, is_active: true },
        { id: 'b', name: 'Victor', tube_price: 360000, per_tube: 12, is_active: true },
      ],
    },
    loading: { value: false },
    fetchTypes: vi.fn().mockResolvedValue(undefined),
  }),
}))

vi.mock('@/lib/supabase', () => ({
  supabase: { rpc: vi.fn().mockResolvedValue({ data: null, error: null }) },
}))

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
