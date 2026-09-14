# Phase P0 — Sửa 2 lỗ hổng phân quyền admin ở luồng session: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Guest (kể cả chưa đăng nhập) xem được session list và session detail, nhưng mọi nút/tính năng chỉ-admin phải bị vô hiệu hóa hoặc ẩn cho non-admin — đóng 2 chỗ code hiện đang gate nhầm theo `isAuthenticated` hoặc không lọc gì.

**Architecture:** Chỉ sửa 2 file Vue view hiện có (`DashboardView.vue`, `SessionDetailView.vue`), không đổi route, không đổi DB/RPC. Mỗi task viết test mount component thật (Vitest + `@vue/test-utils`) với `supabase` client và `useAuthStore` được mock/kiểm soát, chứng minh hành vi đúng theo vai trò trước khi sửa code.

**Tech Stack:** Vue 3 `<script setup>`, Pinia, Vitest, `@vue/test-utils`. Không thêm dependency.

**Spec:** [docs/superpowers/specs/2026-09-14-p0-session-permission-fixes-design.md](../specs/2026-09-14-p0-session-permission-fixes-design.md)

## Global Constraints

- Không thêm route guard (`meta.requiresAdmin`) ở `/sessions` — guest vẫn vào được, chỉ dữ liệu trả về bị lọc theo quyền.
- Không đổi dòng 191 và 735 của `SessionDetailView.vue` (`if (!authStore.isAuthenticated) return t.value('session.readOnlyHint')`) — đây là hint hiển thị, không phải gate hành động, giữ nguyên `isAuthenticated`.
- Mọi test dùng Vitest + `@vue/test-utils`, mock `@/lib/supabase` theo pattern chainable-thenable đã có trong `src/components/session/__tests__/ShuttleUsageEditor.test.ts` — không cài thêm thư viện mock mới.
- Chạy `npx vue-tsc --noEmit -p tsconfig.app.json` (exit code 0) sau mỗi task, trước khi commit.

---

## File Structure

| File | Trách nhiệm |
| --- | --- |
| `src/views/DashboardView.vue` | Sửa `fetchSessions()` để lọc `status` theo `authStore.isAdmin` |
| `src/views/__tests__/DashboardView.test.ts` | Test mới, xác nhận filter đúng theo vai trò |
| `src/views/SessionDetailView.vue` | Đổi 5 chỗ `authStore.isAuthenticated` → `authStore.isAdmin` trong khu vực bảng thanh toán |
| `src/views/__tests__/SessionDetailView.test.ts` | Test mới, xác nhận admin/non-admin/guest thấy đúng nội dung |

---

## Task 1: Lọc session list theo quyền trong `DashboardView.vue`

**Files:**
- Modify: `src/views/DashboardView.vue:23-41` (hàm `fetchSessions`)
- Test: `src/views/__tests__/DashboardView.test.ts` (tạo mới)

**Interfaces:**
- Consumes: `useAuthStore().isAdmin` (computed boolean, đã có sẵn trong `src/stores/auth.ts`)
- Produces: không có API mới — hành vi nội bộ của `fetchSessions()`

- [ ] **Step 1: Viết test (fail trước khi sửa)**

Tạo `src/views/__tests__/DashboardView.test.ts`:

```ts
import { describe, it, expect, vi } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import DashboardView from '@/views/DashboardView.vue'
import { useAuthStore } from '@/stores/auth'

function makeQueryBuilder() {
  const builder: any = {
    select: vi.fn(() => builder),
    order: vi.fn(() => builder),
    in: vi.fn(() => builder),
    then: (resolve: any, reject: any) =>
      Promise.resolve({ data: [], error: null }).then(resolve, reject),
  }
  return builder
}

let lastBuilder: any

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn(() => {
      lastBuilder = makeQueryBuilder()
      return lastBuilder
    }),
  },
}))

async function mountDashboard(isAdmin: boolean) {
  setActivePinia(createPinia())
  const authStore = useAuthStore()
  authStore.profile = isAdmin
    ? { id: 'a1', role: 'admin', display_name: 'Admin' }
    : { id: 'm1', role: 'member', display_name: 'Member' }
  const w = mount(DashboardView)
  await flushPromises()
  await flushPromises()
  return w
}

describe('DashboardView session list permission filter', () => {
  it('filters to finalized statuses for non-admin, applies no status filter for admin', async () => {
    await mountDashboard(false)
    expect(lastBuilder.in).toHaveBeenCalledWith('status', ['waiting_for_payment', 'done'])

    await mountDashboard(true)
    expect(lastBuilder.in).not.toHaveBeenCalled()
  })
})
```

- [ ] **Step 2: Chạy test, xác nhận FAIL**

