# Codebase Concerns

**Analysis Date:** 2025-01-15

## Architecture & Design Issues

### Monolithic Component: SessionDetailView.vue

**Issue:** `src/views/SessionDetailView.vue` is 1290 lines, mixing multiple concerns into a single component:
- Session management (create, edit, finalize, cancel)
- Member registration and removal
- Attendance matrix tracking
- Cost calculations and breakdown
- Payment QR modal handling
- Cash payment modal handling
- Realtime subscriptions
- Polling logic

**Files:** `src/views/SessionDetailView.vue`

**Impact:**
- Extremely difficult to test individual features
- High cognitive load for developers
- Difficult to reuse logic in other components
- Risk of introducing bugs when modifying one feature affects others
- Component becomes slower as it grows

**Fix Approach:**
- Extract attendance matrix logic into `AttendanceMatrix.vue` component
- Extract cost breakdown into `CostBreakdown.vue` component
- Extract payment handling into `PaymentHandler.vue` component (already partially done with modals)
- Create composable hooks for realtime sync and polling logic
- Use these sub-components to compose SessionDetailView

---

## Performance Bottlenecks

### Simultaneous Polling and Realtime (Race Condition Risk)

**Issue:** Both polling (every 10 seconds) and Realtime subscriptions are active simultaneously:
- Line 512-514: `pollTimer = setInterval(() => { fetchData(true) }, 10_000)`
- Line 524-575: Realtime subscription initialized with multiple handlers
- Line 578-583: Both started in `onMounted`

**Files:** `src/views/SessionDetailView.vue`

**Impact:**
- Redundant API calls (every 10 seconds + realtime updates)
- Potential race conditions where realtime and polling fetch simultaneously
- Server load doubled for no benefit
- Network bandwidth wasted
- UI updates could arrive out-of-order

**Current Mitigation:** Both systems fetch independently; there's a flag `isFetching` to prevent concurrent fetches from user action

**Recommendations:**
- **Remove polling entirely** if Realtime is stable and production-ready
- If Realtime is unreliable, use polling as fallback, but not simultaneously
- Add a hybrid approach: Start with polling, upgrade to Realtime when subscribed successfully, fallback to polling on subscription error
- Monitor Realtime subscription health and reconnect if broken

---

### Manual Data Refresh Triggers Extra Fetch

**Issue:** User can click refresh button (line 604) while polling is active:
- Refresh button calls `fetchData()` immediately
- Polling timer will also call `fetchData(true)` up to 10 seconds later
- Creates potential for 2 fetches within seconds

**Files:** `src/views/SessionDetailView.vue` line 604, 510-514

**Impact:** Unnecessary API calls spike whenever user manually refreshes during polling interval

**Fix Approach:** Implement fetch debouncing/throttling to prevent duplicate calls within a time window (e.g., 2-3 seconds)

---

## Type Safety & Code Quality Issues

### Unsafe `any` Type Usage

**Issue:** Multiple files use `any` type to bypass type checking:

- `src/views/SessionDetailView.vue` line 109: `let pollTimer: any = null`
- `src/views/SessionDetailView.vue` line 231: `.map((s: any) =>` when mapping cost snapshots
- `src/views/HomePage.vue` line 105: `data.forEach((row: any) =>` when processing debt data
- `src/views/MemberDetailView.vue` line 27: `const selectedSnapshot = ref<any>(null)` with comment "using any to bypass type mismatch"
- `src/stores/lang.ts` line 15: `let value: any = messages[currentLang.value]`

**Files:** SessionDetailView.vue, HomePage.vue, MemberDetailView.vue, lang.ts

**Impact:**
- Loses type safety during development
- Type errors only caught at runtime
- IDE autocomplete doesn't work properly
- Bugs can silently pass through type checking with `pnpm type-check`

**Fix Approach:**
- Replace `any` with specific types or generics
- For `pollTimer`: Use `NodeJS.Timeout | null`
- For snapshot mapping: Create proper `CostSnapshot` type or interface
- For lang.ts: Ensure messages structure matches expected keys
- Add ESLint rule to warn on `any` usage

---

### Missing Translation Key Fallback

**Issue:** Line 233 in `src/views/SessionDetailView.vue` uses translation key that may not exist:
```typescript
display_name: s.member?.display_name || t.value('common.unknown')
```

**Files:** `src/views/SessionDetailView.vue` line 233

**Impact:**
- If `common.unknown` is not in `src/locales/messages.ts`, displays the key itself or blank
- Inconsistent user experience across languages
- Hard to track missing translations

**Fix Approach:**
- Verify all translation keys exist in both `vi` and `en` locales
- Add script to validate translation completeness
- Create fallback mechanism that logs missing keys

---

## Security & Initialization Issues

### Supabase Client Silently Fails on Missing Env Variables

