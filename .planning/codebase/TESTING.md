# Testing Patterns

**Analysis Date:** 2025-01-15

## Test Framework Status

**Current State:** No testing framework is currently configured in this project.

- **Framework:** Not installed
- **Runner:** Not configured
- **Assertion Library:** Not configured
- **Run Commands:** Not available

## Project Context

This is an active Vue 3/Supabase SPA project with ~4500 lines of TypeScript/Vue code across:
- 8 Vue views (`src/views/`)
- 3 Vue components (`src/components/`)
- 3 Pinia stores (`src/stores/`)
- Multiple utility files (`src/utils/`)
- Centralized types (`src/types/`)

**Current Testing Gap:** Zero test coverage. No test files exist in the project (only in node_modules dependencies).

## Recommended Testing Setup

### Framework Recommendation

For this Vue 3 + TypeScript + Supabase stack, use **Vitest**:

```json
// In package.json devDependencies
"vitest": "^2.x",
"@vitest/ui": "^2.x",
"happy-dom": "^14.x",  // lightweight DOM for Vue components
"@vue/test-utils": "^2.4.x",
"@testing-library/vue": "^8.x",
"@testing-library/user-event": "^14.x"
```

### Build Configuration

Create `vitest.config.ts`:
```typescript
import { defineConfig } from 'vitest/config'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath } from 'node:url'

export default defineConfig({
  plugins: [vue()],
  test: {
    globals: true,
    environment: 'happy-dom',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      lines: 60,
      functions: 60,
      branches: 50,
      statements: 60,
    },
    include: ['src/**/*.{test,spec}.{ts,tsx}'],
  },
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
})
```

Add to `package.json` scripts:
```json
{
  "test": "vitest",
  "test:ui": "vitest --ui",
  "test:run": "vitest run",
  "test:coverage": "vitest run --coverage"
}
```

## Test File Organization

**Location:** Co-located with source files

**Pattern:** `<filename>.test.ts` or `<filename>.spec.ts`

**Structure:**
```
src/
├── components/
│   ├── AppHeader.vue
│   ├── AppHeader.test.ts
│   ├── PaymentQRModal.vue
│   └── PaymentQRModal.test.ts
├── stores/
│   ├── auth.ts
│   ├── auth.test.ts
│   ├── lang.ts
│   └── lang.test.ts
├── utils/
│   ├── formatters.ts
│   ├── formatters.test.ts
│   ├── time.ts
│   └── time.test.ts
└── views/
    ├── LoginView.vue
    └── LoginView.test.ts
```

## Test Structure

**Suite Organization:**

Use `describe()` for logical grouping. Each file typically has one top-level suite:

```typescript
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'

describe('AuthStore', () => {
  describe('initialize', () => {
    it('should fetch user session on init', () => {
      // test code
    })

    it('should load member profile if authenticated', () => {
      // test code
    })
  })

  describe('signOut', () => {
    it('should clear user and profile', () => {
      // test code
    })
  })
})
```

**Setup/Teardown:**

Use `beforeEach()` and `afterEach()` for test isolation:

```typescript
beforeEach(() => {
  vi.clearAllMocks()
  localStorage.clear()
})

afterEach(() => {
  vi.restoreAllMocks()
})
```

**Assertions:**

Use Vitest's built-in expect() - same API as Jest:

```typescript
expect(value).toBe(expected)
expect(array).toContain(item)
expect(spy).toHaveBeenCalledWith(arg)
expect(promise).resolves.toEqual(value)
expect(() => fn()).toThrow()
```

## Mocking

**Framework:** Vitest's built-in `vi` module

**Patterns:**

### 1. Mock Supabase Client

```typescript
import { vi } from 'vitest'

const mockSupabase = {
  from: vi.fn(() => ({
    select: vi.fn(() => ({
      eq: vi.fn().mockResolvedValue({
        data: [{ id: '1', title: 'Test' }],
        error: null,
      }),
    })),
  })),
  rpc: vi.fn().mockResolvedValue({ data: { ... }, error: null }),
  auth: {
    signInWithPassword: vi.fn().mockResolvedValue({ error: null }),
    signOut: vi.fn().mockResolvedValue({ error: null }),
    getSession: vi.fn().mockResolvedValue({ data: { session: null }, error: null }),
    onAuthStateChange: vi.fn(),
  },
}

vi.mock('@/lib/supabase', () => ({
  supabase: mockSupabase,
}))
```

### 2. Mock Pinia Store

```typescript
import { setActivePinia, createPinia } from 'pinia'

beforeEach(() => {
  setActivePinia(createPinia())
})
```