Run: `npx vitest run src/views/__tests__/DashboardView.test.ts`
Expected: FAIL — `lastBuilder.in` chưa từng được gọi cho non-admin (assertion đầu tiên thất bại), vì `fetchSessions()` hiện chưa lọc gì.

- [ ] **Step 3: Sửa `fetchSessions()`**

Trong `src/views/DashboardView.vue`, thay:

```js
async function fetchSessions() {
  try {
    loading.value = true
    errorMessage.value = ''
    const { data, error } = await supabase
      .from('view_session_summary')
      .select('*')
      .order('session_date', { ascending: false })

    if (error) throw error
    sessions.value = data || []
  } catch (error) {
```

bằng:

```js
async function fetchSessions() {
  try {
    loading.value = true
    errorMessage.value = ''
    let query = supabase
      .from('view_session_summary')
      .select('*')
      .order('session_date', { ascending: false })

    if (!authStore.isAdmin) {
      query = query.in('status', ['waiting_for_payment', 'done'])
    }

    const { data, error } = await query

    if (error) throw error
    sessions.value = data || []
  } catch (error) {
```

- [ ] **Step 4: Chạy test, xác nhận PASS**

Run: `npx vitest run src/views/__tests__/DashboardView.test.ts`
Expected: PASS

- [ ] **Step 5: Type-check**

Run: `npx vue-tsc --noEmit -p tsconfig.app.json`
Expected: exit code 0

- [ ] **Step 6: Commit**

```bash
git add src/views/DashboardView.vue src/views/__tests__/DashboardView.test.ts
git commit -m "fix(ui): filter session list to finalized-only for non-admin viewers"
```

---

## Task 2: Sửa gate `isAuthenticated` → `isAdmin` trong bảng thanh toán của `SessionDetailView.vue`

**Files:**
- Modify: `src/views/SessionDetailView.vue:1665, 1703, 1813, 1866, 1952`
- Test: `src/views/__tests__/SessionDetailView.test.ts` (tạo mới)

**Interfaces:**
- Consumes: `useAuthStore().isAdmin`, `useAuthStore().isAuthenticated`, `useAuthStore().user`, `useAuthStore().profile` (đã có sẵn)
- Produces: không có API mới

- [ ] **Step 1: Viết test (fail trước khi sửa)**

Tạo `src/views/__tests__/SessionDetailView.test.ts`:

```ts
import { describe, it, expect, vi } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import SessionDetailView from '@/views/SessionDetailView.vue'
import SessionExtraCharges from '@/components/SessionExtraCharges.vue'
import { useAuthStore } from '@/stores/auth'

const TABLE_FIXTURES: Record<string, any> = {
  view_session_summary: {
    id: 'session-1',
    title: 'Buổi test',
    status: 'waiting_for_payment',
    session_date: '2026-09-14T11:00:00Z',
  },
  sessions: { shuttle_usage: [] },
  session_costs_snapshot: [
    {
      id: 'snap-1',
      session_id: 'session-1',
      member_id: 'm1',
      final_amount: 120000,
      paid_amount: 0,
      payment_code: 'CL000001',
      status: 'pending',
      court_fee_amount: 80000,
      shuttle_fee_amount: 40000,
      extra_fee_amount: 0,
      member: { display_name: 'Nguyễn Văn A' },
    },
  ],
}

function makeQueryBuilder(table: string) {
  const result = table in TABLE_FIXTURES ? TABLE_FIXTURES[table] : []
  const builder: any = {
    select: vi.fn(() => builder),
    eq: vi.fn(() => builder),
    order: vi.fn(() => builder),
    in: vi.fn(() => builder),
    single: vi.fn(() => builder),
    then: (resolve: any, reject: any) =>
      Promise.resolve({ data: result, error: null }).then(resolve, reject),
  }
  return builder
}

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn((table: string) => makeQueryBuilder(table)),
    rpc: vi.fn().mockResolvedValue({ data: [], error: null }),
    removeChannel: vi.fn(),
  },
}))

vi.mock('vue-router', async (importOriginal) => {
  const actual = await importOriginal<typeof import('vue-router')>()
  return {
    ...actual,
    useRoute: () => ({ params: { id: 'session-1' }, query: {}, name: 'session-detail' }),
    useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
  }
})

const STUBS = {
  PaymentQRModal: true,
  ManualPaymentModal: true,
  SessionExtraCharges: true,
  CourtBookingEditor: true,
  ShuttleUsageEditor: true,
}

async function mountDetail(role: 'admin' | 'member' | 'guest') {
  setActivePinia(createPinia())
  const authStore = useAuthStore()
  if (role !== 'guest') {
    authStore.user = { id: 'u1' } as any
    authStore.profile = {
      id: 'u1',
      role: role === 'admin' ? 'admin' : 'member',
      display_name: 'Test User',
    }
  }
  const w = mount(SessionDetailView, { global: { stubs: STUBS } })
  await flushPromises()
  await flushPromises()
  return w
}

describe('SessionDetailView payment table admin gating', () => {
  it('hides admin selection controls and shows 8 header columns for a non-admin authenticated viewer', async () => {
    const w = await mountDetail('member')
    expect(w.findAll('input[type="checkbox"][value="snap-1"]')).toHaveLength(0)
    expect(w.findAll('thead th')).toHaveLength(8)
    expect(w.find('tbody tr:last-child td:first-child').attributes('colspan')).toBe('5')
    expect(w.findComponent(SessionExtraCharges).props('isAdmin')).toBe(false)
  })

  it('shows admin selection controls and 9 header columns for an admin', async () => {
    const w = await mountDetail('admin')
    expect(w.findAll('input[type="checkbox"][value="snap-1"]')).toHaveLength(2)
    expect(w.findAll('thead th')).toHaveLength(9)
    expect(w.find('tbody tr:last-child td:first-child').attributes('colspan')).toBe('6')
    expect(w.findComponent(SessionExtraCharges).props('isAdmin')).toBe(true)
  })

  it('lets a fully anonymous guest still see the payment amounts read-only', async () => {
    const w = await mountDetail('guest')
    expect(w.findAll('input[type="checkbox"][value="snap-1"]')).toHaveLength(0)
    expect(w.text()).toContain('Nguyễn Văn A')
    expect(w.text()).toContain('120.000')
  })
})
```