**Issue:** `src/lib/supabase.ts` creates client with empty strings if env vars are missing:
```typescript
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseAnonKey) {
  console.warn('Supabase URL or Anon Key is missing. Check your .env file.')
}

export const supabase = createClient(supabaseUrl || '', supabaseAnonKey || '')
```

**Files:** `src/lib/supabase.ts` lines 6-10

**Impact:**
- Client is created with empty credentials
- All API calls will fail cryptically (network errors, not clear auth issue)
- `console.warn` is the only signal (may be missed in logs)
- Development environment can run with broken setup without clear indication

**Fix Approach:**
- Throw error if env vars missing (fail fast)
- Add validation in `main.ts` before app initialization
- Show user-friendly error message on init failure
- Consider environment validation step in build process

---

### No Frontend Verification of RLS Policies

**Issue:** Documentation mentions RLS is set up on backend, but frontend has no way to verify:
- No error handling for RLS denials
- Assumes RLS policies are correctly configured
- If RLS is misconfigured, frontend will silently get empty data or cryptic errors

**Files:** All API calls throughout the app

**Impact:**
- If backend misconfigures RLS, security breach goes unnoticed
- Difficult to debug why user sees no data
- No audit trail of RLS failures

**Fix Approach:**
- Add `onError` handlers to Supabase queries to catch "PGRST301" (permission denied) errors
- Create error interceptor that recognizes RLS errors
- Log RLS failures with detailed context
- Document which operations require which RLS roles

---

## Error Handling & Robustness Issues

### Missing Error Boundary Component

**Issue:** No error boundary component to catch component-level errors:
- If any component throws, entire app crashes
- No recovery mechanism

**Files:** All Vue components

**Impact:**
- Single component error = app unusable
- No graceful degradation
- User must refresh page to recover

**Fix Approach:**
- Create `ErrorBoundary.vue` component using `onErrorCaptured` lifecycle hook
- Wrap major view sections with error boundary
- Display fallback UI with error details and retry button

---

### Optimistic Updates Without Comprehensive Error Handling

**Issue:** `togglePresence` (line 380-414) and `toggleAbsent` (line 417-436) use optimistic updates but may not handle all error cases:

```typescript
// togglePresence
if (presence.value[memberId]) {
  presence.value[memberId][intervalId] = newValue  // Optimistic update
}
const { error } = await supabase.from('interval_presence').upsert(...)
if (error) {
  if (presence.value[memberId]) {
    presence.value[memberId][intervalId] = !newValue  // Rollback
  }
  console.error('Error toggling presence:', error)
} else {
  await fetchCosts()
}
```

**Files:** `src/views/SessionDetailView.vue` lines 380-436

**Impact:**
- If multiple rapid updates happen, rollbacks may overwrite pending changes
- `fetchCosts()` may race with other updates if multiple users active
- Error is only logged, not shown to user via toast
- No way for user to know update failed

**Fix Approach:**
- Add per-row loading state to prevent rapid re-clicks
- Show toast on error so user knows update failed
- Add retry mechanism for failed updates
- Implement update queue to serialize conflicting changes

---

### Realtime Subscription Error Handling Missing

**Issue:** `initRealtime()` (line 524-576) creates subscription but has no error handler:
```typescript
realtimeChannel = supabase
  .channel(`session-${sessionId}`)
  .on('postgres_changes', ...)
  .subscribe()  // No error callback
```

**Files:** `src/views/SessionDetailView.vue` line 524-575

**Impact:**
- Subscription failures are silent
- User won't know if realtime is working or falling back to polling
- No indication of network issues

**Fix Approach:**
- Add error callback: `.subscribe((status) => { if (status === 'SUBSCRIPTION_ERROR') { ... } })`
- Log subscription errors
- Fallback to polling if subscription fails
- Monitor subscription status in UI (show "syncing..." vs "realtime" indicator)

---

## Testing & Quality Issues

### No Test Coverage

**Issue:** Zero test files found in entire codebase
- 0 unit tests
- 0 integration tests
- 0 E2E tests

**Files:** All components and utilities

**Impact:**
- Regression bugs introduced on every change
- Refactoring is risky
- Cannot confidently verify bug fixes
- No confidence in API integration contracts

**Risk Areas Without Tests:**
- Session creation and finalization flow
- Cost calculation accuracy
- Member registration/removal
- Payment snapshot creation
- Attendance matrix state management
- Realtime data sync
- Optimistic update rollbacks

**Fix Approach:**
- Add Vitest for unit tests
- Test core composables and utilities first (highest ROI)
- Add integration tests for key user flows (create session → add members → toggle attendance → finalize)
- Add E2E tests with Playwright for critical paths

---

## Code Quality Issues

### Console Logging Left in Production Code

**Issue:** Multiple `console.log` and `console.error` statements throughout codebase:

