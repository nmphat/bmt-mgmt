/**
 * Merges consecutive time intervals into a readable string.
 * Example:
 * Input: [{start: '16:00', end: '16:30'}, {start: '16:30', end: '17:00'}, {start: '18:00', end: '18:30'}]
 * Output: "16:00 - 17:00; 18:00 - 18:30"
 */

interface TimeInterval {
  start_time: string // ISO string or 'HH:mm'
  end_time: string // ISO string or 'HH:mm'
}

export function mergeTimeIntervals(intervals: TimeInterval[]): string {
  if (!intervals || intervals.length === 0) return ''

  // Normalize to HH:mm
  const formatTime = (time: string) => {
    if (!time) return ''
    if (time.includes('T')) {
      return time.split('T')[1].substring(0, 5)
    }
    return time.substring(0, 5)
  }

  const sorted = [...intervals].sort((a, b) => {
    if (!a.start_time || !b.start_time) return 0
    return formatTime(a.start_time).localeCompare(formatTime(b.start_time))
  })

  if (sorted.length === 0) return ''

  const merged: { start: string; end: string }[] = []

  // Safe access for first element
  const first = sorted[0]
  if (!first || !first.start_time || !first.end_time) return ''

  let current = {
    start: formatTime(first.start_time),
    end: formatTime(first.end_time),
  }

  for (let i = 1; i < sorted.length; i++) {
    const item = sorted[i]
    if (!item || !item.start_time || !item.end_time) continue

    const next = {
      start: formatTime(item.start_time),
      end: formatTime(item.end_time),
    }

    if (current.end === next.start) {
      // Merge
      current.end = next.end
    } else {
      // Push and start new
      merged.push(current)
      current = next
    }
  }
  merged.push(current)

  return merged.map((m) => `${m.start}-${m.end}`).join('; ')
}