- [ ] **Step 2: Chạy test, xác nhận FAIL**

Run: `npx vitest run src/views/__tests__/SessionDetailView.test.ts`
Expected: FAIL — test đầu tiên (`member` role) thất bại vì code hiện tại dùng `isAuthenticated` (đang `true` cho `member` đã đăng nhập), nên checkbox/cột/colspan/isAdmin hiện đang theo trạng thái "admin" thay vì bị ẩn.

- [ ] **Step 3: Sửa 5 vị trí trong `SessionDetailView.vue`**

Dòng 1665, trong `<SessionExtraCharges>`:

```
        :isAdmin="authStore.isAuthenticated"
```

→

```
        :isAdmin="authStore.isAdmin"
```

Dòng 1703, checkbox mobile:

```
                      v-if="snapshot.status !== 'paid' && authStore.isAuthenticated"
```

→

```
                      v-if="snapshot.status !== 'paid' && authStore.isAdmin"
```

Dòng 1813, header desktop:

```
                <th v-if="authStore.isAuthenticated" scope="col" class="px-3 py-3 w-10"></th>
```

→

```
                <th v-if="authStore.isAdmin" scope="col" class="px-3 py-3 w-10"></th>
```

Dòng 1866, ô desktop:

```
                <td v-if="authStore.isAuthenticated" class="px-3 py-4 text-center">
```

→

```
                <td v-if="authStore.isAdmin" class="px-3 py-4 text-center">
```

Dòng 1952, colspan:

```
                  :colspan="authStore.isAuthenticated ? 6 : 5"
```

→

```
                  :colspan="authStore.isAdmin ? 6 : 5"
```

- [ ] **Step 4: Chạy test, xác nhận PASS**

Run: `npx vitest run src/views/__tests__/SessionDetailView.test.ts`
Expected: PASS (3/3)

- [ ] **Step 5: Chạy toàn bộ suite + type-check**

Run: `npx vitest run && npx vue-tsc --noEmit -p tsconfig.app.json`
Expected: mọi test pass, exit code 0

- [ ] **Step 6: Commit**

```bash
git add src/views/SessionDetailView.vue src/views/__tests__/SessionDetailView.test.ts
git commit -m "fix(ui): gate payment table admin actions on isAdmin, not isAuthenticated"
```

---

## Self-Review

- **Spec coverage:** Yêu cầu 1 (spec) → Task 2. Yêu cầu 2 (spec) → Task 1. Cả 2 acceptance criteria trong spec đều có test tương ứng (non-admin/admin/guest cho Task 2; admin/non-admin filter cho Task 1).
- **Placeholder scan:** không có TODO/"add appropriate"/"similar to Task N" — mọi step có code đầy đủ.
- **Type consistency:** `authStore.isAdmin`, `authStore.isAuthenticated`, `authStore.profile`, `authStore.user` dùng đúng tên đã định nghĩa trong `src/stores/auth.ts`. `SessionExtraCharges` prop `isAdmin` khớp tên prop thật trong component đó.
