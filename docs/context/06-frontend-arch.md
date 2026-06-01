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
| Vue Router         | v5.x                       | Routing + guards               |
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
├── App.vue                    # Root: AppHeader + RouterView + BottomNav
│
├── views/                     # Page-level components (1:1 với routes)
│   ├── HomePage.vue            # / — Bảng nợ tổng hợp (HomeDebtTable)
│   ├── DashboardView.vue       # /sessions — Danh sách sessions (admin)
│   ├── CreateSessionView.vue   # /create-session — Tạo buổi mới (admin)
│   ├── SessionDetailView.vue   # /session/:id — Chi tiết buổi, điểm danh, payment
│   ├── MemberView.vue          # /members — Danh sách thành viên
│   ├── MemberDetailView.vue    # /member/:id — Lịch sử nợ của 1 member
│   ├── PaymentView.vue         # /pay — Trang QR public (không cần login)
│   ├── LoginView.vue           # /login — Login form
│   └── ProfileView.vue         # /profile — Profile + bank config management
│
├── components/                # Shared/reusable components
│   ├── AppHeader.vue           # Navigation bar, auth state, lang switch
│   ├── BottomNav.vue           # Bottom tabs cho mobile
│   ├── HomeDebtTable.vue       # Bảng tổng hợp nợ tất cả member
│   ├── PaymentQRModal.vue      # Modal QR + polling (single & group)
│   ├── ManualPaymentModal.vue  # Modal confirm manual payment
│   ├── MemberUnpaidSessionsModal.vue  # Modal danh sách buổi chưa trả của member
│   └── SessionExtraCharges.vue  # Component quản lý phụ phí trong session
│
├── composables/
│   ├── usePaymentPolling.ts   # Polling logic cho QR status
│   └── useBankConfig.ts       # Bank config từ DB + fallback
│
├── stores/
│   ├── auth.ts                # user, profile, isAdmin — xem 03-auth-and-roles.md
│   └── lang.ts                # currentLang, t() function (custom i18n)
│
├── lib/
│   └── supabase.ts            # Singleton supabase client
│
├── types/
│   └── index.ts               # Tất cả TypeScript interfaces
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

**Hiện tại:** App dùng đồng thời `AppHeader` + `BottomNav`.

```
Bottom Nav tabs (current):
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
| `profile`        | `/profile`        | ❌        | ❌          | Public route; UI phân nhánh theo trạng thái đăng nhập                                         |
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

Ngoài ra project có custom auth lock + custom visibility handler để tránh lỗi pending API sau khi alt-tab.

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

### Sessions list (`/sessions`) pattern

- FE gọi RPC `search_sessions_list` để lấy data theo page (cursor-based)
- Search + date filter + status filter được sync vào URL query (`q`, `from`, `to`, `status`)
- Infinite scroll dùng `IntersectionObserver` + composite cursor (`status_rank`, `session_date`, `id`)
- Guest chỉ query status `waiting_for_payment` và `done`

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

**Bank config source:** `useBankConfig()` đọc từ `bank_config` (DB) và fallback cứng nếu cần.

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
