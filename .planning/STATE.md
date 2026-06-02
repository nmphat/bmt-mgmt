---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: complete
stopped_at: follow-up PR creation blocked by GitHub auth
last_updated: "2026-06-01T18:12:00+07:00"
last_activity: 2026-06-01 -- attempted follow-up PR creation for fix/v1-audit-gaps; automation blocked by missing gh/token and signed-out browser
progress:
  total_phases: 3
  completed_phases: 3
  total_plans: 15
  completed_plans: 15
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-26)

**Core value:** Members and guests can understand what they owe and pay it quickly, while admins can manage sessions without redoing spreadsheet work.
**Current focus:** Milestone v1.0 complete — UI refactor verified, browser-tested, UI re-audited, mobile debt/QR feedback fixed, DB-backed bank settings restored, 2026-06-01 smoke screenshots captured, member detail session history links restored, Phase 3 security gate passed, Git origin uses SSH, Open Design review is ready-to-archive, SessionDetail bottom quick-navigation is accepted, origin/master has been merged and smoke-tested, and mark absent now works with the interval_presence-only schema

## Current Position

Phase: 03 (admin/supporting-screens-payment-polish-regression-pass) — COMPLETE
Plan: 5 of 5
Status: Milestone implementation complete; `/gsd-audit-milestone v1.0` now passes on branch `fix/v1-audit-gaps`; Phase 3 UI re-audit score is 19/24; DB-backed settings bank config fixed; browser_harness smoke suite passed 15/15; quick task 260601-nav complete; Phase 3 security gate passed with threats_open=0; Open Design final review is ready-to-archive at 19/24; origin/master merge and UI smoke complete; mark absent fix validated; PR #2 merged from `feat/refactor-ui` into `master` at head `3b30d02`; follow-up branch `fix/v1-audit-gaps` is pushed and PR creation URL is ready
Last activity: 2026-06-01 -- Tried to create the follow-up PR automatically, but `gh` is not installed, `GH_TOKEN`/`GITHUB_TOKEN` are not set, and browser_harness opened GitHub signed out. Manual URL: https://github.com/nmphat/bmt-mgmt/compare/master...fix/v1-audit-gaps?quick_pull=1

Progress: ██████████ 100%

## Performance Metrics

**Velocity:**

