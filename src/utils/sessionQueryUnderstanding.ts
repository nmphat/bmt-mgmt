export interface SessionQueryUnderstandingResult {
  keyword: string
  parsedStartDate: string | null
  parsedEndDate: string | null
}

type SportAliasGroup = {
  canonical: string
  preferredToken: string
  aliases: string[]
}

const SPORT_ALIAS_GROUPS: SportAliasGroup[] = [
  {
    canonical: 'cau long',
    preferredToken: 'cl',
    aliases: ['cl', 'bmt', 'bd', 'badminton', 'bad', 'cau long', 'caulong', 'cau'],
  },
  {
    canonical: 'bong ban',
    preferredToken: 'bb',
    aliases: [
      'bb',
      'tt',
      'ping',
      'pong',
      'pingpong',
      'ping pong',
      'table tennis',
      'tabletennis',
      'bong ban',
    ],
  },
  {
    canonical: 'pickleball',
    preferredToken: 'pickleball',
    aliases: ['pick', 'pk', 'pb', 'pickle', 'pickleball', 'pickle ball'],
  },
]

function normalizeText(input: string): string {
  return input
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
}

function formatDatePart(value: number): string {
  return String(value).padStart(2, '0')
}

function toIsoDate(date: Date): string {
  const year = date.getFullYear()
  const month = formatDatePart(date.getMonth() + 1)
  const day = formatDatePart(date.getDate())
  return `${year}-${month}-${day}`
}

function buildMonthRange(year: number, month: number) {
  const from = `${year}-${formatDatePart(month)}-01`
  const endDate = new Date(year, month, 0)
  const to = `${year}-${formatDatePart(month)}-${formatDatePart(endDate.getDate())}`
  return { from, to }
}

function parseYearToken(value: string): number {
  const num = Number(value)
  if (value.length === 2) {
    return num >= 70 ? 1900 + num : 2000 + num
  }
  return num
}

function parseDateToken(token: string): string | null {
  const raw = token.trim()
  if (!raw) return null

  const ymd = raw.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$/)
  if (ymd) {
    const y = Number(ymd[1])
    const m = Number(ymd[2])
    const d = Number(ymd[3])
    if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
      return `${y}-${formatDatePart(m)}-${formatDatePart(d)}`
    }
  }

  const dmy = raw.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$/)
  if (dmy && dmy[3]) {
    const d = Number(dmy[1])
    const m = Number(dmy[2])
    const y = parseYearToken(dmy[3])
    if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
      return `${y}-${formatDatePart(m)}-${formatDatePart(d)}`
    }
  }

  const dm = raw.match(/^(\d{1,2})[-/.](\d{1,2})$/)
  if (dm) {
    const d = Number(dm[1])
    const m = Number(dm[2])
    const y = new Date().getFullYear()
    if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
      return `${y}-${formatDatePart(m)}-${formatDatePart(d)}`
    }
  }

  const monthMap: Record<string, number> = {
    jan: 1,
    january: 1,
    feb: 2,
    february: 2,
    mar: 3,
    march: 3,
    apr: 4,
    april: 4,
    may: 5,
    jun: 6,
    june: 6,
    jul: 7,
    july: 7,
    aug: 8,
    august: 8,
    sep: 9,
    sept: 9,
    september: 9,
    oct: 10,
    october: 10,
    nov: 11,
    november: 11,
    dec: 12,
    december: 12,
  }

  const normalized = normalizeText(raw)
  const monthWordYear = normalized.match(
    /\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\s+(\d{4})\b/,
  )
  if (monthWordYear && monthWordYear[1] && monthWordYear[2]) {
    const month = monthMap[monthWordYear[1]]
    const year = Number(monthWordYear[2])
    if (month) {
      return `${year}-${formatDatePart(month)}-01`
    }
  }

  const viMonthYear = normalized.match(/(?:thang|thg)\s*(\d{1,2})\s*(?:nam)?\s*(\d{4})\b/)
  if (viMonthYear) {
    const month = Number(viMonthYear[1])
    const year = Number(viMonthYear[2])
    if (month >= 1 && month <= 12) {
      return `${year}-${formatDatePart(month)}-01`
    }
  }

  const viMonthOnly = normalized.match(/(?:thang|thg)\s*(\d{1,2})\b/)
  if (viMonthOnly) {
    const month = Number(viMonthOnly[1])
    const year = new Date().getFullYear()
    if (month >= 1 && month <= 12) {
      return `${year}-${formatDatePart(month)}-01`
    }
  }

  const monthWordOnly = normalized.match(
    /\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\b/,
  )
  if (monthWordOnly && monthWordOnly[1]) {
    const month = monthMap[monthWordOnly[1]]
    const year = new Date().getFullYear()
    if (month) {
      return `${year}-${formatDatePart(month)}-01`
    }
  }

  return null
}