- `src/views/HomePage.vue` line 118: `console.log('Snapshot IDs:', snapshotIds)`
- `src/views/HomePage.vue` line 127: `console.log('Group Data (RPC):', rpcResponse)`
- `src/views/SessionDetailView.vue` line 213: `console.error('Error fetching session details:', error)`
- `src/stores/auth.ts` line 29: `console.warn('Error fetching member profile:', error)`

**Files:** HomePage.vue, SessionDetailView.vue, ManualPaymentModal.vue, PaymentQRModal.vue, auth.ts, supabase.ts, and others

**Impact:**
- Exposes sensitive data in browser console (snapshot IDs, member details)
- Production logs pollute browser DevTools
- No structured logging for debugging
- Harder to find actual issues in logs

**Fix Approach:**
- Remove `console.log` statements
- Replace `console.error/warn` with structured logging library (e.g., `pino-browser`)
- Create logger abstraction with configurable levels
- Log only to server in production

---

### No Input Validation Before API Calls

**Issue:** API calls often lack validation:
- No check if `sessionId` is valid UUID format before queries
- No validation of user input before RPC calls
- No length checks on text fields before update

**Files:** SessionDetailView.vue, CreateSessionView.vue, HomePage.vue

**Impact:**
- Backend may reject with cryptic errors
- XSS vulnerabilities if validation happens only on backend
- Poor UX when invalid data causes failures

**Fix Approach:**
- Create validation utilities using Zod or Valibot
- Validate schema before each API call
- Show validation errors to user before attempting API call

---

## Language & Localization Issues

### localStorage Type Casting Without Null Check

**Issue:** `src/stores/lang.ts` line 7 casts `localStorage.getItem()` without null check:
```typescript
const currentLang = ref<Locale>((localStorage.getItem('lang') as Locale) || 'vi')
```

**Files:** `src/stores/lang.ts` line 7

**Impact:**
- If `localStorage.getItem('lang')` is `null`, casting to `Locale` is incorrect
- TypeScript won't catch this (forced cast)
- Runtime behavior depends on localStorage state

**Fix Approach:**
- Add explicit null check: `(localStorage.getItem('lang') ?? 'vi') as Locale`
- Validate that returned value is actually valid `Locale`

---

## Missing Features & Documentation

### No Offline Support

**Issue:** App requires internet connection; no offline mode:
- No service worker
- No local caching strategy
- No offline queue for mutations

**Impact:**
- Mobile users on unstable connections cannot use app
- Attendance data lost if connection drops during session

**Recommendations:** Consider adding offline-first architecture with sync when connection restored

---

### No Audit Logging

**Issue:** No audit trail of who changed what and when:
- User actions not logged server-side
- Cannot track data modifications
- Compliance/governance risk

**Impact:**
- Cannot investigate mistakes or fraud
- No accountability trail

**Recommendations:** Add audit logging table that tracks all mutations with user ID, timestamp, old/new values

---

## Scaling Concerns

### Attendance Matrix Rendering Performance

**Issue:** Attendance matrix renders all members × intervals in DOM:
- 100 members × 100 intervals = 10,000 cells
- Each cell is Vue component/reactive state
- Could cause slow renders on mobile devices

**Files:** `src/views/SessionDetailView.vue` (template section with table rendering)

**Impact:**
- Laggy UI on large sessions
- Mobile browsers may struggle
- Slow initial page load

**Recommendations:**
- Implement virtual scrolling for large lists
- Use fixed-size table window with scroll
- Lazy-render cells outside viewport

---

## Fragile Code Patterns

### Manual State Sync Between Realtime and Polling

**Issue:** Lines 542, 552, 562 all call `fetchData(true)` via different triggers:
- Realtime creates possibility of stale state if subscription disconnects silently
- Polling creates possibility of unnecessary fetches
- Manual sync (`line 413, 434: await fetchCosts()`) adds more places state can diverge

**Files:** `src/views/SessionDetailView.vue` lines 524-576

**Impact:**
- State can become inconsistent between realtime subscribers and offline polls
- Hard to debug sync issues
- May need to trace through 3 different update paths

**Safe Modification:**
- Audit all state updates to ensure they go through single update path
- Document which operations trigger state refresh
- Test offline scenario (disable network, verify polling catches up)

---

## Summary of Priority Issues

| Issue | Severity | Effort | Impact |
|-------|----------|--------|--------|
| No test coverage | High | High | Regression risk, can't verify fixes |
| Polling + Realtime redundancy | High | Low | Wasted resources, race conditions |
| Monolithic component (1290 lines) | High | High | Maintenance burden, hard to refactor |
| Unsafe `any` types | Medium | Medium | Type errors at runtime |
| Missing error boundaries | Medium | Medium | Single error crashes app |
| Supabase client init issue | Medium | Low | Fail silently on config errors |
| No RLS verification | Medium | Medium | Security misconfiguration risks |
| Console logs in prod | Low | Low | Data exposure, noise in logs |
| Missing input validation | Medium | Medium | UX issues, XSS risk |

---

*Concerns audit: 2025-01-15*