- Total plans completed: 15
- Average duration: —
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Mobile Shell + Debt/Payment Foundation | 5 | - | - |
| 2. Session Detail Task Cockpit | 5 | - | - |
| 3. Admin/Supporting Screens + Payment Polish + Regression Pass | 5 | 714s | 143s |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
| Phase 01-mobile-shell-debt-payment-foundation P01 | 104s | 3 tasks | 3 files |
| Phase 01-mobile-shell-debt-payment-foundation P02 | 87s | 3 tasks | 3 files |
| Phase 01-mobile-shell-debt-payment-foundation P03 | 186s | 3 tasks | 3 files |
| Phase 01-mobile-shell-debt-payment-foundation P04 | 158s | 3 tasks | 4 files |
| Phase 01-mobile-shell-debt-payment-foundation P05 | 166s | 2 tasks | 2 files |
| Phase 02-session-detail-task-cockpit P01 | 162s | 3 tasks | 3 files |
| Phase 02-session-detail-task-cockpit P02 | 222 | 3 tasks | 1 files |
| Phase 02-session-detail-task-cockpit P03 | 149 | 3 tasks | 1 files |
| Phase 02-session-detail-task-cockpit P04 | 300 | 3 tasks | 1 files |
| Phase 02-session-detail-task-cockpit P05 | 158 | 3 tasks | 2 files |
| Phase 03-admin-supporting-screens-payment-polish-regression-pass P01 | 120 | 2 tasks | 3 files |
| Phase 03-admin-supporting-screens-payment-polish-regression-pass P02 | 105 | 2 tasks | 3 files |
| Phase 03-admin-supporting-screens-payment-polish-regression-pass P03 | 172 | 2 tasks | 1 files |
| Phase 03-admin-supporting-screens-payment-polish-regression-pass P04 | 147 | 2 tasks | 2 files |
| Phase 03-admin-supporting-screens-payment-polish-regression-pass P05 | 170 | 2 tasks | 2 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- v1.0: Use MCP Open Design `badminton-mgmt` as directional UI reference, not a strict implementation contract.
- v1.0: Roadmap is coarse and exactly 3 phases.
- v1.0: Start at Phase 1 because there is no existing ROADMAP.md or completed milestone history.
- v1.0: Preserve all existing guest/admin/session/member/payment features during UI refactor.
- v1.0: Preserve current Vue/Supabase architecture and backend contracts; no frontend fee recalculation.
- v1.0: Every v1 requirement is mapped exactly once across the 3 phases.
- [Phase 01-mobile-shell-debt-payment-foundation]: Preserve public read-only access for debt, members, member detail, sessions, and session detail routes.
- [Phase 01-mobile-shell-debt-payment-foundation]: Keep member/session mutations admin-only through component gates and existing backend authority.
- [Phase 01-mobile-shell-debt-payment-foundation]: Add locale keys without adding guest-facing login copy to the public shell.
- [Phase 01-mobile-shell-debt-payment-foundation]: Plan 02 keeps mobile bottom navigation public and limited to exactly Home/Debt, Members, and Sessions.
- [Phase 01-mobile-shell-debt-payment-foundation]: Plan 02 preserves hidden /login behavior by removing guest header login affordances while keeping authenticated header actions.
- [Phase 01-mobile-shell-debt-payment-foundation]: Plan 02 redirects logout to / and token-guards authenticated debt badge fetches to avoid stale sign-out updates.
- [Phase 01-mobile-shell-debt-payment-foundation]: Plan 03 keeps debt search member-name-only while preserving total_debt sorting from view_member_debt_summary.
- [Phase 01-mobile-shell-debt-payment-foundation]: Plan 03 makes debt card body selection-only and keeps Details as the sole member-detail navigation from mobile debt cards.
- [Phase 01-mobile-shell-debt-payment-foundation]: Plan 03 keeps QR amounts backend-owned through snapshots/create_group_payment and does not add frontend fee allocation.
- [Phase 01-mobile-shell-debt-payment-foundation]: Plan 04 keeps QR payment-complete as a refresh-only signal while explicit close/Done owns sheet dismissal and payload reset.
- [Phase 01-mobile-shell-debt-payment-foundation]: Plan 04 keeps add_manual_payment payload unchanged and requires cash entry plus review confirmation before RPC submission.
- [Phase 01-mobile-shell-debt-payment-foundation]: Plan 05 skipped/deferred human visual UAT per explicit user instruction and used automated/source/build/access evidence instead.
- [Phase 01-mobile-shell-debt-payment-foundation]: Session-detail mutation gates must use authStore.isAdmin rather than authenticated state to preserve public read-only access.
- [Phase 02-session-detail-task-cockpit]: Session detail editability is centralized on authStore.isAdmin plus open status, preserving public read-only /session/:id access.
- [Phase 02-session-detail-task-cockpit]: Registered-but-absent members are blocked from interval_presence upserts before any Supabase mutation.
- [Phase 02-session-detail-task-cockpit]: Manual cash modal opening is explicitly admin-only while QR payment entry points remain public for unpaid snapshots.
- [Phase 02-session-detail-task-cockpit]: Plan 02 keeps cockpit shell implementation in SessionDetailView.vue to minimize contract drift before later section-body conversions.
- [Phase 02-session-detail-task-cockpit]: Plan 02 uses status-derived default active section with click-driven sticky mini-tabs and no new scroll observer dependency.
- [Phase 02-session-detail-task-cockpit]: 2026-06-01 user visual feedback clarified the mobile quick-navigation ribbon should remain, be fixed immediately above the bottom app nav, and stay visible for one-handed use. Subjective UI feedback requires confirming the desired approach before removing/restructuring UI.
- [Phase 02-session-detail-task-cockpit]: 2026-06-01 post-merge schema fix changes mark absent to use `interval_presence` as the only source of truth: clearing all presence rows marks a registered member absent, and checking any interval is the undo path. The removed `session_registrations.is_registered_not_attended` column must not be referenced in source.
- [Phase 02-session-detail-task-cockpit]: Plan 02 preserves existing sessions.update/finalize_session handlers and centralized isSessionEditable gates while moving controls into Overview.
- [Phase 02-session-detail-task-cockpit]: Plan 03 keeps attendance section work in SessionDetailView.vue to avoid behavior drift in the highest-risk attendance surface.
- [Phase 02-session-detail-task-cockpit]: Plan 03 adds mobile attendance cards as an additive layout while preserving the desktop interval matrix.
- [Phase 02-session-detail-task-cockpit]: Plan 03 reuses existing attendance Supabase handlers and adds no schema changes or frontend fee logic.
- [Phase 02-session-detail-task-cockpit]: Plan 04 preserved backend-owned amounts by displaying calculate_session_costs and session_costs_snapshot fields only.
- [Phase 02-session-detail-task-cockpit]: Plan 04 uses additive mobile cards plus preserved desktop tables for costs and payments.
- [Phase 02-session-detail-task-cockpit]: Plan 04 removed session-detail bottom-6 group payment offset in favor of the Phase 2 safe-area offset above bottom nav.
- [Phase 02-session-detail-task-cockpit]: Phase 2 validation uses automated/source/build evidence because the user explicitly skipped human UAT.
- [Phase 02-session-detail-task-cockpit]: Session detail refreshes queue one pending full/cost refresh instead of dropping in-flight realtime, polling, manual, or payment-complete refresh requests.
- [Phase 03-admin-supporting-screens-payment-polish-regression-pass]: Phase 3 begins with source-verifiable preservation checks before UI edits.
- [Phase 03-admin-supporting-screens-payment-polish-regression-pass]: Human visual UAT remains skipped/deferred for this phase; automated source checks, type-check, and build are the validation gate.
- [Phase 03-admin-supporting-screens-payment-polish-regression-pass]: Locale scaffold adds only required Phase 3 session/create-session/member copy and no deferred feature copy.
- [Phase 03-admin-supporting-screens-payment-polish-regression-pass]: Preserved /sessions as public read-only while keeping the Create Session affordance behind authStore.isAdmin.
- [Phase 03-admin-supporting-screens-payment-polish-regression-pass]: Preserved /create-session router meta and create_session_with_intervals payload keys while changing only mobile presentation and fallback error copy.
- [Phase 03-admin-supporting-screens-payment-polish-regression-pass]: Kept validation source-based and automated; human visual UAT remains skipped/deferred for Phase 3.
- [Phase 03-admin-supporting-screens-payment-polish-regression-pass]: Kept MemberView.vue as the implementation seam to avoid route, Supabase, or auth contract drift.
- [Phase 03-admin-supporting-screens-payment-polish-regression-pass]: Added mobile member cards additively and retained the desktop member table at the md breakpoint.
- [Phase 03-admin-supporting-screens-payment-polish-regression-pass]: Preserved member CRUD calls, admin visibility gates, handler guards, create-another, loading, toasts, and confirmation semantics while polishing mobile controls.
- [Phase 03-admin-supporting-screens-payment-polish-regression-pass]: Kept PaymentQRModal.vue as the single QR/group QR surface for home, member detail, and session detail.
- [Phase 03-admin-supporting-screens-payment-polish-regression-pass]: Kept ManualPaymentModal.vue as the cash entry/review surface and preserved SessionDetailView.vue as the admin gate.
- [Phase 03-admin-supporting-screens-payment-polish-regression-pass]: Limited payment modal changes to presentation so Supabase contracts, polling cleanup, and explicit close/Done semantics remain unchanged.
- [Phase 03-admin-supporting-screens-payment-polish-regression-pass]: Kept Phase 3 verification source/build-based because human visual UAT and 360/390/430px browser sweeps were explicitly skipped/deferred.
- [Phase 03-admin-supporting-screens-payment-polish-regression-pass]: Marked 03-VERIFICATION.md as in_progress after Task 1 and only changed it to passed after all final checks passed.
- [Phase 03-admin-supporting-screens-payment-polish-regression-pass]: Documented existing untracked Open Design artifacts and modified .planning/config.json as intentionally not committed.