### 3. Mock Vue Router

```typescript
vi.mock('vue-router', () => ({
  useRouter: () => ({
    push: vi.fn(),
    back: vi.fn(),
  }),
  useRoute: () => ({
    params: { id: 'test-id' },
    query: {},
  }),
}))
```

### 4. Mock vue-toastification

```typescript
const mockToast = {
  error: vi.fn(),
  success: vi.fn(),
  info: vi.fn(),
}

vi.mock('vue-toastification', () => ({
  useToast: () => mockToast,
}))
```

### 5. Spy on Functions

```typescript
const consoleSpy = vi.spyOn(console, 'error')
// ... run code that calls console.error ...
expect(consoleSpy).toHaveBeenCalledWith('Error fetching:', expect.any(Error))
consoleSpy.mockRestore()
```

**What to Mock:**
- External API clients (Supabase)
- Router navigation (useRouter, useRoute)
- Toast notifications
- Timers (vi.useFakeTimers())
- Local storage

**What NOT to Mock:**
- Core logic of the component/function under test
- Pinia store logic (test actual behavior)
- date-fns utilities (real dates help catch edge cases)
- TypeScript types

## Fixtures and Factories

**Test Data:**

Create factory functions in `src/__tests__/fixtures/`:

```typescript
// src/__tests__/fixtures/factories.ts
import type { SessionSummary, MemberCost } from '@/types'

export function createSessionSummary(overrides?: Partial<SessionSummary>): SessionSummary {
  return {
    id: 'session-1',
    title: 'Tuesday Badminton',
    status: 'open',
    session_date: '2025-01-15T18:00:00Z',
    court_fee_total: 100000,
    shuttle_fee_total: 20000,
    total_intervals: 4,
    total_registrations: 8,
    ...overrides,
  }
}

export function createMemberCost(overrides?: Partial<MemberCost>): MemberCost {
  return {
    member_id: 'member-1',
    display_name: 'John Doe',
    total_court_fee: 25000,
    total_shuttle_fee: 5000,
    final_total: 30000,
    intervals_count: 2,
    ...overrides,
  }
}
```

**Usage in Tests:**

```typescript
import { describe, it, expect } from 'vitest'
import { createSessionSummary } from '@/__tests__/fixtures/factories'

describe('DashboardView', () => {
  it('should display session card with correct title', () => {
    const session = createSessionSummary({ title: 'Weekend Session' })
    // Use session in test
  })
})
```

**Location:** `src/__tests__/fixtures/` or `src/__tests__/mocks/`

## Coverage

**Requirements:** Not currently enforced

**Recommended Targets:**
- Utilities: 90%+ (pure functions)
- Stores: 80%+ (state management)
- Components: 60%+ (UI difficult to test fully)
- Views: 40%+ (depend heavily on route/auth)

**View Coverage:**

```bash
pnpm test:coverage
```

Output files:
- `coverage/index.html` - Browse coverage report
- `coverage/coverage-final.json` - CI/CD integration

## Test Types

### Unit Tests

**Scope:** Individual functions and store methods

**Example - Utility Function:**

```typescript
import { describe, it, expect } from 'vitest'
import { mergeTimeIntervals } from '@/utils/time'

describe('mergeTimeIntervals', () => {
  it('should merge consecutive intervals', () => {
    const intervals = [
      { start_time: '16:00', end_time: '16:30' },
      { start_time: '16:30', end_time: '17:00' },
    ]
    expect(mergeTimeIntervals(intervals)).toBe('16:00-17:00')
  })

  it('should return empty string for empty input', () => {
    expect(mergeTimeIntervals([])).toBe('')
  })
})
```

**Example - Pinia Store:**

```typescript
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { setActivePinia, createPinia } from 'pinia'
import { useAuthStore } from '@/stores/auth'

vi.mock('@/lib/supabase', () => ({
  supabase: {
    auth: {
      getSession: vi.fn().mockResolvedValue({ data: { session: null }, error: null }),
      onAuthStateChange: vi.fn(),
    },
    from: vi.fn(),
  },
}))

describe('AuthStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('should initialize with null user when no session', async () => {
    const store = useAuthStore()
    await store.initialize()
    expect(store.user).toBeNull()
  })
})
```

### Component Tests

**Scope:** Vue component rendering and interactions

**Example - Simple Component:**

```typescript
import { describe, it, expect, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import AppHeader from '@/components/AppHeader.vue'

vi.mock('@/stores/auth', () => ({
  useAuthStore: () => ({
    isAuthenticated: false,
    user: null,
  }),
}))

describe('AppHeader', () => {
  it('should show login button when not authenticated', () => {
    const wrapper = mount(AppHeader)
    expect(wrapper.text()).toContain('Login')
  })
})
```

