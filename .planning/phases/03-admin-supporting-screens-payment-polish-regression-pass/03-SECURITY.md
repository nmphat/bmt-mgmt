---
phase: 03
slug: admin-supporting-screens-payment-polish-regression-pass
status: verified
threats_open: 0
asvs_level: 1
created: 2026-06-01
register_authored_at_plan_time: true
---

# Phase 03 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Public browser to Vue SPA | Guests can read debt, member, session, and payment QR views without logging in. | Public club/session/member debt data, unpaid snapshot references, QR display data. |
| Vue SPA to Supabase REST/RPC | Frontend reads views/tables and calls RPCs while backend retains business logic and RLS authority. | Session summaries, member records, attendance, cost snapshots, payment requests, RPC payloads. |
| Guest UI to admin-only controls | Admin-only mutations are hidden in UI and guarded in handlers/router. | Session creation, member CRUD, manual cash entry, session edit/finalize/cancel actions. |
| Payment UI to external QR image provider | QR modal renders VietQR image using backend-owned amount/code plus configured bank account. | Payment amount, transfer content, bank id/account/template in image URL. |
| Realtime/polling to UI refresh | Session/payment polling and realtime refresh live UI state without writing business logic in the client. | Cost snapshot/payment status updates and attendance/session refresh triggers. |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-03-01-01 | Elevation of Privilege | Route/access inventory | mitigate | `/create-session` and `/settings` retain `requiresAuth: true` and `requiresAdmin: true`; downstream admin visibility/handler checks are verified source-wide. | closed |
| T-03-01-02 | Tampering | Supabase contract list | mitigate | `03-PRESERVATION-INVENTORY.md`, `03-REGRESSION-SOURCE-CHECKS.md`, and `03-VERIFICATION.md` record and verify exact RPC/view/table contract names before marking Phase 3 passed. | closed |
| T-03-02-01 | Elevation of Privilege | Dashboard create CTA | mitigate | `DashboardView.vue` keeps `v-if="authStore.isAdmin"` for Create Session and router guard remains unchanged. | closed |
| T-03-02-02 | Tampering | Create-session RPC payload | mitigate | `CreateSessionView.vue` still calls `create_session_with_intervals` with `p_title`, `p_start_time`, `p_end_time`, `p_court_fee`, `p_shuttle_fee`, and `p_created_by`; no frontend interval generation was added. | closed |
| T-03-03-01 | Elevation of Privilege | Member CRUD | mitigate | `MemberView.vue` keeps admin-only visibility plus four handler-level `if (!authStore.isAdmin) return` guards. | closed |
| T-03-03-02 | Tampering | Member update payload | mitigate | Member update payload remains limited to `display_name`, `role`, `is_active`, `is_permanent`, and `updated_at`; insert/update/delete Supabase calls are unchanged. | closed |
| T-03-04-01 | Tampering | QR amount/content | mitigate | `PaymentQRModal.vue` computes QR from existing snapshot/group values and queries `session_costs_snapshot`; no frontend allocation or fee authority was added. | closed |
| T-03-04-02 | Denial of Service | Payment polling | mitigate | `PaymentQRModal.vue` preserves `startPolling` guards and `stopPolling` cleanup on close, hide, paid, and unmount. | closed |
| T-03-04-03 | Elevation of Privilege | Manual cash | mitigate | `SessionDetailView.vue` keeps `openCashPayment` guarded by `authStore.isAdmin`; `ManualPaymentModal.vue` only submits existing `add_manual_payment` RPC payload after the caller gate. | closed |
| T-03-05-01 | Repudiation | Final verification artifact | mitigate | `03-VERIFICATION.md` records exact source/build evidence and is marked `status: passed` only after checks pass. | closed |
| T-03-05-02 | Elevation of Privilege | Route/admin gates | mitigate | Route meta and `authStore.isAdmin` source checks passed for guarded create/settings/member/payment/admin surfaces. | closed |
| T-03-05-03 | Tampering | Supabase/payment contracts | mitigate | Final verification greps exact Supabase contract names and payment modal invariants; `pnpm type-check` and `pnpm build` passed. | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

No accepted risks.

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-06-01 | 12 | 12 | 0 | Copilot / gsd-secure-phase |

---

## Security Audit 2026-06-01

| Metric | Count |
|--------|-------|
| Threats found | 12 |
| Closed | 12 |
| Open | 0 |

### Verification Evidence

- `pnpm type-check` passed.
- `pnpm build` passed.
- Route/admin gate grep passed for `/create-session`, `/settings`, `requiresAuth`, `requiresAdmin`, and `authStore.isAdmin`.
- Create-session RPC grep passed for `create_session_with_intervals` and exact payload keys.
- Member CRUD grep passed for admin handler guards, `members.insert`, `members.update`, `members.delete`, and preserved update fields.
- Payment grep passed for QR amount/content, `session_costs_snapshot`, polling cleanup, `payment-complete`, manual cash `add_manual_payment`, and caller-side admin gate.
- `03-VERIFICATION.md` is `status: passed` and includes final route/access, Supabase contract, payment, locale, card parity, fixed-layer, and skipped human-UAT evidence.

### Scope Notes

- This audit verifies the Phase 03 plan-time threat register; no additional retroactive STRIDE register was required because Phase 03 plans already contained formal `<threat_model>` blocks.
- Phase 03 UI work did not introduce schema/RPC/RLS changes. Backend business logic remains in Supabase RPCs/views/tables.
- Human visual UAT remained explicitly skipped/deferred for the milestone, but browser_harness smoke evidence exists separately in session artifacts and project state.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-06-01
