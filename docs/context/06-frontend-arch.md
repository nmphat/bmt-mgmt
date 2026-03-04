# Frontend Architecture

> **Dùng file này khi:** Thêm component mới, sửa store, thêm route, hoặc cần hiểu cách FE tổ chức theo pattern nào.

---

## Tech Stack

| Tool               | Version                    | Mục đích                       |
| ------------------ | -------------------------- | ------------------------------ |
| Vue 3              | Composition API            | UI framework                   |
| TypeScript         | strict                     | Type safety                    |
| Vite               |                            | Build tool, dev server         |
| Pinia              |                            | State management               |
| Vue Router 4       |                            | Routing + guards               |
| Tailwind CSS       | v4 (via @tailwindcss/vite) | Styling                        |
| Supabase JS        |                            | DB client, auth, realtime      |
| date-fns           |                            | Date formatting (vi/en locale) |
| lucide-vue-next    |                            | Icons                          |
| vue-toastification |                            | Toast notifications            |

**Path alias:** `@` → `src/`

---

## Project Structure

```
src/
├── main.ts                    # App entry, init Pinia + Router + app mount
├── App.vue                    # Root: AppHeader + RouterView
│
├── views/                     # Page-level components (1:1 với routes)
│   ├── HomePage.vue            # / — Bảng nợ tổng hợp (HomeDebtTable)
│   ├── DashboardView.vue       # /sessions — Danh sách sessions (admin)
│   ├── CreateSessionView.vue   # /create-session — Tạo buổi mới (admin)
│   ├── SessionDetailView.vue   # /session/:id — Chi tiết buổi, điểm danh, payment
│   ├── MemberView.vue          # /members — Danh sách thành viên
│   ├── MemberDetailView.vue    # /member/:id — Lịch sử nợ của 1 member
│   ├── PaymentView.vue         # /pay — Trang QR public (không cần login)
│   └── LoginView.vue           # /login — Login form
│
├── components/                # Shared/reusable components
│   ├── AppHeader.vue           # Navigation bar, auth state, lang switch
│   ├── HomeDebtTable.vue       # Bảng tổng hợp nợ tất cả member
│   ├── PaymentQRModal.vue      # Modal QR + polling (single & group)
│   ├── ManualPaymentModal.vue  # Modal confirm manual payment
│   ├── MemberUnpaidSessionsModal.vue  # Modal danh sách buổi chưa trả của member
│   └── SessionExtraCharges.vue  # Component quản lý phụ phí trong session
│
├── composables/
│   └── usePaymentPolling.ts   # Polling logic cho QR status
│
├── stores/
│   ├── auth.ts                # user, profile, isAdmin — xem 03-auth-and-roles.md
│   ├── lang.ts                # currentLang, t() function (custom i18n)
│   └── counter.ts             # Boilerplate (chưa dùng, có thể xóa)
│
├── lib/
│   └── supabase.ts            # Singleton supabase client
│
├── types/
│   └── index.ts               # Tất cả TypeScript interfaces + BANK_INFO constant
│
├── utils/
│   ├── formatters.ts          # formatCurrency(), getShortName()
│   └── time.ts                # Time helpers
│
├── locales/
│   └── messages.ts            # i18n strings (vi + en)
│
└── router/
    └── index.ts               # Routes + beforeEach guard
```

---

## Pinia Stores

### `useAuthStore` (`stores/auth.ts`)

```typescript
// State
user: User | null
profile: { id, role, display_name } | null
loading: boolean

// Getters
isAuthenticated: boolean
isAdmin: boolean

// Actions
initialize()    // Gọi 1 lần ở App.vue
signOut()
```

### `useLangStore` (`stores/lang.ts`)

```typescript
// State
currentLang: 'vi' | 'en'  // Persist vào localStorage

// Getters
t: (path: string, args?) => string  // Custom i18n function, NOT vue-i18n
  // Usage: t('common.save') hoặc t('payment.amount', { amount: 150000 })

// Actions
setLang(lang: 'vi' | 'en')
```

> **Lưu ý:** App KHÔNG dùng vue-i18n library. Có file `locales/messages.ts` với nested object và hàm `t()` tự viết trong `lang` store.

---

## Navigation Structure

**Target:** Bottom nav bar (mobile-first). **Hiện tại** đang dùng top nav — cần refactor.

```
Bottom Nav tabs (target):
  🏠 Home (/),  📅 Sessions (/sessions — admin only),  👥 Members (/members)
  👤 Login / Profile (top-right corner, không nằm trong bottom nav)
```

---

## Routing & Access Control