### Integration Tests

**Scope:** Multiple components/stores working together

**Priority:** Lower - focus on unit tests and component tests first

**Example - Store + Component:**

```typescript
describe('Session Detail Integration', () => {
  it('should load and display session data', async () => {
    // Setup store
    // Setup mocks for Supabase
    // Mount component
    // Verify data displayed
  })
})
```

### E2E Tests (Future)

**Tool:** Not currently in place. Consider Playwright or Cypress for future phases.

**Scope:** Full user workflows (login → create session → update attendance)

## Common Patterns

### Async Testing

Use `async/await` syntax with `vi.waitFor()` for reactive updates:

```typescript
it('should load sessions on mount', async () => {
  const wrapper = mount(DashboardView)
  
  // Wait for async data load
  await vi.waitFor(() => {
    expect(wrapper.find('[data-testid="session-card"]').exists()).toBe(true)
  })
})

// Or with Pinia store
it('should fetch profile after login', async () => {
  const store = useAuthStore()
  await store.initialize()
  
  await vi.waitFor(() => {
    expect(store.profile).not.toBeNull()
  })
})
```

### Error Testing

```typescript
it('should show error toast on failed login', async () => {
  const mockToast = {
    error: vi.fn(),
  }
  
  vi.mock('vue-toastification', () => ({
    useToast: () => mockToast,
  }))

  // Test error handling
  await loginFunction()
  
  expect(mockToast.error).toHaveBeenCalled()
})
```

### Testing Computed Properties

```typescript
it('should compute display name from profile', () => {
  const store = useAuthStore()
  store.profile = { id: '1', display_name: 'John', role: 'admin' }
  
  expect(store.displayName).toBe('John')
})
```

### Testing Watchers

```typescript
it('should refetch data when route changes', async () => {
  const mockFetch = vi.fn()
  const wrapper = mount(MemberDetailView, {
    global: {
      mocks: {
        $route: { params: { id: 'member-1' } },
      },
    },
  })

  // Change route param (typically via router)
  await wrapper.vm.$nextTick()
  
  expect(mockFetch).toHaveBeenCalled()
})
```

## Test Naming Convention

**Pattern:** `should [expected behavior] [when condition]`

```typescript
// ✓ Good
it('should display error message when login fails', () => {})
it('should redirect to home when authenticated', () => {})
it('should disable submit button while loading', () => {})
it('should merge consecutive intervals with 30-min gaps', () => {})

// ✗ Avoid
it('test login', () => {})
it('login works', () => {})
it('should work', () => {})
```

## Critical Areas Needing Tests

Priority order for initial test coverage:

1. **Supabase Error Handling** (`src/stores/auth.ts`, `src/lib/supabase.ts`)
   - Network failures
   - Auth errors
   - Database constraint violations

2. **Cost Calculations** (RPC-driven in `SessionDetailView.vue`)
   - Verify cost breakdowns are displayed (don't calculate, trust RPC)
   - Verify rounding displays correctly

3. **Attendance Matrix Logic** (`SessionDetailView.vue`)
   - Toggle presence updates
   - Bulk toggle for member row
   - "Registered but absent" flag handling

4. **Payment State** (`SessionDetailView.vue`, `PaymentQRModal.vue`)
   - QR code generation with correct payment info
   - Payment completion polling
   - Group payment vs individual payment UI

5. **Auth Store** (`src/stores/auth.ts`)
   - Profile loading
   - Admin role detection
   - Sign out cleanup

## Running Tests

```bash
# Run all tests in watch mode
pnpm test

# Run tests once (CI mode)
pnpm test:run

# View coverage report
pnpm test:coverage

# Interactive UI dashboard
pnpm test:ui
```

## Best Practices

1. **Test behavior, not implementation** - Test what the function does, not how it does it
2. **One assertion per test** when possible - Easier to identify what failed
3. **Use descriptive test names** - Should read like documentation
4. **Mock external dependencies** - Supabase, Router, Toast
5. **Keep tests close to code** - Co-located test files aid navigation
6. **Isolate tests** - Use beforeEach/afterEach for cleanup
7. **Test error paths** - Not just happy path
8. **Avoid test interdependence** - Each test should stand alone
9. **Use factories for complex data** - DRY test fixtures
10. **Verify UI interactions** - Button clicks, input changes, etc.

---

*Testing analysis: 2025-01-15*
