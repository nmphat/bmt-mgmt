# Coding Conventions

**Analysis Date:** 2025-01-15

## Naming Patterns

**Files:**
- Vue components (Views): `*View.vue` - PascalCase suffix pattern. Example: `LoginView.vue`, `SessionDetailView.vue`, `DashboardView.vue` in `src/views/`
- Vue components (Reusable): `*.vue` - PascalCase. Example: `AppHeader.vue`, `PaymentQRModal.vue` in `src/components/`
- TypeScript files: `*.ts` - camelCase. Example: `supabase.ts`, `formatters.ts`
- Utilities: `*-*.ts` or `*.ts` - camelCase. Example: `formatters.ts`, `time.ts`

**Functions and Methods:**
- Named functions: camelCase. Example: `fetchSessions()`, `handleLogin()`, `getShortName()`, `mergeTimeIntervals()`
- Arrow functions: camelCase with explicit parameter types. Example: `const fetchMyDebt = async () => { ... }`
- Async functions: Always async/await, never promise chains. Example: `async function handleLogin() { ... }`
- Pinia store functions: camelCase, exported inside store. Example: `initialize()`, `signOut()`, `fetchProfile()`

**Variables and Constants:**
- Reactive state: camelCase with ref(). Example: `const loading = ref(false)`, `const email = ref('')`
- Computed properties: camelCase. Example: `const isAuthenticated = computed(() => !!user.value)`
- Local variables: camelCase. Example: `const displayName = 'John'`, `const errorMsg = ref('')`
- Constants: SCREAMING_SNAKE_CASE. Example: `BANK_INFO`, `ACCOUNT_NO`, `TEMPLATE`
- Never use var - always const or let

**Types and Interfaces:**
- Interfaces: PascalCase. Example: `interface SessionSummary { ... }`, `interface MemberCost { ... }`
- Type unions: PascalCase. Example: `type Locale = 'vi' | 'en'`
- Generic type parameters: Single uppercase letter preferred. Example: `<T>`, `<K, V>`

**Pinia Stores:**
- Store functions: `use` + PascalCase. Example: `useAuthStore()`, `useLangStore()`, `useCounterStore()`
- All exported from `src/stores/` directory
- Use Composition API pattern inside defineStore

## Code Style

**Formatting:**
- Tool: Prettier 3.8.1 (configured in `.prettierrc.json`)
- Semicolons: **Disabled** (`"semi": false`)
- Quotes: **Single quotes** (`"singleQuote": true`)
- Print width: **100 characters** (`"printWidth": 100`)
- Apply formatting with: `pnpm format` (runs `prettier --write --experimental-cli src/`)

**Linting:**
- No ESLint or Biome configuration detected
- Type checking: `pnpm type-check` runs `vue-tsc --build`
- Follow TypeScript strict mode in `tsconfig.app.json`

## Import Organization

**Order:**
1. Vue/Framework imports first
2. Library imports (e.g., @supabase, date-fns, lucide-vue-next, vue-toastification)
3. Local imports using `@/` alias
4. Type imports using `type` keyword

**Example:**
```typescript
// ✓ Correct order
import { ref, computed, onMounted } from 'vue'
import { defineStore } from 'pinia'
import { useRouter } from 'vue-router'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import type { SessionSummary, MemberCost } from '@/types'
import PaymentQRModal from '@/components/PaymentQRModal.vue'
```

**Path Aliases:**
- `@/` resolves to `src/` - Use this consistently for all local imports
- Configuration in `vite.config.ts` and `tsconfig.app.json`

## Error Handling

**Supabase Pattern:**
- Always destructure `data` and `error` from Supabase responses
- Check and throw errors immediately
- Use try-catch-finally blocks

```typescript
// ✓ Correct pattern
async function fetchSessions() {
  try {
    loading.value = true
    const { data, error } = await supabase
      .from('view_session_summary')
      .select('*')
      .order('session_date', { ascending: false })

    if (error) throw error
    sessions.value = data || []
  } catch (error) {
    console.error('Error fetching sessions:', error)
  } finally {
    loading.value = false
  }
}
```

**API Error Handling:**
- Console.error() for server-side logging
- toast.error() for user-facing notifications using `vue-toastification`
- Always pass error message to toast: `toast.error(error.message || t.value('key'))`

**Type Casting:**
- Use `as` for known types. Example: `const userId = route.params.id as string`
- Use optional chaining `?.` and nullish coalescing `??` to handle nullable values

## Logging

**Framework:** console (no structured logging framework)

**Patterns:**
- `console.warn()` for non-critical issues
- `console.error()` for caught exceptions and error states
- Prefix messages with context. Example: `console.error('Error fetching member profile:', error)`
- Never log secrets or sensitive data

**Example:**
```typescript
if (error) {
  console.warn('Error fetching member profile:', error)
  return
}
```

## Comments

**When to Comment:**
- Document complex business logic (e.g., time interval merging)
- Explain non-obvious solutions
- Mark temporary workarounds with `// TODO:` or `// FIXME:`

**JSDoc/TSDoc:**
- Use for exported functions and utilities
- Include parameter descriptions and return type documentation

**Example:**
```typescript
/**
 * Merges consecutive time intervals into a readable string.
 * Example:
 * Input: [{start: '16:00', end: '16:30'}, {start: '16:30', end: '17:00'}]
 * Output: "16:00 - 17:00"
 */
export function mergeTimeIntervals(intervals: TimeInterval[]): string {
  // Implementation
}
```

