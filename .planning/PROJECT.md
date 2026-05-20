# Badminton Session Manager

## What This Is

Badminton Session Manager is a mobile-friendly Vue/Supabase web app for managing badminton sessions, attendance by time interval, member debt, and shared payments. The app serves both guests who only need to check and pay debt without logging in, and admins who create sessions, manage members, track attendance, finalize sessions, and confirm payments.

## Core Value

Members and guests can understand what they owe and pay it quickly, while admins can manage sessions without redoing spreadsheet work.

## Current Milestone: v1.0 UI refactor from Open Design

**Goal:** Refactor the app UI around the current Open Design mobile prototype without blindly copying it, while preserving every existing feature and Supabase-backed behavior.

**Target features:**
- Debt-first homepage with prominent guest-visible debt summary, search/selection, and single/group QR payment entry points.
- Mobile-first app shell with one-handed bottom navigation, compact header actions, role-aware guest/admin navigation, and safe-area-aware floating CTAs.
- Session detail experience split into task-focused sections for overview, attendance, costs, and payments without losing attendance matrix, realtime sync, member registration, absent flag, finalize/cancel/edit, QR/cash/group payment, or read-only guest views.
- Admin and supporting screens polished consistently: session list, create session form, member management, member debt history, login, QR payment modal, and manual payment modal.
- Feature inventory and regression guardrails so the refactor maps every existing route, component, and API-backed behavior before implementation.

## Requirements

### Validated

<!-- Existing capabilities inferred from current codebase; preserve unless explicitly changed. -->

- ✓ Guests can view the debt-focused home page and member debt summaries without logging in — existing `/` route and `view_member_debt_summary` usage.
- ✓ Guests and members can open member debt history and create QR payment flows for single or grouped unpaid items — existing `/member/:id`, `PaymentQRModal`, and `create_group_payment` usage.
- ✓ Authenticated admins can view sessions, create sessions through `create_session_with_intervals`, and open session detail pages — existing `/sessions`, `/create-session`, and `/session/:id` routes.
- ✓ Session detail supports interval attendance, adding/removing registered members, registered-but-absent marking, live cost summaries from `calculate_session_costs`, realtime updates, session editing, cancellation, finalization, QR payments, group payments, and manual cash payments.
- ✓ Admins can add, edit, and delete members, including role, active, and permanent flags.
- ✓ The app supports Vietnamese and English labels through the language store and `src/locales/messages.ts`.

### Active

<!-- Current milestone scope. Detailed REQ-IDs live in REQUIREMENTS.md. -->

- [ ] Refactor visual system and app shell for mobile-first, Vietnamese-friendly, one-handed use.
- [ ] Make debt discovery and payment the clearest guest path on the home and member-detail flows.
- [ ] Redesign session detail into a clearer mobile task cockpit without removing any session operations.
- [ ] Polish admin/supporting screens and payment modals with the same design language.
- [ ] Add explicit feature preservation checks before and after UI refactor phases.

### Out of Scope

<!-- Explicit boundaries for this milestone. -->

- Backend business logic rewrites — cost calculation, session creation, payment grouping, and manual payment logic stay in Supabase RPCs/tables/views.
- Database schema changes unless a UI preservation issue proves an existing API cannot support the current behavior.
- Building a native mobile app — this milestone remains the Vue SPA.
- Blindly copying Open Design prototype markup or prototype-only JavaScript — Open Design is a directional reference, not the implementation contract.
- Removing existing English/Vietnamese i18n coverage — new labels must keep both locales.

## Context

- The active Open Design MCP project is `badminton-mgmt`, entry `mobile-prototypes/index.html`.
- Open Design custom instructions emphasized Vietnamese-friendly fonts, mobile-friendly layouts, one-handed operation, bottom navigation, and guest debt/payment as the most important use case.
- The prototype pack includes screens for debt home, sessions, session detail, create session, members, member/admin detail, member sessions, and login. It recommends a neutral shell, white cards, indigo action color, status chips, 44px+ tap targets, bottom sheets, bottom nav, and safe-area-aware floating bars.
- The current codebase is a Vue 3 + TypeScript + TailwindCSS SPA with Supabase as the data/auth/realtime backend. Business logic must remain in Supabase RPCs and views.
- Known codebase concern: `SessionDetailView.vue` is monolithic and mixes attendance, costs, payments, member registration, realtime, polling, and session editing. This milestone should refactor UI without changing business semantics.
- Current GSD setup started with codebase mapping only; this milestone initializes the primary GSD project/requirements/roadmap docs.

## Constraints

- **Feature preservation:** No route or current user-visible capability may disappear during the UI refactor.
- **Backend boundary:** The frontend must not recalculate shared costs or replace Postgres RPC business logic.
- **Mobile-first:** Designs must work well at 360-430px widths with 44px+ tap targets and thumb-zone CTAs.
- **Access model:** Guest read/payment flows must stay available without login; admin-only create/edit/manage actions must remain protected by auth/role checks.
- **Localization:** All new user-facing strings need Vietnamese and English coverage through the existing locale pattern.
- **Type safety:** Preserve strict TypeScript compatibility and avoid widening with `any` while refactoring.
- **Planning granularity:** Roadmap is intentionally coarse and limited to 3 phases for this milestone.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use Open Design as a reference, not a source of truth | The prototype captures desired mobile direction, but it does not cover every live Vue/Supabase behavior | — Pending |
| Keep a 3-phase coarse roadmap | User requested coarse mode and exactly 3 phases | — Pending |
| Refactor UI before changing backend contracts | Current backend already owns business logic; UI risk is losing flows during redesign | — Pending |
| Prioritize guest debt/payment path | User identified guest no-login debt payment as the most important use case in Open Design instructions | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-20 after milestone v1.0 start*
