# Brand spec — Badminton Management

Source observed: `src/assets/main.css` and Vue templates using Tailwind utility classes directly.

## 2026-09-14 update: redesign pass

The two decisions below (no color tokens, no font override) were revisited the same day and **superseded** by an explicit redesign request. Kept here for history, not as current guidance — see "Current tokens" instead.

> ~~**Màu:** không có CSS variable nào... thêm token trừu tượng vào lúc này là refactor không có lý do thực tế đi kèm.~~
> ~~**Font:** không override `font-family`... vốn đã tương đương tinh thần "system font".~~

## Current tokens

`src/assets/main.css`:

```css
@theme {
  --text-xs: 0.75rem;
  --text-sm: 0.875rem;
  --text-base: 1rem;
  --text-lg: 1.125rem;
  --text-xl: 1.25rem;
  --text-2xl: 1.5rem;
  --text-3xl: 2rem;

  --font-sans: 'Plus Jakarta Sans', ui-sans-serif, system-ui, -apple-system, 'Segoe UI', sans-serif;

  --color-brand-50 … --color-brand-900; /* see main.css */
}
html { font-size: 16px; }
body { font-variant-numeric: tabular-nums; }
```

- **Font:** Plus Jakarta Sans (Google Fonts, weights 400–800), loaded in `index.html`. First choice during the redesign was Be Vietnam Pro (full Vietnamese diacritic coverage, since roughly half this app's UI copy is Vietnamese) — swapped to Plus Jakarta Sans same day after user feedback that Be Vietnam Pro's default weight read too heavy/thick. Plus Jakarta Sans keeps full Vietnamese subset coverage but with visibly lighter strokes at every weight; it also tops out at 800 (no 900/Black face), so `font-black` usages degrade gracefully to 800 instead of a true black weight — fine here since lighter was the point. Applied once via `--font-sans`; no per-component `font-*` classes needed.
- **Màu:** `brand-*` token ramp (50–900) replaces every former `indigo-*` utility 1:1 across `src/` (mechanical rename). Same hue (~277° in OKLCH) as the old indigo, but chroma trimmed ~18% off the peak shades (400–800) so the accent reads as a considered brand color rather than stock Tailwind indigo. `brand-600` is still the primary CTA/link color. Status-semantic colors (red/orange/green/gray for debt and session states) were deliberately **not** touched — those are functional traffic-light signals, not decorative accents, and collapsing them to one color would hurt usability.
- **Numbers:** `font-variant-numeric: tabular-nums` set globally on `body` — this is a money/debt-tracking app, so digit alignment in tables and totals matters.
- **Mono:** still unused; no data-dense screens need it.

## Observed posture rules

- Neutral app shell: `gray-50` page, white cards, gray dividers.
- Primary action accent: `brand-600/700` (was `indigo-600/700`), mostly for admin CTAs and links.
- Status semantics: blue=open, orange=waiting/payment, green=done/paid, gray=cancelled/neutral. Unchanged by the redesign.
- Card radius: 8–12px, low elevation, hairline borders often better than shadow on mobile.
- Current type scale intentionally enlarged globally in Tailwind theme; mobile layouts need density controls so tables/forms do not feel oversized.