## Function Design

**Size:** Keep functions under 50 lines where possible. Break complex logic into smaller functions.

**Parameters:**
- Use destructuring for object parameters
- Use `defineProps<{...}>()` in Vue components instead of props parameter
- Always annotate types explicitly

**Return Values:**
- Always specify return type: `async function getName(): Promise<string> { ... }`
- Use optional return types when appropriate: `function getValue(): string | null { ... }`
- Return early for error conditions

**Example:**
```typescript
async function handleLogin() {
  try {
    loading.value = true
    errorMsg.value = ''
    const { error } = await supabase.auth.signInWithPassword({
      email: email.value,
      password: password.value,
    })
    if (error) throw error
    router.push('/')
  } catch (error: any) {
    errorMsg.value = error.message || 'Login failed'
    toast.error(errorMsg.value)
  } finally {
    loading.value = false
  }
}
```

## Vue 3 Script Setup Patterns

**Component Structure:**
- Use `<script setup lang="ts">` for all Vue components
- Define props with `defineProps<{ ... }>()`
- Define emits with `defineEmits<{ ... }>()`
- Use Composition API functions (ref, computed, onMounted, watch)

**Reactive State:**
- Use `ref<Type>(initialValue)` for mutable state
- Use `computed(() => derivedValue)` for derived state
- Use `watch()` for side effects on state changes

**Lifecycle:**
- `onMounted()` for initialization
- `onUnmounted()` for cleanup
- `watch()` for reactive dependencies

**Example Component:**
```typescript
<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import type { SessionSummary } from '@/types'

const props = defineProps<{
  sessionId: string
}>()

const emit = defineEmits<{
  (e: 'update', id: string): void
}>()

const session = ref<SessionSummary | null>(null)
const loading = ref(false)

const displayTitle = computed(() => session.value?.title || 'Loading...')

async function fetchSession() {
  loading.value = true
  try {
    // Fetch logic
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  fetchSession()
})
</script>
```

## Module Design

**Exports:**
- Named exports for utilities and types: `export const functionName = ...` or `export interface Name { ... }`
- Default export for Vue components: `<template>` and `<script setup>` combination
- Re-export from index files when organizing multiple exports

**Barrel Files:**
- Use `src/types/index.ts` to export all type definitions
- Use centralized store exports from `src/stores/`
- Import directly from specific files, not barrel files when possible for better tree-shaking

**Example:**
```typescript
// src/types/index.ts
export interface SessionSummary { ... }
export interface MemberCost { ... }
export const BANK_INFO = { ... }

// Usage
import type { SessionSummary } from '@/types'
```

## i18n/Localization

**Pattern:**
- Centralized messages object in `src/locales/messages.ts`
- Nested object structure following dot-notation keys
- Support both Vietnamese (vi) and English (en)

**Usage:**
```typescript
const langStore = useLangStore()
const t = computed(() => langStore.t)

// In template or code
t('common.save')  // Access via dot notation
t('session.title')
t('auth.emailPlaceholder')

// With interpolation
t('session.selectedCount', { count: 5 })  // Replace {count} with 5
```

**Naming Convention for Keys:**
- Group by feature: `auth.*`, `common.*`, `session.*`, `nav.*`, `debt.*`
- Use snake_case for key names: `waiting_for_payment`, `sign_in_title`

## Directory Structure

**Locations by Type:**
- Components: `src/components/` - Reusable Vue components
- Views/Pages: `src/views/` - Page-level components (suffixed with `View`)
- Stores: `src/stores/` - Pinia state management stores
- Utilities: `src/utils/` - Helper functions (formatters, time, etc.)
- Types: `src/types/` - TypeScript interfaces and types
- Libraries: `src/lib/` - Integrated external libraries (Supabase client)
- Router: `src/router/` - Vue Router configuration
- Locales: `src/locales/` - i18n message files
- Assets: `src/assets/` - Static assets and global CSS

## Supabase Patterns

**Client Initialization:**
- Single centralized instance in `src/lib/supabase.ts`
- Export as named export: `export const supabase = createClient(...)`
- Import in components: `import { supabase } from '@/lib/supabase'`

**Query Patterns:**
```typescript
// RPC call (for business logic in Postgres)
const { data, error } = await supabase.rpc('function_name', { param1, param2 })

// Table select
const { data, error } = await supabase
  .from('table_name')
  .select('col1, col2')
  .eq('filter_col', value)
  .order('created_at', { ascending: false })

// Upsert (insert or update)
const { error } = await supabase
  .from('table_name')
  .upsert({ ...data }, { onConflict: 'id' })
```

**Realtime Subscriptions:**
- Subscribe to table changes with channel API
- Unsubscribe on component unmount
- Destructure payload for reactive updates

## Type Safety

**Strict Mode:**
- TypeScript strict mode enabled in `tsconfig.app.json`
- Always annotate function return types
- Use `as const` for literal type narrowing
- Avoid `any` type - use generics or union types instead
- Type cast with `as Type` only when necessary

**Example:**
```typescript
// ✓ Good
const sessionId: string = route.params.id
const sessions: SessionSummary[] = []
async function fetch(): Promise<SessionSummary> { ... }

// ✗ Avoid
const sessionId = route.params.id as any
```

---

*Convention analysis: 2025-01-15*
