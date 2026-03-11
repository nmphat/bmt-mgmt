import { format, parseISO } from 'date-fns'
import type { Locale } from '@/locales/messages'

function toDate(input: string | Date | null | undefined): Date | null {
  if (!input) return null
  if (input instanceof Date) return input

  // Keep date-only values stable across timezones.
  if (/^\d{4}-\d{2}-\d{2}$/.test(input)) {
    return parseISO(input)
  }

  return new Date(input)
}

function getDatePattern(lang: Locale): string {
  return lang === 'vi' ? 'dd/MM/yyyy' : 'MMMM dd, yyyy'
}

export function formatDisplayDate(input: string | Date | null | undefined, lang: Locale): string {
  const date = toDate(input)
  if (!date || Number.isNaN(date.getTime())) return ''

  return format(date, getDatePattern(lang))
}

export function formatDisplayDateTime(
  input: string | Date | null | undefined,
  lang: Locale,
): string {
  const date = toDate(input)
  if (!date || Number.isNaN(date.getTime())) return ''

  return `${format(date, getDatePattern(lang))} ${format(date, 'HH:mm')}`
}

export function formatDisplayTime(input: string | Date | null | undefined): string {
  const date = toDate(input)
  if (!date || Number.isNaN(date.getTime())) return ''

  return format(date, 'HH:mm')
}
