# Brand spec — Badminton Management

Source observed: `src/assets/main.css` and Vue templates using Tailwind utility classes directly (no custom color/font CSS variables exist in code — see note below).

## Tokens (thực tế đang chạy, không phải mục tiêu thiết kế)

`src/assets/main.css` chỉ khai báo lại type scale của Tailwind v4, không có color token hay font-family riêng nào:

```css
@theme {
  --text-xs: 0.75rem;
  --text-sm: 0.875rem;
  --text-base: 1rem;
  --text-lg: 1.125rem;
  --text-xl: 1.25rem;
  --text-2xl: 1.5rem;
  --text-3xl: 2rem;
}
html { font-size: 16px; }
```

- **Màu:** không có CSS variable nào — mọi nơi dùng thẳng utility class Tailwind (`bg-indigo-600`, `text-gray-900`, `border-gray-200`, ...). Đây là quyết định có chủ đích (2026-09-14): app hiện đã nhất quán màu (`indigo-600` là accent duy nhất xuyên suốt) mà không cần lớp token riêng; thêm token trừu tượng vào lúc này là refactor không có lý do thực tế đi kèm.
- **Font:** không override `font-family` — dùng nguyên stack mặc định của Tailwind v4 preflight (`ui-sans-serif, system-ui, -apple-system, "Segoe UI", ...`), vốn đã tương đương tinh thần "system font" mà bản spec cũ mô tả, chỉ khác là không đi qua biến CSS tường minh.
- **Mono:** không dùng font-mono ở đâu trong app hiện tại (không có màn hình data-dense cần tabular figures).

## Observed posture rules

- Neutral app shell: `gray-50` page, white cards, gray dividers.
- Primary action accent: indigo `600/700`, mostly for admin CTAs and links.
- Status semantics: blue=open, orange=waiting/payment, green=done/paid, gray=cancelled/neutral.
- Card radius: 8–12px, low elevation, hairline borders often better than shadow on mobile.
- Current type scale intentionally enlarged globally in Tailwind theme; mobile layouts need density controls so tables/forms do not feel oversized.
