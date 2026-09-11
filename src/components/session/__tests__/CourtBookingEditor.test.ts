import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import CourtBookingEditor from '@/components/session/CourtBookingEditor.vue'
import type { CourtBookingDraft } from '@/types'

// useLangStore reads localStorage on init. Node's own experimental global
// `localStorage` (on by default in the Node version running this suite)
// shadows happy-dom's polyfill and evaluates to `undefined`, so stub a
// working in-memory implementation before each test.
beforeEach(() => {
  const store = new Map<string, string>()
  Object.defineProperty(globalThis, 'localStorage', {
    configurable: true,
    value: {
      getItem: (key: string) => store.get(key) ?? null,
      setItem: (key: string, value: string) => store.set(key, value),
      removeItem: (key: string) => store.delete(key),
      clear: () => store.clear(),
    },
  })
})

const base: CourtBookingDraft[] = [
  { court_name: 'Sân 1', start_time: '17:00', end_time: '18:00', price_per_hour: 120000 },
  { court_name: 'Sân 1', start_time: '18:00', end_time: '19:00', price_per_hour: 130000 },
  { court_name: 'Sân 2', start_time: '18:00', end_time: '20:00', price_per_hour: 135000 },
]

function mountEditor(bookings = base) {
  setActivePinia(createPinia())
  return mount(CourtBookingEditor, {
    props: { bookings, sessionStart: '17:00', sessionEnd: '20:00', defaultPrice: 120000 },
  })
}

describe('CourtBookingEditor', () => {
  it('groups slots under one card per court', () => {
    const w = mountEditor()
    expect(w.findAll('[data-testid="court-card"]')).toHaveLength(2)
  })

  it('shows the court total', () => {
    const w = mountEditor()
    expect(w.get('[data-testid="court-total"]').text()).toContain('520.000')
  })

  it('reports invalid when two slots on one court overlap', async () => {
    const w = mountEditor([
      { court_name: 'Sân 1', start_time: '17:00', end_time: '18:30', price_per_hour: 120000 },
      { court_name: 'Sân 1', start_time: '18:00', end_time: '19:00', price_per_hour: 130000 },
    ])
    await w.vm.$nextTick()
    expect(w.emitted('update:valid')?.at(-1)).toEqual([false])
    expect(w.text()).toContain('trùng nhau')
  })

  it('reports invalid when a slot falls outside the session window', async () => {
    const w = mountEditor([
      { court_name: 'Sân 1', start_time: '16:00', end_time: '18:00', price_per_hour: 120000 },
    ])
    await w.vm.$nextTick()
    expect(w.emitted('update:valid')?.at(-1)).toEqual([false])
  })

  it('adds a court seeded with the session window and default price', async () => {
    const w = mountEditor()
    await w.get('[data-testid="add-court"]').trigger('click')
    const emitted = w.emitted('update:bookings')?.at(-1)?.[0] as CourtBookingDraft[]
    expect(emitted).toHaveLength(4)
    expect(emitted[3]).toMatchObject({
      start_time: '17:00',
      end_time: '20:00',
      price_per_hour: 120000,
    })
  })

  it('keeps at least one slot', async () => {
    const w = mountEditor([base[0]])
    expect(w.get('[data-testid="remove-slot-0"]').attributes('disabled')).toBeDefined()
  })
})
