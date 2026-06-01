# Deferred Items

## Build warning: Tailwind arbitrary `calc()` spacing

- **Found during:** Plan 03-02 final `pnpm build`
- **Issue:** Vite/esbuild warns that `+` in arbitrary Tailwind `calc(...+env(safe-area-inset-bottom))` values needs whitespace.
- **Scope:** Existing Phase 1/2 fixed-layer classes in `src/App.vue`, `src/views/SessionDetailView.vue`, `src/components/PaymentQRModal.vue`, and `src/components/ManualPaymentModal.vue`.
- **Disposition:** Resolved in `38778c0` by moving safe-area calculations to CSS helpers and narrowing Tailwind source scanning to `src`; `pnpm build` now passes without the CSS minify warning.
