# Auth & Roles

> **Dùng file này khi:** Implement tính năng liên quan đến login, phân quyền, route guard, RLS policy.

---

## Auth Provider

**Supabase Auth** — email/password (không có social login, không có self-signup).

- Admin tạo tài khoản member thủ công qua Supabase Dashboard hoặc admin UI
- Sau khi user tạo, admin link `auth.users.id` vào `members.user_id`

---

## Roles

| Role     | Postgres Enum | Quyền                                                     |
| -------- | ------------- | --------------------------------------------------------- |
| `admin`  | `user_role`   | Toàn quyền: tạo session, điểm danh, tính tiền, xem tất cả |
| `member` | `user_role`   | Chỉ xem thông tin bản thân (lịch sử nợ, chi tiết buổi)    |

**Role lấy từ đâu:** `members.role` (sau khi login, FE fetch profile từ bảng `members`)

---

## Auth Store (`src/stores/auth.ts`)

```typescript
// State
user: User | null        // Supabase auth user object
profile: MemberProfile | null  // { id, role, display_name } từ bảng members
loading: boolean

// Computed
isAuthenticated: computed(() => !!user.value)
isAdmin: computed(() => profile.value?.role === 'admin')
```

### Initialization flow

```
App mount → authStore.initialize()
  → supabase.auth.getSession()
  → nếu có session → fetchProfile(userId)
     → SELECT id, role, display_name FROM members WHERE user_id = $userId
  → set loading = false
  → subscribe onAuthStateChange (handle tab refresh / token expiry)
```

---

## Route Guards

**Defined in:** `src/router/index.ts`

| Route          | Path              | Auth         | Admin |
| -------------- | ----------------- | ------------ | ----- |
| Home           | `/`               | ❌ Public     | ❌     |
| Login          | `/login`          | ❌ Public     | ❌     |
| Dashboard      | `/sessions`       | ✅            | ✅     |
| Create Session | `/create-session` | ✅            | ✅     |
| Session Detail | `/session/:id`    | ❌ Public     | ❌     |
| Members List   | `/members`        | ❌ Public     | ❌     |
| Member Detail  | `/member/:id`     | ❌ Public     | ❌     |
| Profile        | `/profile`        | ❌ Public     | ❌     |
| **Payment**    | `/pay`            | ❌ **Public** | ❌     |

> `/pay` là trang **public không cần login** — member/khách quét QR và thanh toán mà không cần tài khoản.

### Guard logic

```typescript
router.beforeEach(async (to, from, next) => {
  if (authStore.loading) await authStore.initialize()  // Chờ init nếu đang refresh

  if (requiresAuth && !authStore.isAuthenticated) → redirect '/login'
  if (requiresAdmin && !authStore.isAdmin) → redirect '/'
  next()
})
```

---

## RLS Policies (Pattern chung)

Tất cả tables có RLS enabled. Pattern chung:

```sql
-- Admin: full access
CREATE POLICY "admin_all" ON <table>
  USING (
    EXISTS (SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin')
  );

-- Member: chỉ đọc data của chính mình
CREATE POLICY "member_read_own" ON session_costs_snapshot
  FOR SELECT
  USING (member_id = (SELECT id FROM members WHERE user_id = auth.uid()));
```

---

## Luồng đăng nhập

```
User truy cập /login
  → Nhập email + password
  → supabase.auth.signInWithPassword({ email, password })
  → Thành công → onAuthStateChange trigger → fetchProfile()
  → redirect về trang trước hoặc '/'
```

## Luồng đăng xuất

```
supabase.auth.signOut()
  → clear user + profile trong store
  → onAuthStateChange trigger với null session
```

---

## Edge Cases cần chú ý

1. **Member chưa được link** (`user_id` null): User có thể login nhưng `fetchProfile` trả về empty → `isAdmin = false`, không có profile. Cần xử lý gracefully ở UI.
2. **Page refresh**: `loading = true` khi init → route guard `await initialize()` để tránh flash redirect.
3. **Token expiry**: Supabase tự refresh token, `onAuthStateChange` handle automatically.
