# Deferred Items

## Build warning: Tailwind arbitrary `calc()` spacing

- **Found during:** Plan 03-02 final `pnpm build`
- **Issue:** Vite/esbuild warns that `+` in arbitrary Tailwind `calc(...+env(safe-area-inset-bottom))` values needs whitespace.
- **Scope:** Existing Phase 1/2 fixed-layer classes in `src/App.vue`, `src/views/SessionDetailView.vue`, `src/components/PaymentQRModal.vue`, and `src/components/ManualPaymentModal.vue`.
- **Disposition:** Out of scope for Plan 03-02 because this plan only modifies `DashboardView.vue` and `CreateSessionView.vue`; build still passes.
