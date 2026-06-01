# Brand spec — Badminton Management

Source observed: `/home/phatngo/badminton-mgmt/src/assets/main.css` and Vue templates using Tailwind utility palette.

## Tokens

```css
:root {
  --bg:      oklch(98.5% 0.002 247);
  --surface: oklch(100% 0 0);
  --fg:      oklch(21% 0.034 264);
  --muted:   oklch(44.6% 0.03 257);
  --border:  oklch(92.8% 0.006 264);
  --accent:  oklch(51.1% 0.262 276);

  --font-display: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', system-ui, sans-serif;
  --font-body:    -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', system-ui, sans-serif;
  --font-mono:    ui-monospace, 'SF Mono', Menlo, Monaco, Consolas, monospace;
}
```

## Observed posture rules

- Neutral app shell: `gray-50` page, white cards, gray dividers.
- Primary action accent: indigo `600/700`, mostly for admin CTAs and links.
- Status semantics: blue=open, orange=waiting/payment, green=done/paid, gray=cancelled/neutral.
- Card radius: 8–12px, low elevation, hairline borders often better than shadow on mobile.
- Current type scale intentionally enlarged globally in Tailwind theme; mobile layouts need density controls so tables/forms do not feel oversized.
