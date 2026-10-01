import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import CourtBookingEditor from '@/components/session/CourtBookingEditor.vue'
import { useLangStore } from '@/stores/lang'
import type { CourtBookingDraft } from '@/types'

// Types into the field: sets the value and fires only `input` (VTU's setValue also fires `change`).
async function type(
  w: { element: Element; trigger: (e: string) => Promise<void> },
  value: string | number,
) {
  ;(w.element as HTMLInputElement).value = String(value)
  await w.trigger('input')
}

const base: CourtBookingDraft[] = [
  { court_name: 'Sân 1', start_time: '17:00', end_time: '18:00', price_per_hour: 120000 },
  { court_name: 'Sân 1', start_time: '18:00', end_time: '19:00', price_per_hour: 130000 },
  { court_name: 'Sân 2', start_time: '18:00', end_time: '20:00', price_per_hour: 135000 },
]

function mountEditor(bookings = base, extraProps: Record<string, unknown> = {}) {
  setActivePinia(createPinia())
  return mount(CourtBookingEditor, {
    props: {
      bookings,
      sessionStart: '17:00',
      sessionEnd: '20:00',
      defaultPrice: 120000,
      ...extraProps,
    },
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

  it('disables every interactive control when disabled is true', () => {
    const w = mountEditor(base, { disabled: true })
    // Query every input/select/button that exists, rather than hardcoding a
    // count: a control added later without :disabled must fail this test.
    const controls = w.findAll('input, select, button')
    expect(controls.length).toBeGreaterThan(0)
    for (const [i, control] of controls.entries()) {
      const label = `control #${i} <${control.element.tagName.toLowerCase()} data-testid="${control.attributes('data-testid')}">`
      expect(control.attributes('disabled'), `${label} should be disabled`).toBeDefined()
    }
  })

  it("adds a slot to an existing court, seeded from that court's last end_time", async () => {
    const w = mountEditor()
    // Sân 1 already has two rows (17:00-18:00, 18:00-19:00); the new slot
    // should continue from the later one's end_time (19:00) through sessionEnd.
    await w.get('[data-testid="add-slot-Sân 1"]').trigger('click')
    const emitted = w.emitted('update:bookings')?.at(-1)?.[0] as CourtBookingDraft[]
    expect(emitted).toHaveLength(4)
    expect(emitted[3]).toMatchObject({
      court_name: 'Sân 1',
      start_time: '19:00',
      end_time: '20:00',
      price_per_hour: 120000,
    })
  })

  it('clamps a negative price to the stored 0 and writes it back', async () => {
    const w = mountEditor([{ ...base[0]!, price_per_hour: 0 }, base[1]!, base[2]!])
    const price = w.get('[data-testid="price-0"]')
    await type(price, '-5000')
    await price.trigger('change')
    expect((price.element as HTMLInputElement).value).toBe('0')
    const emitted = w.emitted('update:bookings')?.at(-1)?.[0] as CourtBookingDraft[]
    expect(emitted[0]).toMatchObject({ price_per_hour: 0 })
  })

  it('renames a court once on change, not per keystroke', async () => {
    const w = mountEditor()
    const name = w.get('[data-testid="court-name-Sân 1"]')
    await type(name, 'Sân')
    await type(name, 'Sân A')
    expect(w.emitted('update:bookings')).toBeUndefined()
    await name.trigger('change')
    expect(w.emitted('update:bookings')).toHaveLength(1)
    const emitted = w.emitted('update:bookings')![0]![0] as CourtBookingDraft[]
    expect(emitted[0]).toMatchObject({ court_name: 'Sân A' })
  })

  it('emits an updated price on the right row and recomputes the displayed total', async () => {
    const w = mountEditor()
    const price = w.get('[data-testid="price-0"]')
    await type(price, 150000)
    await price.trigger('change')
    const emitted = w.emitted('update:bookings')?.at(-1)?.[0] as CourtBookingDraft[]
    await w.setProps({ bookings: emitted })
    expect((price.element as HTMLInputElement).value).toBe('150000')
    expect(emitted[0]).toMatchObject({ price_per_hour: 150000 })
    expect(emitted[1]).toEqual(base[1])
    expect(emitted[2]).toEqual(base[2])

    // Hand derivation of the total once row 0's price changes 120000 -> 150000:
    // Sân 1 17:00-18:00 = 1h * 150000       = 150000
    // Sân 1 18:00-19:00 = 1h * 130000       = 130000
    // Sân 2 18:00-20:00 = 2h * 135000       = 270000
    // 150000 + 130000 + 270000              = 550000
    await w.setProps({ bookings: emitted })
    expect(w.get('[data-testid="court-total"]').text()).toContain('550.000')
  })

  it('emits an updated time on the right row when a time select changes', async () => {
    const w = mountEditor()
    await w.get('[data-testid="start-time-2"]').setValue('17:00')
    const emitted = w.emitted('update:bookings')?.at(-1)?.[0] as CourtBookingDraft[]
    expect(emitted[2]).toMatchObject({ court_name: 'Sân 2', start_time: '17:00' })
    expect(emitted[0]).toEqual(base[0])
    expect(emitted[1]).toEqual(base[1])
  })

  it('removes exactly the targeted slot and keeps the others in order', async () => {
    const w = mountEditor()
    await w.get('[data-testid="remove-slot-0"]').trigger('click')
    const emitted = w.emitted('update:bookings')?.at(-1)?.[0] as CourtBookingDraft[]
    expect(emitted).toEqual([base[1], base[2]])
  })

  it('removes a court entirely once its last slot is removed while another court remains', async () => {
    const twoCourts: CourtBookingDraft[] = [
      { court_name: 'Sân 1', start_time: '17:00', end_time: '18:00', price_per_hour: 120000 },
      { court_name: 'Sân 2', start_time: '18:00', end_time: '20:00', price_per_hour: 135000 },
    ]
    const w = mountEditor(twoCourts)
    await w.get('[data-testid="remove-slot-0"]').trigger('click')
    const emitted = w.emitted('update:bookings')?.at(-1)?.[0] as CourtBookingDraft[]
    expect(emitted).toEqual([twoCourts[1]])
  })
})

describe('CourtBookingEditor (I/O matrix)', () => {
  const t = (key: string) => useLangStore().t(key)
  const slot = (start_time: string, end_time: string): CourtBookingDraft => ({
    court_name: 'Sân 1',
    start_time,
    end_time,
    price_per_hour: 120000,
  })

  // Row: Court slot errors
  it.each([
    {
      name: 'overlap',
      bookings: [slot('17:00', '18:30'), slot('18:00', '19:00')],
      error: 'Overlap',
      tone: 'Danger',
      key: 'courtBooking.overlapError',
    },
    {
      name: 'end before start',
      bookings: [slot('19:00', '18:00')],
      error: 'End Before Start',
      tone: 'Danger',
      key: 'courtBooking.endBeforeStartError',
    },
    {
      name: 'out of bounds',
      bookings: [slot('16:00', '18:00')],
      error: 'Out Of Bounds',
      tone: 'Warning',
      key: 'courtBooking.outOfBoundsError',
    },
  ])('$name: Alert Small $tone and row Error $error', ({ bookings, error, tone, key }) => {
    const w = mountEditor(bookings)
    const row = w.get('[data-ds="Court Slot Row"]')
    expect(row.attributes('data-ds-error')).toBe(error)
    const alert = row.get('[data-ds="Alert"]')
    expect(alert.attributes('data-ds-tone')).toBe(tone)
    expect(alert.attributes('data-ds-size')).toBe('Small')
    expect(alert.attributes('data-ds-style')).toBe('Box')
    expect(alert.attributes('role')).toBe(tone === 'Danger' ? 'alert' : undefined)
    expect(alert.text()).toBe(t(key))
  })

  it('valid slot: row Error None and no Alert', () => {
    const w = mountEditor([slot('17:00', '18:00')])
    expect(w.get('[data-ds="Court Slot Row"]').attributes('data-ds-error')).toBe('None')
    expect(w.find('[data-ds="Alert"]').exists()).toBe(false)
  })

  it('remove slot is an Icon Button Default Square Ghost labelled removeSlot', () => {
    const w = mountEditor()
    const remove = w.get('[data-testid="remove-slot-0"]')
    expect(remove.attributes('data-ds')).toBe('Icon Button')
    expect(remove.attributes('data-ds-size')).toBe('Default')
    expect(remove.attributes('data-ds-shape')).toBe('Square')
    expect(remove.attributes('data-ds-style')).toBe('Ghost')
    expect(remove.attributes('aria-label')).toBe(t('courtBooking.removeSlot'))
    expect(remove.attributes('title')).toBe(t('courtBooking.removeSlot'))
  })
})
