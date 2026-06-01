# External Integrations

**Analysis Date:** 2025-01-13

## APIs & External Services

**Supabase Backend:**
- Supabase - Complete BaaS platform (Database, Auth, Realtime)
  - SDK/Client: `@supabase/supabase-js` ^2.95.2
  - Initialization: `src/lib/supabase.ts`
  - Auth: Environment variables `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`

## Data Storage

**Database:**
- PostgreSQL (via Supabase)
  - Connection: Configured in `src/lib/supabase.ts` using Supabase client
  - Client: `@supabase/supabase-js` createClient
  - Authentication: Anon key (public) and optional session-based auth

**Tables (Primary Data):**
- `sessions` - Badminton session records
- `members` - Member profiles (id, user_id, role, display_name)
- `session_intervals` - 30-minute interval definitions within sessions
- `session_registrations` - Member registration records per session
- `interval_presence` - Attendance tracking (member presence per interval)

**Views (Derived Data):**
- `view_session_summary` - Aggregated session data (totals, status, court_fee_total, etc.)

**RPC Functions (Business Logic):**
- `calculate_session_costs(p_session_id)` - Computes cost breakdown per member
  - Returns: Member cost details with court fees, shuttle fees, and rounded totals
  - Invoked by: `src/views/SessionDetailView.vue`
- `create_session_with_intervals(p_title, p_start_time, p_end_time, p_court_fee, p_shuttle_fee, p_created_by)` - Creates session and auto-generates 30-min intervals
  - Invoked by: `src/views/CreateSessionView.vue`

**File Storage:**
- Not detected - Application is server-less UI; no file uploads configured

**Caching:**
- None configured - Relies on Supabase query caching and frontend state

## Authentication & Identity

**Auth Provider:**
- Supabase Auth - Built-in authentication service
  - Implementation: Session-based with JWT tokens
  - Methods used:
    - `supabase.auth.signInWithPassword()` - Email/password login
    - `supabase.auth.getSession()` - Get current session
    - `supabase.auth.onAuthStateChange()` - Listen for auth state changes
    - `supabase.auth.signOut()` - Logout
  - Location: Managed in `src/stores/auth.ts` (Pinia store)

**User Profile Model:**
- Custom member profile linked to auth user
  - Table: `members` (id, user_id, role, display_name)
  - Fetched on auth: `src/stores/auth.ts` - `fetchProfile()` method
  - Roles: 'admin' | 'member'

**Role-Based Access:**
- Admin: Can create sessions, manage attendance
- Member: Can view sessions and costs
- Anonymous: Read-only access via RLS policies (Supabase)

## Realtime & Event Streaming

**Supabase Realtime:**
- RealtimeChannel - Listens for live changes in database
  - Implementation: `import type { RealtimeChannel } from '@supabase/supabase-js'`
  - Usage: `src/views/SessionDetailView.vue` subscribes to `interval_presence` table changes
  - Pattern: Channel setup and cleanup on mount/unmount
  - Cleanup: `supabase.removeChannel(realtimeChannel)` on component destroy

## Monitoring & Observability

**Error Tracking:**
- Not configured - No external error tracking service detected

**Logging:**
- Browser console only - Uses `console.warn()`, `console.error()` for debugging
  - Examples: `src/stores/auth.ts` logs auth errors
  - Examples: `src/lib/supabase.ts` logs missing environment variables

**Toast Notifications:**
- vue-toastification 2.0.0-rc.5 - User-facing error and success notifications
  - Pattern: `const toast = useToast()` → `toast.error()`, `toast.success()`
  - Files using toasts:
    - `src/components/ManualPaymentModal.vue`
    - `src/views/CreateSessionView.vue`
    - `src/views/HomePage.vue`
    - `src/views/MemberDetailView.vue`
    - `src/views/SessionDetailView.vue`
    - `src/views/LoginView.vue`
    - `src/views/MemberView.vue`

## Environment Configuration

**Required Environment Variables:**
- `VITE_SUPABASE_URL` - Supabase project URL (e.g., `https://bufpmpehugzysvmbjlub.supabase.co`)
- `VITE_SUPABASE_ANON_KEY` - Supabase anonymous/public key for client-side access

**Configuration Source:**
- `.env` file (local development)
- `.env.example` - Template with variable names
- Vite automatically prefixes `VITE_*` variables for browser access

**Loading Pattern:**
- `import.meta.env.VITE_SUPABASE_URL` - Access in `src/lib/supabase.ts`
- `import.meta.env.VITE_SUPABASE_ANON_KEY` - Access in `src/lib/supabase.ts`

## CI/CD & Deployment

**Hosting:**
- Static hosting required (SPA deployment)
- Build output: `dist/` directory after `pnpm build`
- Client-side routing: All requests should fallback to `index.html`

**Build Process:**
- `pnpm build` executes:
  1. Type checking: `vue-tsc --build`
  2. Vite build: `vite build` (minification, bundling)
- Output: Optimized JavaScript, CSS, and static assets in `dist/`

**CI Pipeline:**
- Not configured - No CI service detected (.github/workflows/ not visible)

## API Endpoints (PostgREST)

**Supabase PostgREST API:**
- Base: Exposed via `@supabase/supabase-js` client (abstracted from raw HTTP)
- Tables accessible via client methods:
  - `.from('table_name').select()`
  - `.from('table_name').insert()`
  - `.from('table_name').update()`
  - `.from('table_name').delete()`
- RPC calls: `.rpc('function_name', { params })`

**OpenAPI Spec:**
- `docs/api.yaml` - Auto-generated Swagger/OpenAPI 2.0 specification
  - Base path: `/` (PostgreSQL public schema endpoints)
  - Schemes: HTTPS only
  - Hosts: `bufpmpehugzysvmbjlub.supabase.co:443`
  - Content types: JSON, CSV
  - Tables exposed: session_registrations, session_intervals, sessions, members, interval_presence, etc.

## Webhooks & Callbacks

**Incoming Webhooks:**
- Not configured - Frontend is UI only; no webhook endpoints

**Outgoing Webhooks:**
- Supabase Webhooks: Not detected in codebase
- Realtime subscriptions handle most update patterns instead

## Data Synchronization

**Realtime Sync Pattern:**
- Session detail view (`SessionDetailView.vue`) subscribes to `interval_presence` changes
- Updates cost summary when attendance changes
- Multi-device sync: Changes visible instantly across clients connected to same session

**Manual Refresh:**
- UI provides refresh buttons for manual data reload
- Triggered by: Session modifications, payment state changes

---

*Integration audit: 2025-01-13*
