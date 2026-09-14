import type { CourtBookingDraft, ShuttleUsageEntry } from '@/types'

/** "HH:mm" → số phút kể từ nửa đêm. */
function toMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number)
  return (h ?? 0) * 60 + (m ?? 0)
}

/** Tổng tiền sân của một danh sách nháp, tính theo số giờ mỗi khung phủ. */
export function courtTotal(bookings: CourtBookingDraft[]): number {
  return bookings.reduce((sum, b) => {
    const hours = (toMinutes(b.end_time) - toMinutes(b.start_time)) / 60
    return hours > 0 ? sum + b.price_per_hour * hours : sum
  }, 0)
}

/**
 * Chỉ số các khung giờ chồng lên một khung khác của cùng một sân.
 * Khung chồng nhau làm refresh_interval_courts cộng tiền sân hai lần,
 * nên giao diện phải chặn lưu chứ không chỉ cảnh báo.
 */
export function findOverlaps(bookings: CourtBookingDraft[]): number[] {
  const bad = new Set<number>()
  for (let i = 0; i < bookings.length; i++) {
    for (let j = i + 1; j < bookings.length; j++) {
      const a = bookings[i]
      const b = bookings[j]
      if (!a || !b) continue
      if (a.court_name !== b.court_name) continue
      if (
        toMinutes(a.start_time) < toMinutes(b.end_time) &&
        toMinutes(b.start_time) < toMinutes(a.end_time)
      ) {
        bad.add(i)
        bad.add(j)
      }
    }
  }
  return [...bad].sort((x, y) => x - y)
}

/**
 * Tổng tiền cầu. Phải khớp công thức trong set_session_shuttle_usage:
 * cộng dồn trước, làm tròn một lần duy nhất ở cuối — không làm tròn từng dòng.
 */
export function shuttleTotal(usage: ShuttleUsageEntry[]): number {
  const sum = usage.reduce((total, e) => {
    if (!e.per_tube) return total
    return total + (e.tube_price / e.per_tube) * e.used
  }, 0)
  return Math.round(sum)
}
