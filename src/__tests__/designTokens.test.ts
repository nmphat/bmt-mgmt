import { describe, it, expect } from 'vitest'

// Views and components use the semantic tokens of src/assets/tokens.css (generated from the Figma variables), never a
// palette shade such as `bg-green-600` or `text-gray-500`. Files that still use palette shades are listed below; each
// B-1 slice migrates its files and removes them from this list, and the last slice leaves it empty.
const PALETTE_ALLOWED = [
  'App.vue',
  'components/AppHeader.vue',
  'components/BottomNav.vue',
  'components/CashPaymentModal.vue',
  'components/HomeDebtTable.vue',
  'components/ManualPaymentModal.vue',
  'components/PaymentQRModal.vue',
  'components/SessionExtraCharges.vue',
  'components/session/CourtBookingEditor.vue',
  'components/session/ShuttleUsageEditor.vue',
  'views/PaymentView.vue',
  'views/SessionDetailView.vue',
]

const PALETTE_CLASS =
  /(?:^|[^a-z-])((?:bg|text|border|ring|divide|from|via|to|outline|fill|stroke|placeholder|decoration|accent|caret)-(?:gray|red|green|amber|blue|emerald|brand|slate|zinc|neutral|stone|orange|yellow|lime|teal|cyan|sky|indigo|violet|purple|fuchsia|pink|rose)-\d+)/g

const sources = import.meta.glob('../**/*.vue', {
  query: '?raw',
  import: 'default',
  eager: true,
}) as Record<string, string>
const files = Object.entries(sources).map(
  ([path, text]) => [path.replace(/^\.\.\//, ''), text] as const,
)

describe('design tokens', () => {
  it('finds the source files', () => {
    expect(files.length).toBeGreaterThan(10)
  })

  it('uses no palette shade outside the files still to migrate', () => {
    const offenders = files
      .filter(([path]) => !PALETTE_ALLOWED.includes(path))
      .map(
        ([path, text]) =>
          [path, [...new Set([...text.matchAll(PALETTE_CLASS)].map((m) => m[1]))]] as const,
      )
      .filter(([, hits]) => hits.length)
      .map(([path, hits]) => `${path}: ${hits.join(', ')}`)
    expect(offenders).toEqual([])
  })

  it('lists only files that still use palette shades', () => {
    const stale = PALETTE_ALLOWED.filter((path) => {
      const text = sources[`../${path}`]
      return text === undefined || [...text.matchAll(PALETTE_CLASS)].length === 0
    })
    expect(stale).toEqual([])
  })
})
