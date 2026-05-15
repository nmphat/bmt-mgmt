# Architecture

**Analysis Date:** 2025-01-17

## Pattern Overview

**Overall:** Client-side Single Page Application (SPA) with Supabase backend integration

**Key Characteristics:**
- Vue 3 Composition API with TypeScript strict mode
- Real-time reactive UI synchronized via Supabase Realtime subscriptions
- Separation of business logic: backend (Supabase RPC/Views) vs presentation (Vue components)
- Mobile-first responsive design using TailwindCSS
- Global state management for authentication and language preferences via Pinia

## Layers

**Presentation Layer (Views & Components):**
- Purpose: Display data to users, handle user interactions
- Location: `src/views/` (page-level), `src/components/` (reusable UI)
- Contains: Vue components (`.vue` files with `<script setup>`)
- Depends on: Types, Stores, Lib (Supabase client)
- Used by: Vue Router, App.vue

**State Management Layer:**
- Purpose: Manage global application state (authentication, language)
- Location: `src/stores/`
- Contains: Pinia stores (`auth.ts`, `lang.ts`, `counter.ts`)
- Depends on: Lib (Supabase), Types
- Used by: Views, Components, Router guards

**Data Access Layer:**
- Purpose: Initialize and expose Supabase client
- Location: `src/lib/supabase.ts`
- Contains: Supabase client creation with environment variables
- Depends on: Environment config (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`)
- Used by: Stores, Views, Components

**Utility Layer:**
- Purpose: Provide reusable formatting and helper functions
- Location: `src/utils/`
- Contains: Formatters (`formatters.ts`), time helpers (`time.ts`)
- Depends on: date-fns library
- Used by: Views, Components

**Type Definition Layer:**
- Purpose: Define TypeScript interfaces for type safety across application
- Location: `src/types/index.ts`
- Contains: `SessionSummary`, `MemberCost`, `MemberDebtSummary`, `CostSnapshot`, etc.
- Depends on: Supabase types
- Used by: All layers (Stores, Views, Components)

## Data Flow

**Authentication & Session Initialization:**

1. App.vue mounts → calls `authStore.initialize()`
2. Auth store queries `supabase.auth.getSession()`
3. If user exists → fetch `members` table to load `MemberProfile`
4. Set up `onAuthStateChange` listener for session changes
5. Router guards check `authStore.isAuthenticated` and `authStore.isAdmin` before allowing navigation

**Session Detail Page Flow:**

1. User navigates to `/session/:id` (SessionDetailView.vue)
2. Component fetches:
   - Session data from `view_session_summary`
   - Intervals from `session_intervals`
   - Registrations from `session_registrations`
3. Real-time subscription established on `interval_presence` table
4. User toggles member attendance → upsert to `interval_presence`
5. Realtime payload received → component updates UI
6. Cost summary fetches RPC `calculate_session_costs(p_session_id)` on each attendance change

**Home Page Flow (Member Debt Summary):**

1. HomePage.vue mounts → fetchDebts()
2. Query `view_member_debt_summary` with pagination
3. Display member debt list sorted by total_debt
4. User clicks member → navigate to payment details
5. Optional: Show payment QR or manual payment modal

**Create Session Flow (Admin Only):**

1. Router guard checks `requiresAdmin: true` before loading CreateSessionView
2. User fills form (title, date, times, fees)
3. Submit → call RPC `create_session_with_intervals()`
4. RPC creates session and generates 30-min intervals automatically
5. Success → navigate to `/session/:id`

**State Management:**
- Auth state persists via Supabase session tokens
- Language preference persists via localStorage (lang store)
- View-level state (loading, UI toggles) stored in component refs
- No Redux/global store pattern; Pinia used minimally for cross-component concerns

## Key Abstractions

**Supabase Client Singleton:**
- Purpose: Centralized Supabase instance with anon role capabilities
- Examples: `src/lib/supabase.ts`
- Pattern: Single export used throughout app; RLS policies enforce data access

**Pinia Auth Store:**
- Purpose: Encapsulate authentication logic and state
- Examples: `src/stores/auth.ts`
- Pattern: Computed properties expose `isAuthenticated` and `isAdmin` for guard logic

**TypeScript Interfaces:**
- Purpose: Ensure type safety across Supabase data models
- Examples: `SessionSummary`, `MemberCost`, `CostSnapshot` in `src/types/index.ts`
- Pattern: Match exact Supabase table/view schemas; enable IDE autocomplete

**Component Composition:**
- Purpose: Decompose pages into reusable pieces
- Examples: `AppHeader.vue`, `HomeDebtTable.vue`, `PaymentQRModal.vue`, `ManualPaymentModal.vue`
- Pattern: Single Responsibility; modals handle specific features (QR code, manual payment)

## Entry Points

**HTML Entry:**
- Location: `index.html`
- Triggers: Browser loads page
- Responsibilities: Define root DOM element (`<div id="app">`), load main.ts

**JavaScript/TypeScript Entry:**
- Location: `src/main.ts`
- Triggers: HTML script tag loads it
- Responsibilities: Create Vue app, mount Pinia, load Router, mount to #app

**Vue Application Root:**
- Location: `src/App.vue`
- Triggers: main.ts calls `app.mount('#app')`
- Responsibilities: Render AppHeader globally, initialize auth on mount, render router-view

**Router Entry:**
- Location: `src/router/index.ts`
- Triggers: App.vue renders `<router-view />`
- Responsibilities: Define all routes, enforce auth guards, lazy-load view components

## Error Handling

**Strategy:** Toast notifications for user feedback; console logging for debug

**Patterns:**
- Supabase query errors caught in try-catch, converted to toast messages via `vue-toastification`
- Auth errors (e.g., invalid credentials) shown to user in LoginView
- Network/API errors logged to console and notified via toast
- Type errors caught at compile time via TypeScript strict mode
- Example from `src/views/HomePage.vue`: `try { fetchDebts() } catch (error) { toast.error(...) }`

## Cross-Cutting Concerns

**Logging:** Console log/warn/error; no structured logging framework. Auth errors logged to warn/error level.

**Validation:** Client-side form validation before submission; server-side RLS + constraints enforce data integrity. No separate validation layer.

**Authentication:** Supabase Auth (email/password); anon role for public data, authenticated role for protected operations. RLS policies on backend enforce authorization.

**Real-time Sync:** Supabase Realtime subscriptions on `interval_presence` and views to auto-update components when data changes across devices. Components manage subscription cleanup on unmount.

**Localization:** Language store (`src/stores/lang.ts`) manages i18n; `date-fns/locale` used for date formatting; hardcoded message keys in `src/locales/messages.ts`.

---

*Architecture analysis: 2025-01-17*