function getWeekRangeMonday(now = new Date()) {
  const current = new Date(now)
  const day = current.getDay()
  const mondayOffset = day === 0 ? -6 : 1 - day
  const monday = new Date(current)
  monday.setDate(current.getDate() + mondayOffset)
  const sunday = new Date(monday)
  sunday.setDate(monday.getDate() + 6)
  return { from: toIsoDate(monday), to: toIsoDate(sunday) }
}

export function understandSessionQuery(raw: string): SessionQueryUnderstandingResult {
  const original = raw.trim()
  if (!original) {
    return { keyword: '', parsedStartDate: null, parsedEndDate: null }
  }

  let parsedStartDate: string | null = null
  let parsedEndDate: string | null = null
  const normalized = normalizeText(original)

  const rangeRegex =
    /(\d{1,4}[\/.\-]\d{1,2}(?:[\/.\-]\d{1,4})?|(?:thang|thg)\s*\d{1,2}\s*(?:nam)?\s*\d{4}|(?:jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\s+\d{4})\s*(?:to|den|->|~|\-|–)\s*(\d{1,4}[\/.\-]\d{1,2}(?:[\/.\-]\d{1,4})?|(?:thang|thg)\s*\d{1,2}\s*(?:nam)?\s*\d{4}|(?:jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\s+\d{4})/i

  const rangeMatch = normalized.match(rangeRegex)
  if (rangeMatch && rangeMatch[1] && rangeMatch[2]) {
    const from = parseDateToken(rangeMatch[1])
    const to = parseDateToken(rangeMatch[2])
    if (from && to) {
      parsedStartDate = from
      parsedEndDate = to
    }
  }

  if (!parsedStartDate) {
    const explicitDateMatch = normalized.match(
      /\b(\d{4}[\/.\-]\d{1,2}[\/.\-]\d{1,2}|\d{1,2}[\/.\-]\d{1,2}[\/.\-]\d{2,4}|\d{1,2}[\/.\-]\d{1,2})\b/,
    )
    if (explicitDateMatch && explicitDateMatch[1]) {
      const date = parseDateToken(explicitDateMatch[1])
      if (date) {
        parsedStartDate = date
        parsedEndDate = date
      }
    }
  }

  if (!parsedStartDate) {
    const monthYearVi = normalized.match(/(?:thang|thg)\s*(\d{1,2})\s*(?:nam)?\s*(\d{4})\b/)
    if (monthYearVi) {
      const month = Number(monthYearVi[1])
      const year = Number(monthYearVi[2])
      if (month >= 1 && month <= 12) {
        const range = buildMonthRange(year, month)
        parsedStartDate = range.from
        parsedEndDate = range.to
      }
    }
  }

  if (!parsedStartDate) {
    const monthOnlyVi = normalized.match(/(?:thang|thg)\s*(\d{1,2})\b/)
    if (monthOnlyVi) {
      const month = Number(monthOnlyVi[1])
      const year = new Date().getFullYear()
      if (month >= 1 && month <= 12) {
        const range = buildMonthRange(year, month)
        parsedStartDate = range.from
        parsedEndDate = range.to
      }
    }
  }

  if (!parsedStartDate) {
    const monthYearEn = normalized.match(
      /\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\s+(\d{4})\b/,
    )
    if (monthYearEn && monthYearEn[1] && monthYearEn[2]) {
      const firstDay = parseDateToken(`${monthYearEn[1]} ${monthYearEn[2]}`)
      if (firstDay) {
        const [yText, mText] = firstDay.split('-')
        const y = Number(yText)
        const m = Number(mText)
        if (!Number.isNaN(y) && !Number.isNaN(m)) {
          const range = buildMonthRange(y, m)
          parsedStartDate = range.from
          parsedEndDate = range.to
        }
      }
    }
  }

  if (!parsedStartDate) {
    const monthOnlyEn = normalized.match(
      /\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\b/,
    )
    if (monthOnlyEn && monthOnlyEn[1]) {
      const firstDay = parseDateToken(monthOnlyEn[1])
      if (firstDay) {
        const [yText, mText] = firstDay.split('-')
        const y = Number(yText)
        const m = Number(mText)
        if (!Number.isNaN(y) && !Number.isNaN(m)) {
          const range = buildMonthRange(y, m)
          parsedStartDate = range.from
          parsedEndDate = range.to
        }
      }
    }
  }

  if (!parsedStartDate) {
    const now = new Date()

    if (/\b(hom nay|today)\b/i.test(normalized)) {
      const iso = toIsoDate(now)
      parsedStartDate = iso
      parsedEndDate = iso
    } else if (/\b(hom qua|yesterday)\b/i.test(normalized)) {
      const d = new Date(now)
      d.setDate(d.getDate() - 1)
      const iso = toIsoDate(d)
      parsedStartDate = iso
      parsedEndDate = iso
    } else if (/\b(tuan nay|this week)\b/i.test(normalized)) {
      const range = getWeekRangeMonday(now)
      parsedStartDate = range.from
      parsedEndDate = range.to
    } else if (/\b(thang nay|this month)\b/i.test(normalized)) {
      const range = buildMonthRange(now.getFullYear(), now.getMonth() + 1)
      parsedStartDate = range.from
      parsedEndDate = range.to
    } else if (/\b(thang truoc|last month|previous month)\b/i.test(normalized)) {
      const prev = new Date(now.getFullYear(), now.getMonth() - 1, 1)
      const range = buildMonthRange(prev.getFullYear(), prev.getMonth() + 1)
      parsedStartDate = range.from
      parsedEndDate = range.to
    } else if (/\b(nam nay|this year)\b/i.test(normalized)) {
      const y = now.getFullYear()
      parsedStartDate = `${y}-01-01`
      parsedEndDate = `${y}-12-31`
    } else if (/\b(last\s*7\s*days|past\s*7\s*days|7\s*ngay|7d)\b/i.test(normalized)) {
      const end = toIsoDate(now)
      const start = new Date(now)
      start.setDate(start.getDate() - 6)
      parsedStartDate = toIsoDate(start)
      parsedEndDate = end
    } else if (/\b(last\s*30\s*days|past\s*30\s*days|30\s*ngay|30d)\b/i.test(normalized)) {
      const end = toIsoDate(now)
      const start = new Date(now)
      start.setDate(start.getDate() - 29)
      parsedStartDate = toIsoDate(start)
      parsedEndDate = end
    }
  }

  let matchedGroup: SportAliasGroup | null = null
  for (const group of SPORT_ALIAS_GROUPS) {
    const hasAlias = group.aliases.some((alias) => {
      const escaped = alias.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      const pattern = new RegExp(`(^|\\s)${escaped}(\\s|$)`, 'i')
      return pattern.test(normalized)
    })
    if (hasAlias) {
      matchedGroup = group
      break
    }
  }

  let cleanedKeyword = original
    .replace(/\b\d{4}-\d{1,2}-\d{1,2}\b/g, ' ')
    .replace(/\b\d{1,2}[\/.\-]\d{1,2}(?:[\/.\-]\d{2,4})?\b/g, ' ')
    .replace(/(?:tháng|thang|thg)?\s*\d{1,2}[\s\/-]+\d{4}\b/gi, ' ')
    .replace(/(?:tháng|thang|thg)\s*\d{1,2}\b/gi, ' ')
    .replace(
      /\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\s+\d{4}\b/gi,
      ' ',
    )
    .replace(
      /\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\b/gi,
      ' ',
    )
    .replace(
      /\b(hom nay|today|hom qua|yesterday|tuan nay|this week|thang nay|this month|thang truoc|last month|previous month|nam nay|this year|last\s*7\s*days|past\s*7\s*days|7\s*ngay|7d|last\s*30\s*days|past\s*30\s*days|30\s*ngay|30d)\b/gi,
      ' ',
    )
    .replace(/\b(ngay|ngày|date|from|to|den|đến|tu|từ|on|during|trong)\b/gi, ' ')

  if (matchedGroup) {
    for (const alias of matchedGroup.aliases) {
      const escaped = alias.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      cleanedKeyword = cleanedKeyword.replace(
        new RegExp(`(^|\\s)${escaped}(\\s|$)`, 'gi'),
        ` ${matchedGroup.preferredToken} `,
      )
    }
  }

  cleanedKeyword = cleanedKeyword.replace(/\s+/g, ' ').trim()

  if (!cleanedKeyword && matchedGroup) {
    cleanedKeyword = matchedGroup.preferredToken
  }

  return {
    keyword: cleanedKeyword,
    parsedStartDate,
    parsedEndDate,
  }
}