### Pending Todos

- Optional: low-priority hardening for dense financial rows/cards — add non-color cues where state is primarily red/green amount emphasis.
- Optional: full authenticated admin mutation smoke still requires explicit admin credentials and preferably a dev/test branch.

### Blockers/Concerns

None currently.

Known follow-up notes:

- Browser harness smoke passed on 2026-05-27 for mobile `/`, `/sessions`, `/members`, `/login`, `/create-session` guard and desktop `/sessions`, `/members`; no visible error text or global overflow was detected.
- Full browser_harness screenshot sweep captured 14 grouped screenshots; the `03-session-detail-readonly` `Tiền sân NaN ₫` finding is fixed in `bad7cc0` and retested on mobile/desktop.
- Phase 3 UI review priority findings were fixed in `38778c0`: typography classes normalized in changed Phase 3 surfaces, safe-area `calc()` arbitrary Tailwind classes replaced with CSS helpers plus Tailwind source narrowed to `src`, exact CTA copy aligned, and clipboard failure now surfaces a toast.
- UI review fix retest passed with `pnpm type-check`, `pnpm build` with no CSS minify warning, and browser_harness 8/8 affected route+viewport checks. Screenshots are under `/home/phatngo/.copilot/session-state/07dceea9-e423-4717-900e-03af338018ed/files/browser-harness-20260527-ui-review-fixes`.
- Fresh Phase 3 UI re-audit score is 19/24 after `16608b0` moved manual payment footer CSS to top-level scoped style. Remaining top fixes: typography token drift, SessionDetailView user-facing error feedback, and compact/icon-only accessibility/tap-target gaps.
- Mobile debt/QR feedback fixed in `7a1ad79`: debt cards show full member names, QR CTA labels are compact for iPhone SE, and group QR polling checks `snapshot_ids` instead of group codes so empty results stay pending. Browser_harness evidence is under `/home/phatngo/.copilot/session-state/07dceea9-e423-4717-900e-03af338018ed/files/browser-harness-20260527-home-feedback-fix`.
- Settings route fixed in `5e890b3`: admin menu now opens `/settings`, unauthenticated access redirects to `/login`, the settings page displays payment QR config, and VietQR generation uses `TPB`/TPBank. Browser_harness evidence is under `/home/phatngo/.copilot/session-state/07dceea9-e423-4717-900e-03af338018ed/files/browser-harness-20260527-settings-fix`.
- Bank config moved to DB-backed Settings in `841cfac`: `src/stores/bankConfig.ts` reads/writes `public.bank_config`, Settings supports add/set-default/delete, QR modal uses the active DB config, and fallback/seed is TPB `10003392871` / `CLB CAU LONG BMT`. Supabase migration `restore_bank_config_settings` seeded TPB active + MB inactive and changed `bank_config` RLS to public read/admin write. Browser_harness evidence is under `/home/phatngo/.copilot/session-state/07dceea9-e423-4717-900e-03af338018ed/files/browser-harness-20260527-bank-config-settings`.
- Browser harness MCP checked on 2026-06-01: `browser_harness run` is operational; `browser_harness doctor` initially reported daemon/connection failures, then passed daemon + active browser connection after reload/run. Optional `profile-use` and `BROWSER_USE_API_KEY` remain unavailable and are only needed for cloud/profile sync.
- Smoke test cases and categorized screenshots captured on 2026-06-01: 15/15 passed using CDP certificate bypass because initial Supabase REST calls failed with `ERR_CERT_AUTHORITY_INVALID`. Evidence is under `/home/phatngo/.copilot/session-state/2d00395f-5b2a-4898-a036-90f73efbadd6/files/browser-harness-20260601-smoke` with `TEST-CASES.md`, `manifest.json`, and category folders `01-public-debt` through `07-auth-admin-guards`.
- 2026-06-01 smoke policy: production-data safety preserved by not executing admin mutations, manual payments, session mutations, or group QR creation; admin-only create/settings were covered by guest guards, group payment by selection bar, and single QR by existing member snapshot modal.
- Quick task `260601-nav` fixed member detail session history navigation in `1c4f7a4`: mobile cards and desktop rows on `/member/:id` now open `/session/:session_id`, while QR buttons stop propagation and still open the payment modal. Browser_harness evidence is under `/home/phatngo/.copilot/session-state/2d00395f-5b2a-4898-a036-90f73efbadd6/files/member-detail-session-nav-20260601`.
- Phase 3 security gate completed on 2026-06-01: `03-SECURITY.md` has `status: verified`, `threats_open: 0`, 12/12 plan-time threats closed, and source/type/build evidence for route/admin gates, Supabase RPC contracts, member CRUD guards, and payment modal semantics.
- Git remote `origin` is now SSH: `git@github.com:nmphat/bmt-mgmt.git`.
- Open Design daemon is running at `http://127.0.0.1:17456` with web UI `http://127.0.0.1:17573`. The MCP tool wrapper still reports `http://127.0.0.1:7456` unreachable, so import was done through the daemon API at `17456`.
- Open Design UI review packet was imported into project `bmt-ui-review-20260601-0753` (`badminton-mgmt UI review 2026-06-01`) with 21 files. Web project URL: `http://127.0.0.1:17573/projects/bmt-ui-review-20260601-0753`. Daemon preview URL: `http://127.0.0.1:17456/api/projects/bmt-ui-review-20260601-0753/preview/35c911bd-19f8-421c-95ff-8e94b6a76b6a/index.html`. Direct preview was browser_harness verified and screenshot evidence is `/home/phatngo/.copilot/session-state/2d00395f-5b2a-4898-a036-90f73efbadd6/files/open-design-ui-review-20260601/verification/open-design-direct-preview-updated.png`. Source packet remains under `/home/phatngo/.copilot/session-state/2d00395f-5b2a-4898-a036-90f73efbadd6/files/open-design-ui-review-20260601`.
- Open Design review run: Claude attempt `81012363-c29f-4168-acad-2bdf7ad8e2b4` failed with `AGENT_AUTH_REQUIRED`; Copilot retry `95b5c036-9bdd-46c5-840d-fe614a3d0a17` succeeded. Review outputs were copied to `/home/phatngo/.copilot/session-state/2d00395f-5b2a-4898-a036-90f73efbadd6/files/open-design-ui-review-20260601/OPEN-DESIGN-UI-REVIEW.md` and `review-findings.json`. Verdict: `fix-before-archive`, score 14/24, top findings: repeated mobile locked-state messaging, compact/icon-only tap targets/accessibility, SessionDetailView error feedback, typography token drift, dense mobile card stacks, generic auth guard login copy, and missing non-mutating admin/payment mutation evidence.
- Open Design fix-before-archive remediation completed on 2026-06-01: `SessionDetailView.vue` now uses one full locked-session banner plus compact locked chips, adds inline retryable page/action/payment error feedback, and surfaces attendance mutation failures through toast + inline alerts; `MemberDetailView.vue` adds 44px accessible compact controls and collapses mobile history after four sessions; `/create-session` and `/settings` guest redirects preserve the attempted route and show route-specific login copy; global typography tokens were normalized to 16px base. Verification passed with `pnpm type-check`, `pnpm build`, and targeted browser_harness smoke 5/5. Evidence and screenshots are under `/home/phatngo/.copilot/session-state/2d00395f-5b2a-4898-a036-90f73efbadd6/files/open-design-ui-review-20260601/remediation-evidence` and were uploaded into Open Design project `bmt-ui-review-20260601-0753` under `remediation-evidence/`.
- Open Design remediation re-review completed on 2026-06-01: Copilot run `95acc6cc-0b43-496d-99df-1859669df6d2` succeeded and produced `/home/phatngo/.copilot/session-state/2d00395f-5b2a-4898-a036-90f73efbadd6/files/open-design-ui-review-20260601/OPEN-DESIGN-UI-REVIEW-rerun.md` plus `review-findings-rerun.json`. Verdict: `needs-more-evidence`, score 16/24. Cleared: repeated locked-state messaging, reviewed member-detail QR tap targets, mobile member history density, and auth guard route context. Remaining archive gates are evidence-only: typography source/computed metrics and production-safe or mocked `SessionDetailView` fetch/action/payment failure-state evidence.
- Open Design archive evidence was added on 2026-06-01 under `/home/phatngo/.copilot/session-state/2d00395f-5b2a-4898-a036-90f73efbadd6/files/open-design-ui-review-20260601/archive-evidence` and uploaded to project `bmt-ui-review-20260601-0753`: computed typography metrics, production-safe mocked `SessionDetailView` failure evidence, and screenshots proving Supabase REST/RPC/update requests were blocked before production writes.
- Open Design final re-review completed on 2026-06-01: safe failure-copy remediation replaced raw exception text with localized operator-safe messages in `SessionDetailView.vue`, Copilot run `a97059f8-5e04-4148-9e00-e2bb1ea1e58c` succeeded, and outputs were copied to `/home/phatngo/.copilot/session-state/2d00395f-5b2a-4898-a036-90f73efbadd6/files/open-design-ui-review-20260601/OPEN-DESIGN-UI-REVIEW-safe-copy.md` plus `review-findings-safe-copy.json`. Verdict: `ready-to-archive`, score 19/24. All archive gates cleared; only UI-R2 low non-blocking color/accessibility hardening remains.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260525-m9g | Browser harness smoke test, cert bypass, and mobile/desktop screenshots for `http://localhost:5173/`. | 2026-05-25 | dfa6974 | [260525-m9g-h-y-ki-m-tra-mcp-harness-browser-testing](./quick/260525-m9g-h-y-ki-m-tra-mcp-harness-browser-testing/) |
| 260601-nav | Member detail session history navigates to session detail when clicking a session. | 2026-06-01 | 1c4f7a4 | [260601-nav-member-detail-session-navigation](./quick/260601-nav-member-detail-session-navigation/) |

## Session Continuity

Last session: 2026-06-01T16:05:00+07:00
Stopped at: Open Design final re-review complete; verdict ready-to-archive, score 19/24
Resume file: .planning/HANDOFF.json
Next command: ask user for next action; recommended proceed to `/gsd-complete-milestone`
