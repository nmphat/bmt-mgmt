import { describe, it, expect } from 'vitest'
import { courtTotal, findOverlaps, shuttleTotal } from '@/utils/courtCost'
import type { CourtBookingDraft, ShuttleUsageEntry } from '@/types'

const draft = (
  court_name: string,
  start_time: string,
  end_time: string,
  price_per_hour: number,
): CourtBookingDraft => ({ court_name, start_time, end_time, price_per_hour })

describe('courtTotal', () => {
  it('charges each slot for the hours it covers', () => {
    // Sân 1 17:00-18:00 = 1h * 120000 = 120000
    // Sân 1 18:00-19:00 = 1h * 130000 = 130000
    // Sân 2 18:00-20:00 = 2h * 135000 = 270000
    // 120000 + 130000 + 270000 = 520000
    expect(
      courtTotal([
        draft('Sân 1', '17:00', '18:00', 120000),
        draft('Sân 1', '18:00', '19:00', 130000),
        draft('Sân 2', '18:00', '20:00', 135000),
      ]),
    ).toBe(520000) // 120000 + 130000 + 270000
  })

  it('handles half hours', () => {
    // 18:00-18:30 is 0.5h at 120000/hour => 0.5 * 120000 = 60000
    expect(courtTotal([draft('Sân 1', '18:00', '18:30', 120000)])).toBe(60000)
  })

  it('returns zero for an empty list', () => {
    expect(courtTotal([])).toBe(0)
  })

  it('totals two adjoining price slots on one court (the plan headline scenario)', () => {
    // 11:00-11:30 is 0.5h at 120000/hour => 0.5 * 120000 = 60000
    // 11:30-12:00 is 0.5h at 130000/hour => 0.5 * 130000 = 65000
    // 60000 + 65000 = 125000
    expect(
      courtTotal([
        draft('Sân 1', '11:00', '11:30', 120000),
        draft('Sân 1', '11:30', '12:00', 130000),
      ]),
    ).toBe(125000)
  })
})

describe('findOverlaps', () => {
  it('returns no indices when nothing overlaps at all', () => {
    expect(
      findOverlaps([
        draft('Sân 1', '07:00', '08:00', 100000),
        draft('Sân 1', '09:00', '10:00', 100000),
        draft('Sân 2', '07:00', '08:00', 100000),
      ]),
    ).toEqual([])
  })

  it('flags two slots that overlap on the same court', () => {
    expect(
      findOverlaps([
        draft('Sân 1', '17:00', '18:30', 120000),
        draft('Sân 1', '18:00', '19:00', 130000),
      ]),
    ).toEqual([0, 1])
  })

  it('allows slots that merely touch', () => {
    expect(
      findOverlaps([
        draft('Sân 1', '17:00', '18:00', 120000),
        draft('Sân 1', '18:00', '19:00', 130000),
      ]),
    ).toEqual([])
  })

  it('allows overlapping slots on different courts', () => {
    expect(
      findOverlaps([
        draft('Sân 1', '17:00', '19:00', 120000),
        draft('Sân 2', '17:00', '19:00', 135000),
      ]),
    ).toEqual([])
  })

  it('does not flag two adjoining price slots on one court as an overlap', () => {
    // Same headline scenario as courtTotal above: 11:00-11:30 and 11:30-12:00
    // touch at the boundary. The server's own overlap predicate is strict on
    // both sides (start < end AND end > start), so a shared boundary point is
    // disjoint, not an overlap.
    expect(
      findOverlaps([
        draft('Sân 1', '11:00', '11:30', 120000),
        draft('Sân 1', '11:30', '12:00', 130000),
      ]),
    ).toEqual([])
  })
})

describe('shuttleTotal', () => {
  it('prices part of a tube', () => {
    // a: 315000 / 12 per tube = 26250/unit * 3 used = 78750
    // b: 360000 / 12 per tube = 30000/unit * 2 used = 60000
    // 78750 + 60000 = 138750
    const usage: ShuttleUsageEntry[] = [
      { type_id: 'a', name: 'Vina', tube_price: 315000, per_tube: 12, used: 3 },
      { type_id: 'b', name: 'Victor', tube_price: 360000, per_tube: 12, used: 2 },
    ]
    expect(shuttleTotal(usage)).toBe(138750)
  })

  it('treats a zero tube size as zero rather than dividing by it', () => {
    expect(
      shuttleTotal([{ type_id: 'a', name: 'X', tube_price: 100000, per_tube: 0, used: 5 }]),
    ).toBe(0)
  })

  it('rounds the sum once, not each entry (sum-then-round)', () => {
    // Each entry: 320000 / 12 = 26666.666...  (does not divide evenly)
    // Correct (sum-then-round): 26666.666... + 26666.666... = 53333.333...
    //   Math.round(53333.333...) = 53333
    // Wrong (round-then-sum): Math.round(26666.666...) = 26667, doubled = 53334
    // If a future edit flips the order, this assertion (53333) fails against 53334.
    const usage: ShuttleUsageEntry[] = [
      { type_id: 'a', name: 'Vina', tube_price: 320000, per_tube: 12, used: 1 },
      { type_id: 'b', name: 'Victor', tube_price: 320000, per_tube: 12, used: 1 },
    ]
    expect(shuttleTotal(usage)).toBe(53333)
  })
})