| Route Name       | Path              | Auth req | Admin only | Ai xem được gì                                                                               |
| ---------------- | ----------------- | -------- | ---------- | -------------------------------------------------------------------------------------------- |
| `home`           | `/`               | ❌        | ❌          | Tất cả - nhưng nội dung khác nhau (admin thấy full, member thấy giới hạn)                    |
| `dashboard`      | `/sessions`       | ✅        | ✅          | Admin only — toàn bộ sessions                                                                |
| `create-session` | `/create-session` | ✅        | ✅          | Admin only                                                                                   |
| `session-detail` | `/session/:id`    | ❌        | ❌          | **Admin:** tất cả status. **Member/non-login:** chỉ sessions đã finalized (status != 'open') |
| `members`        | `/members`        | ❌        | ❌          | Tất cả — admin thấy thêm action buttons                                                      |
| `member-detail`  | `/member/:id`     | ❌        | ❌          | Tất cả — member tự xem của mình                                                              |
| `payment`        | `/pay`            | ❌        | ❌          | **Public** — bất kỳ ai có link                                                               |
| `login`          | `/login`          | ❌        | ❌          | Tất cả                                                                                       |

> **Content-based access** (không phải route-based): Một số trang accessible với tất cả, nhưng nội dung hiển thị khác nhau tùy `isAdmin` và `isAuthenticated`.

---

## Supabase Client

**Singleton** tại `src/lib/supabase.ts`:

```typescript
export const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY
)
```

**Sử dụng trực tiếp trong views/components** (không qua store riêng cho data).  
Pattern: mỗi view tự fetch data cần thiết, không có global data store.

---

## Data Fetching Pattern

App dùng pattern **local fetch trong mỗi view**, không có global data cache:

```typescript
// Pattern phổ biến trong views
const data = ref<SomeType[]>([])
const loading = ref(true)

onMounted(async () => {
  const { data: result, error } = await supabase
    .from('table_name')
    .select('...')
  if (!error) data.value = result
  loading.value = false
})
```

**Realtime** (dùng ở `SessionDetailView`):

```typescript
const channel = supabase
  .channel('unique-channel-name')
  .on('postgres_changes', { event: '*', schema: 'public', table: 'interval_presence' }, handler)
  .subscribe()

onUnmounted(() => supabase.removeChannel(channel))
```

---

## i18n Pattern (Custom)

```typescript
// Trong component:
const langStore = useLangStore()
const t = computed(() => langStore.t)

// Usage:
t.value('common.save')                           // → 'Lưu'
t.value('payment.amount', { amount: 150000 })    // → 'Số tiền: 150,000đ'
```

Keys được định nghĩa trong `src/locales/messages.ts`.  
Nested structure: `domain.key` (VD: `auth.login`, `session.finalize`).

---

## TypeScript Types (`src/types/index.ts`)

Các interface chính:

| Interface             | Mapping với DB                         |
| --------------------- | -------------------------------------- |
| `SessionSummary`      | `view_session_summary`                 |
| `MemberCost`          | Output của `calculate_session_costs()` |
| `MemberDebtSummary`   | `view_member_debt_summary`             |
| `MemberSessionDetail` | `view_member_session_details`          |
| `Interval`            | `session_intervals`                    |
| `Member`              | `members`                              |
| `CostSnapshot`        | `session_costs_snapshot`               |
| `SessionRegistration` | `session_registrations`                |
| `IntervalPresence`    | `interval_presence`                    |
| `ExtraCharge`         | `session_extra_charges`                |
| `SessionPayment`      | `session_payments`                     |
| `GroupPaymentData`    | Output của `create_group_payment()`    |
| `CourtBooking`        | `session_court_bookings`               |

**Constant:**

```typescript
export const BANK_INFO = { BANK_ID: 'TPB', ACCOUNT_NO: '10003392871', TEMPLATE: 'compact2' }
```

> ⚠️ Đang bị duplicate trong `PaymentView.vue` và `PaymentQRModal.vue`. Nên refactor về 1 nguồn.

---

## Utility Functions

### `formatters.ts`

```typescript
formatCurrency(amount: number): string
// → "150.000 ₫" (định dạng vi-VN)

getShortName(name: string): string
// "Nguyễn Văn An Bình" → "Nguyễn Văn An"  (3 parts max)
```

---

## Component Conventions

- **Props:** Typed với TypeScript `defineProps<{...}>()`
- **Emits:** Typed với `defineEmits<{...}>()`
- **Composition API** (`setup()` style) — không dùng Options API
- **Icons:** `lucide-vue-next` — import từng icon cần dùng
- **Toast:** `useToast()` từ `vue-toastification`

---

## Deployment

- **Platform:** Vercel
- **Config:** `vercel.json` — rewrites tất cả routes về `index.html` (SPA fallback)
- **Public redirects:** `public/_redirects` — Netlify format fallback
- **Env vars cần set trên Vercel:** `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`

---

## Xem thêm

- **UI/UX design intent từng trang:** [07-ui-ux-design.md](./07-ui-ux-design.md)
- **Bug tracker & roadmap:** [08-bugs-and-roadmap.md](./08-bugs-and-roadmap.md)
