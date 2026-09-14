# Phase 1–4 — Giá theo sân, tiền cầu theo ống, dọn UX tạo buổi: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cho phép mỗi sân có giá riêng theo từng khung giờ, nhập tiền cầu theo ống và số quả từ một danh mục dùng lại được, trả lại khả năng sửa giờ buổi và giờ sân sau khi tạo, và xóa 1.623 dòng component chết — mà không làm đổi một đồng nào trong 53 buổi đã có.

**Architecture:** Giá sân chuyển xuống từng dòng `session_court_bookings`; `refresh_interval_courts` quy đổi thành `session_intervals.court_cost` (tiền, không phải số sân); `calculate_session_costs` đổi đúng một biểu thức và giữ nhánh cũ làm dự phòng cho buổi cũ. Tiền cầu giữ nguyên đường tính: một danh mục `shuttle_types` và một cột `sessions.shuttle_usage` kiểu jsonb chỉ để dựng ra `shuttle_fee_total`, engine không đổi. Phía giao diện, một component `CourtBookingEditor` dùng chung cho cả form tạo lẫn trang chi tiết, thay cho hai bản sao hiện tại.

**Tech Stack:** PostgreSQL 17, Vue 3 Composition API, TypeScript, Pinia, Tailwind v4, Vitest (thêm mới ở Task 8), Docker Postgres cho test SQL.

**Spec:** [docs/superpowers/specs/2026-09-09-pricing-model-and-create-session-ux-design.md](../specs/2026-09-09-pricing-model-and-create-session-ux-design.md) — mục 4, 5, 6, 7.

**Phụ thuộc:** [Plan Phase 0](./2026-09-09-security-and-money-bugs.md) phải hoàn tất trước. Plan này dùng lại `db-tests/` mà Plan Phase 0 dựng lên, và giả định các RPC ghi tiền đã là `SECURITY DEFINER`.

## Global Constraints

- **Nguồn sự thật của DB là `docs/sql-export/*.sql`.** Mọi thay đổi DB phải sửa file export tương ứng trong cùng commit.
- **Đừng tin file export cho tới khi đã đối chiếu.** Chạy `db-tests/drift-check.sh` (Task 0 của Plan Phase 0) trước khi bắt đầu và bất cứ khi nào quay lại plan này. File export được cập nhật bằng tay nên trôi khỏi production, kể cả do agent áp thay đổi qua MCP rồi quên ghi lại.
- **Tuyệt đối không chạy lệnh ghi lên production** (`bufpmpehugzysvmbjlub`). Thay đổi được giao dưới dạng file SQL để người dùng tự chạy.
- Mọi RPC tạo mới: `SECURITY DEFINER`, `SET search_path = public, pg_temp`, kiểm tra quyền admin ở đầu thân hàm, `REVOKE EXECUTE ... FROM anon`.
- Giao diện theo design system v1.0: mọi target chạm có `min-h-11`, bo góc `rounded-xl` hoặc `rounded-2xl`, chữ đậm dùng `font-bold`, tiêu đề mục dùng `text-[20px] font-bold leading-[1.2]`. **Không** dùng `rounded-lg` hay `font-semibold` — đó là hệ cũ.
- Mobile trước: bố cục xếp dọc dưới `sm`, hàng ngang chỉ từ `sm` trở lên.
- Mọi chuỗi hiển thị phải đi qua `t()` và có cả hai khóa `vi` và `en` trong `src/locales/messages.ts`. Chạy `pnpm i18n:audit` trước khi commit phần giao diện.
- Tiền VND là số nguyên đồng. Phép `CEIL(... / 1000) * 1000` cuối `calculate_session_costs` giữ nguyên.
- `pnpm install` trước khi bắt đầu — `node_modules` chưa được cài, `pnpm type-check` hiện fail ngay ở bước chạy `vue-tsc`.

---

## File Structure

### Cơ sở dữ liệu

| File | Thay đổi |
| --- | --- |
| `docs/sql-export/02_tables.sql` | Thêm `session_court_bookings.price_per_hour`, `session_intervals.court_cost`, `sessions.shuttle_usage`; thêm bảng `shuttle_types` |
| `docs/sql-export/04_indexes.sql` | Thêm index cho `session_court_bookings.session_id` |
| `docs/sql-export/06_functions.sql` | Sửa `refresh_interval_courts`, `calculate_session_costs`, `create_session_with_bookings` (bản 8 tham số); xóa bản 7 tham số; thêm `set_session_court_bookings`, `set_session_shuttle_usage` |
| `docs/sql-export/08_rls.sql` | Policy cho `shuttle_types` |
| `docs/sql-export/09_grants.sql` | Grant cho hai RPC mới |
| `docs/migrations/2026-09-09-phase1-pricing.sql` | Script người dùng chạy trên production |

### Giao diện

| File | Trách nhiệm |
| --- | --- |
| `src/components/session/CourtBookingEditor.vue` | **Mới.** Soạn danh sách sân, nhóm theo tên sân, mỗi khung giờ có giá riêng. Dùng ở cả form tạo và trang chi tiết |
| `src/components/session/ShuttleUsageEditor.vue` | **Mới.** Chọn loại cầu từ danh mục, nhập số quả bằng stepper, hiện tổng tiền |
| `src/composables/useShuttleTypes.ts` | **Mới.** Đọc và quản lý danh mục `shuttle_types` |
| `src/views/CreateSessionView.vue` | Bỏ hardcode sân 1, nhúng `CourtBookingEditor`, bỏ ô tiền cầu, thêm xem trước số interval |
| `src/views/SessionDetailView.vue` | Thêm sửa giờ buổi, nhúng `CourtBookingEditor` và `ShuttleUsageEditor` |
| `src/views/SettingsView.vue` | Thêm mục quản lý danh mục loại cầu |
| `src/types/index.ts` | `CourtBooking.price_per_hour`, `Interval.court_cost`, `ShuttleType`, `ShuttleUsageEntry` |
| `src/locales/messages.ts` | Khóa mới cho cả hai ngôn ngữ |
| **Xóa** | `src/components/session/SessionHeader.vue`, `SessionAttendanceGrid.vue`, `SessionCostSummary.vue`, `SessionPaymentTable.vue`, `SessionGroupPaymentBar.vue`, `src/components/MemberUnpaidSessionsModal.vue` |

---

## Task 1: Cột giá sân và cột tiền sân theo interval

**Files:**
- Create: `db-tests/10_court_cost.test.sql`
- Modify: `docs/sql-export/02_tables.sql`
- Modify: `docs/sql-export/04_indexes.sql`
- Modify: `docs/sql-export/06_functions.sql` (`refresh_interval_courts`)

**Interfaces:**
- Consumes: bàn test và `assert_eq` từ Plan Phase 0 Task 1
- Produces:
  - `session_court_bookings.price_per_hour numeric NOT NULL DEFAULT 0`
  - `session_intervals.court_cost numeric NOT NULL DEFAULT 0`
  - `refresh_interval_courts(p_session_id uuid)` — chữ ký không đổi, nay cập nhật cả `active_court_count` lẫn `court_cost`

- [ ] **Step 1: Viết test đỏ**

Tạo `db-tests/10_court_cost.test.sql`. Fixture của Plan Phase 0 là buổi 11:00–12:00 với hai interval 30 phút; test này thêm court booking có giá vào đúng buổi đó.

```sql
BEGIN;

-- Sân 1 chia hai khung giá, sân 2 một khung phủ cả buổi.
INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time, price_per_hour) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 1',
   '2026-09-01 11:00:00+00', '2026-09-01 11:30:00+00', 120000),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 1',
   '2026-09-01 11:30:00+00', '2026-09-01 12:00:00+00', 130000),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 2',
   '2026-09-01 11:00:00+00', '2026-09-01 12:00:00+00', 135000);

SELECT refresh_interval_courts('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- Interval 0 (11:00-11:30): Sân 1 @120k + Sân 2 @135k, mỗi sân nửa giờ
--   = 120000*0.5 + 135000*0.5 = 60000 + 67500 = 127500
SELECT assert_eq(
  (SELECT court_cost FROM session_intervals WHERE idx = 0
    AND session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  127500::numeric, 'interval 0 court_cost');

-- Interval 1 (11:30-12:00): Sân 1 @130k + Sân 2 @135k
--   = 130000*0.5 + 135000*0.5 = 65000 + 67500 = 132500
SELECT assert_eq(
  (SELECT court_cost FROM session_intervals WHERE idx = 1
    AND session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  132500::numeric, 'interval 1 court_cost');

-- active_court_count phải giữ nguyên hành vi cũ: đếm booking phủ interval.
SELECT assert_eq(
  (SELECT active_court_count FROM session_intervals WHERE idx = 0
    AND session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  2, 'interval 0 still counts two courts');

-- Booking không có giá (buổi cũ) phải cho court_cost = 0, không phải NULL.
DELETE FROM session_court_bookings
WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 1',
   '2026-09-01 11:00:00+00', '2026-09-01 12:00:00+00');

SELECT refresh_interval_courts('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

SELECT assert_eq(
  (SELECT court_cost FROM session_intervals WHERE idx = 0
    AND session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::numeric, 'legacy booking leaves court_cost at zero');

ROLLBACK;
```

- [ ] **Step 2: Chạy test, xác nhận đỏ**

```bash
./db-tests/run.sh
```

Kỳ vọng: `FAIL db-tests/10_court_cost.test.sql` với lỗi `column "price_per_hour" of relation "session_court_bookings" does not exist`.

- [ ] **Step 3: Thêm hai cột**

Trong `docs/sql-export/02_tables.sql`, thêm vào định nghĩa `session_court_bookings`:

```sql
  price_per_hour numeric NOT NULL DEFAULT 0,
```

và vào `session_intervals`:

```sql
  court_cost numeric NOT NULL DEFAULT 0,
```

Trong `docs/sql-export/04_indexes.sql`, thêm — `refresh_interval_courts` quét bảng này theo `session_id` cho mỗi interval, và khóa ngoại đó đang thiếu index:

```sql
CREATE INDEX IF NOT EXISTS idx_court_bookings_session ON public.session_court_bookings (session_id);
```

- [ ] **Step 4: Sửa `refresh_interval_courts`**

Trong `docs/sql-export/06_functions.sql`, thay toàn bộ thân hàm:

```sql
CREATE OR REPLACE FUNCTION public.refresh_interval_courts(p_session_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
BEGIN
    -- Update lại active_court_count VÀ court_cost cho từng interval thuộc session đó.
    -- active_court_count: đếm số sân phủ interval (hành vi cũ, giữ nguyên).
    -- court_cost: tổng tiền thật của các sân phủ interval, tính theo số giờ overlap.
    --   Buổi cũ có price_per_hour = 0 nên court_cost = 0, và
    --   calculate_session_costs sẽ rơi về công thức cũ.
    UPDATE session_intervals si
    SET active_court_count = (
        SELECT COUNT(*)
        FROM session_court_bookings b
        WHERE b.session_id = p_session_id
          -- Logic Overlap: Booking bắt đầu trước khi Interval kết thúc
          -- VÀ Booking kết thúc sau khi Interval bắt đầu
          AND b.start_time < si.end_time
          AND b.end_time > si.start_time
    ),
    court_cost = COALESCE((
        SELECT SUM(
            b.price_per_hour
            * EXTRACT(epoch FROM (
                LEAST(b.end_time, si.end_time) - GREATEST(b.start_time, si.start_time)
              )) / 3600.0
        )
        FROM session_court_bookings b
        WHERE b.session_id = p_session_id
          AND b.start_time < si.end_time
          AND b.end_time > si.start_time
    ), 0)
    WHERE si.session_id = p_session_id;
END;
$function$;
```

- [ ] **Step 5: Dựng lại bàn test và chạy**

Vì đã đổi định nghĩa bảng, phải dựng lại container từ đầu:

```bash
./db-tests/down.sh && ./db-tests/up.sh && ./db-tests/run.sh
```

Kỳ vọng: mọi file `PASS`, gồm cả `00_smoke` — smoke test chưa có court booking nào nên `court_cost` bằng 0 và tiền không đổi.

- [ ] **Step 6: Commit**

```bash
git add db-tests/10_court_cost.test.sql docs/sql-export/02_tables.sql docs/sql-export/04_indexes.sql docs/sql-export/06_functions.sql
git commit -m "feat(db): price each court booking and derive per-interval court cost"
```

---

## Task 2: Engine tính tiền dùng `court_cost`

Đây là task rủi ro nhất trong plan. Nó chạm vào hàm quyết định số tiền từng người phải trả. Test phải chứng minh cả hai điều: buổi mới tính đúng theo giá sân, và buổi cũ **không đổi một đồng**.

**Files:**
- Create: `db-tests/11_calc_with_court_cost.test.sql`
- Modify: `docs/sql-export/06_functions.sql` (`calculate_session_costs`, khối `court_cost` trong CTE `member_interval_costs`)

**Interfaces:**
- Consumes: `court_cost` từ Task 1
- Produces: `calculate_session_costs(p_session_id uuid)` — chữ ký và tên cột trả về **không đổi**

- [ ] **Step 1: Viết test đỏ**

Tạo `db-tests/11_calc_with_court_cost.test.sql`:

```sql
BEGIN;

-- ── Nhánh cũ: buổi không có giá sân, tiền phải y hệt trước khi sửa ──
-- Fixture: price_per_hour = 0, court_fee_addon = 300k, shuttle = 120k
-- A có mặt cả 2 interval, B có mặt interval 0. Không có ghost.
SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  280000::numeric, 'legacy session: member A unchanged');

SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  140000::numeric, 'legacy session: member B unchanged');

-- ── Nhánh mới: cùng buổi đó, nay có giá sân thật ──
-- Bỏ court_fee_addon để cô lập phần tiền sân mới.
UPDATE sessions SET court_fee_addon = 0, shuttle_fee_total = 0
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time, price_per_hour) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 1',
   '2026-09-01 11:00:00+00', '2026-09-01 11:30:00+00', 120000),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sân 1',
   '2026-09-01 11:30:00+00', '2026-09-01 12:00:00+00', 130000);

SELECT refresh_interval_courts('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

-- court_cost: interval 0 = 120000*0.5 = 60000; interval 1 = 130000*0.5 = 65000
-- interval 0: A và B cùng có mặt, ghost = 0 -> mỗi người 60000/2 = 30000
-- interval 1: chỉ A          -> A thêm 65000/1 = 65000
-- A = 30000 + 65000 = 95000
-- B = 30000
SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '22222222-2222-2222-2222-222222222222'),
  95000::numeric, 'priced session: member A pays for both intervals');

SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '33333333-3333-3333-3333-333333333333'),
  30000::numeric, 'priced session: member B pays for one interval');

-- Tổng thu phải bằng tổng tiền sân thực tế, không thất thoát.
SELECT assert_eq(
  (SELECT sum(total_court_fee) FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  125000::numeric, 'court money adds up to what the courts cost');

-- ── Ghost vẫn chịu tiền sân ──
INSERT INTO members (id, display_name, role, is_active)
VALUES ('44444444-4444-4444-4444-444444444444', 'Ghost', 'member', true);
INSERT INTO session_registrations (session_id, member_id)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '44444444-4444-4444-4444-444444444444');

-- interval 0: real = 2, ghost = 1 -> mẫu số 3 -> 60000/3 = 20000 mỗi suất
-- interval 1: real = 1, ghost = 1 -> mẫu số 2 -> 65000/2 = 32500 mỗi suất
-- Ghost tính cả hai interval: 20000 + 32500 = 52500 -> làm tròn 53000
SELECT assert_eq(
  (SELECT final_total FROM calculate_session_costs('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    WHERE member_id = '44444444-4444-4444-4444-444444444444'),
  53000::numeric, 'ghost still pays court fee under the new model');

ROLLBACK;
```

- [ ] **Step 2: Chạy test, xác nhận đỏ**

```bash
./db-tests/run.sh
```

Kỳ vọng: `FAIL db-tests/11_calc_with_court_cost.test.sql` ở assert `priced session: member A pays for both intervals` — nhận được `0`, vì `price_per_hour` của session bằng 0 và hàm chưa biết đến `court_cost`.

- [ ] **Step 3: Sửa `calculate_session_costs`**

Trong `docs/sql-export/06_functions.sql`, tìm CTE `member_interval_costs`, khối `-- A. COURT FEE — Option C additive (booking cost + addon)`. Thay nhánh trong cùng:

```sql
                            CASE
                                WHEN v_total_court_units > 0 THEN
                                    -- Normal: both booking cost and addon weighted by court-units.
                                    -- booking_cost prefers the real per-booking price when the
                                    -- session has one; sessions created before per-court pricing
                                    -- have court_cost = 0 and fall back to the old formula.
                                    (
                                        CASE
                                            WHEN ist.court_cost > 0 THEN ist.court_cost
                                            ELSE (v_price_per_hour / 2.0) * ist.active_court_count
                                        END
                                        +
                                        (COALESCE(v_court_fee_addon, 0) * ist.active_court_count::numeric / v_total_court_units)
                                    ) / (ist.real_present_count + v_ghost_count)
```

Phần `WHEN v_total_intervals > 0 AND COALESCE(v_court_fee_addon, 0) > 0` và `ELSE 0` phía dưới giữ nguyên.

Để `ist.court_cost` dùng được, thêm cột vào CTE `interval_stats`:

```sql
    interval_stats AS (
        SELECT
            i.id AS interval_id,
            i.active_court_count,
            i.court_cost,
            COUNT(p.member_id) FILTER (WHERE p.is_present = true) AS real_present_count
        FROM session_intervals i
        LEFT JOIN interval_presence p ON p.interval_id = i.id
        WHERE i.session_id = p_session_id
        GROUP BY i.id, i.active_court_count, i.court_cost
    ),
```

Không đụng vào khối `-- B. SHUTTLE FEE`, khối extra fee, hay phép `CEIL` ở cuối.

- [ ] **Step 4: Nạp lại và chạy test**

```bash
docker exec -i bmt-test psql -U postgres -d bmt -v ON_ERROR_STOP=1 -q < docs/sql-export/06_functions.sql
./db-tests/run.sh
```

Kỳ vọng: mọi file `PASS`. `00_smoke` và hai assert "legacy session … unchanged" là bằng chứng buổi cũ không đổi tiền.

- [ ] **Step 5: Đối chiếu trên dữ liệu production, chỉ đọc**

Cột `court_cost` mặc định 0 và migration **không** backfill, nên mọi buổi cũ đi vào nhánh `ELSE`. Kiểm tra lập luận đó bằng số thật, không viết gì lên production:

```sql
-- Chạy qua Supabase MCP, chỉ đọc. Kỳ vọng: 0 dòng.
SELECT s.id, s.title, count(*) AS bookings_with_price
FROM sessions s
JOIN session_court_bookings b ON b.session_id = s.id
WHERE s.deleted_at IS NULL AND b.price_per_hour IS DISTINCT FROM 0
GROUP BY s.id, s.title;
```

Trước ngày chạy migration, cột này chưa tồn tại nên truy vấn sẽ báo lỗi cột — đó là kết quả đúng, ghi lại. Sau khi chạy migration, truy vấn phải trả về **0 dòng**: chưa buổi nào có giá sân, nên chưa buổi nào đổi cách tính.

- [ ] **Step 6: Commit**

```bash
git add db-tests/11_calc_with_court_cost.test.sql docs/sql-export/06_functions.sql
git commit -m "feat(db): use real per-booking court cost when a session has one"
```

---

## Task 3: RPC ghi court booking

Thay cặp `delete` + `insert` mà client đang làm, và đảm bảo `refresh_interval_courts` luôn được gọi sau khi giá đổi.

**Files:**
- Create: `db-tests/12_set_court_bookings.test.sql`
- Modify: `docs/sql-export/06_functions.sql` (thêm hàm mới; sửa `create_session_with_bookings` bản 8 tham số; xóa bản 7 tham số)
- Modify: `docs/sql-export/09_grants.sql`

**Interfaces:**
- Consumes: `refresh_interval_courts` từ Task 1
- Produces:
  - `set_session_court_bookings(p_session_id uuid, p_bookings jsonb) RETURNS void`
    `p_bookings` là mảng object `{"court_name": text, "start_time": timestamptz, "end_time": timestamptz, "price_per_hour": numeric}`
  - `create_session_with_bookings(...)` bản 8 tham số nay đọc thêm `price_per_hour` từ mỗi phần tử `p_bookings`; bản 7 tham số bị xóa

- [ ] **Step 1: Viết test đỏ**

Tạo `db-tests/12_set_court_bookings.test.sql`:

```sql
BEGIN;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

SELECT set_session_court_bookings(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '[{"court_name":"Sân 1","start_time":"2026-09-01T11:00:00+00","end_time":"2026-09-01T11:30:00+00","price_per_hour":120000},
    {"court_name":"Sân 1","start_time":"2026-09-01T11:30:00+00","end_time":"2026-09-01T12:00:00+00","price_per_hour":130000}]'::jsonb);

SELECT assert_eq(
  (SELECT count(*)::int FROM session_court_bookings
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  2, 'two bookings written');

-- RPC phải tự gọi refresh_interval_courts; caller không phải nhớ.
SELECT assert_eq(
  (SELECT court_cost FROM session_intervals WHERE idx = 0
    AND session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  60000::numeric, 'intervals refreshed by the RPC itself');

-- Gọi lại phải thay thế, không cộng dồn.
SELECT set_session_court_bookings(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '[{"court_name":"Sân 2","start_time":"2026-09-01T11:00:00+00","end_time":"2026-09-01T12:00:00+00","price_per_hour":100000}]'::jsonb);

SELECT assert_eq(
  (SELECT count(*)::int FROM session_court_bookings
    WHERE session_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1, 'second call replaces rather than appends');

RESET ROLE;

-- Không phải admin: bị từ chối.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

DO $$
BEGIN
  BEGIN
    PERFORM set_session_court_bookings('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '[]'::jsonb);
    RAISE EXCEPTION 'FAIL non-admin could write court bookings';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    RAISE NOTICE 'ok   non-admin blocked';
  END;
END $$;

RESET ROLE;

-- Buổi đã chốt: bị từ chối, kể cả admin.
UPDATE sessions SET status = 'waiting_for_payment'
WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

DO $$
BEGIN
  BEGIN
    PERFORM set_session_court_bookings('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '[]'::jsonb);
    RAISE EXCEPTION 'FAIL admin could edit a finalized session';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    RAISE NOTICE 'ok   finalized session is locked';
  END;
END $$;

RESET ROLE;
ROLLBACK;
```

- [ ] **Step 2: Chạy test, xác nhận đỏ**

```bash
./db-tests/run.sh
```

Kỳ vọng: `FAIL db-tests/12_set_court_bookings.test.sql` với `function set_session_court_bookings(...) does not exist`.

- [ ] **Step 3: Viết hàm**

Thêm vào `docs/sql-export/06_functions.sql`:

```sql
CREATE OR REPLACE FUNCTION public.set_session_court_bookings(p_session_id uuid, p_bookings jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_status TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Chỉ admin được thực hiện thao tác này';
    END IF;

    SELECT status::text INTO v_status FROM sessions WHERE id = p_session_id;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Không tìm thấy buổi: %', p_session_id;
    END IF;
    IF v_status <> 'open' THEN
        RAISE EXCEPTION 'Không thể sửa sân khi buổi đang ở trạng thái "%".', v_status;
    END IF;

    DELETE FROM session_court_bookings WHERE session_id = p_session_id;

    INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time, price_per_hour)
    SELECT
        p_session_id,
        e->>'court_name',
        (e->>'start_time')::timestamptz,
        (e->>'end_time')::timestamptz,
        COALESCE((e->>'price_per_hour')::numeric, 0)
    FROM jsonb_array_elements(p_bookings) e;

    PERFORM refresh_interval_courts(p_session_id);
END;
$function$;
```

- [ ] **Step 4: Cho `create_session_with_bookings` đọc giá**

Trong bản 8 tham số, phần `INSERT INTO session_court_bookings`, thêm cột `price_per_hour` lấy từ jsonb theo đúng cách trên: `COALESCE((e->>'price_per_hour')::numeric, 0)`.

Xóa hẳn bản 7 tham số (`docs/sql-export/06_functions.sql:526-582`) — nó là code chết và tạo rủi ro PostgREST chọn nhầm overload.

- [ ] **Step 5: Thêm grant**

Nối vào `docs/sql-export/09_grants.sql`:

```sql
REVOKE EXECUTE ON FUNCTION public.set_session_court_bookings(uuid, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_session_court_bookings(uuid, jsonb) TO authenticated;
```

- [ ] **Step 6: Nạp lại và chạy test**

```bash
docker exec -i bmt-test psql -U postgres -d bmt -v ON_ERROR_STOP=1 -q < docs/sql-export/06_functions.sql
docker exec -i bmt-test psql -U postgres -d bmt -v ON_ERROR_STOP=1 -q < docs/sql-export/09_grants.sql
./db-tests/run.sh
```

Kỳ vọng: mọi file `PASS`.

- [ ] **Step 7: Commit**

```bash
git add db-tests/12_set_court_bookings.test.sql docs/sql-export/06_functions.sql docs/sql-export/09_grants.sql
git commit -m "feat(db): add set_session_court_bookings and drop the stale 7-arg overload"
```

---

## Task 4: Danh mục loại cầu và tiền cầu theo ống

**Files:**
- Create: `db-tests/13_shuttle_usage.test.sql`
- Modify: `docs/sql-export/02_tables.sql`
- Modify: `docs/sql-export/06_functions.sql`
- Modify: `docs/sql-export/08_rls.sql`
- Modify: `docs/sql-export/09_grants.sql`

**Interfaces:**
- Consumes: bàn test
- Produces:
  - Bảng `shuttle_types (id uuid, name text, tube_price numeric, per_tube int, is_active boolean, created_at timestamptz)`
  - Cột `sessions.shuttle_usage jsonb NOT NULL DEFAULT '[]'`
  - `set_session_shuttle_usage(p_session_id uuid, p_usage jsonb) RETURNS void` — mỗi phần tử `{"type_id": uuid, "name": text, "tube_price": numeric, "per_tube": int, "used": numeric}`

- [ ] **Step 1: Viết test đỏ**

Tạo `db-tests/13_shuttle_usage.test.sql`:

```sql
BEGIN;

INSERT INTO shuttle_types (id, name, tube_price, per_tube) VALUES
  ('55555555-5555-5555-5555-555555555555', 'Vina',   315000, 12),
  ('66666666-6666-6666-6666-666666666666', 'Victor', 360000, 12);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

SELECT set_session_shuttle_usage(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '[{"type_id":"55555555-5555-5555-5555-555555555555","name":"Vina","tube_price":315000,"per_tube":12,"used":3},
    {"type_id":"66666666-6666-6666-6666-666666666666","name":"Victor","tube_price":360000,"per_tube":12,"used":2}]'::jsonb);

-- 315000/12*3 = 78750 ; 360000/12*2 = 60000 ; tổng = 138750
SELECT assert_eq(
  (SELECT shuttle_fee_total FROM sessions WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  138750::numeric, 'shuttle total derived from tube price and count');

SELECT assert_eq(
  (SELECT jsonb_array_length(shuttle_usage) FROM sessions
    WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  2, 'usage breakdown stored alongside the total');

-- Snapshot: đổi giá trong danh mục không được đổi tiền của buổi.
UPDATE shuttle_types SET tube_price = 999000
WHERE id = '55555555-5555-5555-5555-555555555555';

SELECT assert_eq(
  (SELECT shuttle_fee_total FROM sessions WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  138750::numeric, 'catalog price change does not touch a recorded session');

-- Danh sách rỗng đưa tổng về 0.
SELECT set_session_shuttle_usage('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '[]'::jsonb);
SELECT assert_eq(
  (SELECT shuttle_fee_total FROM sessions WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::numeric, 'clearing usage zeroes the total');

RESET ROLE;

-- Khách không đọc trộm được danh mục? Có — danh mục là public read.
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claim.sub = '';
SELECT assert_eq(
  (SELECT count(*)::int > 0 FROM shuttle_types), true, 'anon can read the catalog');

-- Nhưng không ghi được.
WITH attempt AS (
  UPDATE shuttle_types SET tube_price = 1 RETURNING 1
)
SELECT assert_eq((SELECT count(*)::int FROM attempt), 0, 'anon cannot edit the catalog');

RESET ROLE;
ROLLBACK;
```

- [ ] **Step 2: Chạy test, xác nhận đỏ**

```bash
./db-tests/run.sh
```

Kỳ vọng: `FAIL db-tests/13_shuttle_usage.test.sql` với `relation "shuttle_types" does not exist`.

- [ ] **Step 3: Thêm bảng và cột**

Trong `docs/sql-export/02_tables.sql`:

```sql
CREATE TABLE IF NOT EXISTS public.shuttle_types (
  id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name       text NOT NULL,
  tube_price numeric NOT NULL,
  per_tube   integer NOT NULL DEFAULT 12,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
```

Và thêm vào `sessions`:

```sql
  shuttle_usage jsonb NOT NULL DEFAULT '[]'::jsonb,
```

- [ ] **Step 4: Viết RPC**

Thêm vào `docs/sql-export/06_functions.sql`:

```sql
CREATE OR REPLACE FUNCTION public.set_session_shuttle_usage(p_session_id uuid, p_usage jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_status TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Chỉ admin được thực hiện thao tác này';
    END IF;

    SELECT status::text INTO v_status FROM sessions WHERE id = p_session_id;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Không tìm thấy buổi: %', p_session_id;
    END IF;
    IF v_status <> 'open' THEN
        RAISE EXCEPTION 'Không thể sửa tiền cầu khi buổi đang ở trạng thái "%".', v_status;
    END IF;

    -- Breakdown và tổng tiền được ghi trong cùng một lệnh, nên không có
    -- đường nào để hai giá trị lệch nhau.
    UPDATE sessions
    SET shuttle_usage = p_usage,
        shuttle_fee_total = COALESCE((
            SELECT SUM(
                (e->>'tube_price')::numeric
                / NULLIF((e->>'per_tube')::numeric, 0)
                * (e->>'used')::numeric
            )
            FROM jsonb_array_elements(p_usage) e
        ), 0),
        updated_at = now()
    WHERE id = p_session_id;
END;
$function$;
```

- [ ] **Step 5: Thêm RLS và grant**

Vào `docs/sql-export/08_rls.sql`:

```sql
ALTER TABLE public.shuttle_types ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS shuttle_types_public_read ON public.shuttle_types;
CREATE POLICY shuttle_types_public_read ON public.shuttle_types
  AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS shuttle_types_admin_write ON public.shuttle_types;
CREATE POLICY shuttle_types_admin_write ON public.shuttle_types
  AS PERMISSIVE FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'));
```

Vào `docs/sql-export/09_grants.sql`:

```sql
REVOKE EXECUTE ON FUNCTION public.set_session_shuttle_usage(uuid, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_session_shuttle_usage(uuid, jsonb) TO authenticated;
```

- [ ] **Step 6: Dựng lại bàn test và chạy**

```bash
./db-tests/down.sh && ./db-tests/up.sh && ./db-tests/run.sh
```

Kỳ vọng: mọi file `PASS`.

- [ ] **Step 7: Commit**

```bash
git add db-tests/13_shuttle_usage.test.sql docs/sql-export/02_tables.sql docs/sql-export/06_functions.sql docs/sql-export/08_rls.sql docs/sql-export/09_grants.sql
git commit -m "feat(db): add shuttle type catalog and per-session tube usage"
```

---

## Task 5: Script migration cho production

**Files:**
- Create: `docs/migrations/2026-09-09-phase1-pricing.sql`
- Modify: `docs/migrations/README.md`

**Interfaces:**
- Consumes: mọi thay đổi DB từ Task 1–4
- Produces: một script chạy một lần, bọc trong transaction

- [ ] **Step 1: Viết script**

Tạo `docs/migrations/2026-09-09-phase1-pricing.sql`. Chép nguyên văn thân các hàm đã sửa từ `docs/sql-export/06_functions.sql`.

```sql
-- Phase 1 & 2 — per-court pricing + shuttle tube pricing
-- Run once, after 2026-09-09-phase0-security.sql.

BEGIN;

-- 1. Columns. Defaults are chosen so existing rows keep the old behaviour:
--    price_per_hour = 0 -> court_cost = 0 -> calculate_session_costs falls
--    back to the pre-existing formula. No backfill, on purpose.
ALTER TABLE public.session_court_bookings ADD COLUMN IF NOT EXISTS price_per_hour numeric NOT NULL DEFAULT 0;
ALTER TABLE public.session_intervals      ADD COLUMN IF NOT EXISTS court_cost     numeric NOT NULL DEFAULT 0;
ALTER TABLE public.sessions               ADD COLUMN IF NOT EXISTS shuttle_usage  jsonb   NOT NULL DEFAULT '[]'::jsonb;

CREATE INDEX IF NOT EXISTS idx_court_bookings_session ON public.session_court_bookings (session_id);

-- 2. Catalog table.
CREATE TABLE IF NOT EXISTS public.shuttle_types (
  id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name       text NOT NULL,
  tube_price numeric NOT NULL,
  per_tube   integer NOT NULL DEFAULT 12,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.shuttle_types ENABLE ROW LEVEL SECURITY;
-- <<< two shuttle_types policies from docs/sql-export/08_rls.sql >>>

-- 3. Functions.
-- <<< refresh_interval_courts >>>
-- <<< calculate_session_costs >>>
-- <<< create_session_with_bookings, 8-arg version >>>
-- <<< set_session_court_bookings >>>
-- <<< set_session_shuttle_usage >>>

DROP FUNCTION IF EXISTS public.create_session_with_bookings(text, timestamptz, timestamptz, numeric, numeric, uuid, jsonb);

-- 4. Grants.
REVOKE EXECUTE ON FUNCTION public.set_session_court_bookings(uuid, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.set_session_shuttle_usage(uuid, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_session_court_bookings(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_session_shuttle_usage(uuid, jsonb) TO authenticated;

COMMIT;
```

- [ ] **Step 2: Viết phần runbook**

Nối vào `docs/migrations/README.md` mục cho script này. Phần quan trọng nhất là cổng đối chiếu tiền — chạy **trước** và **sau**, so sánh phải khớp tuyệt đối:

```markdown
## 2026-09-09-phase1-pricing.sql

Chạy sau `2026-09-09-phase0-security.sql`.

### Trước khi chạy — chụp ảnh tiền của mọi buổi

```sql
SELECT s.id, c.member_id, c.final_total
FROM sessions s
CROSS JOIN LATERAL calculate_session_costs(s.id) c
WHERE s.deleted_at IS NULL
ORDER BY s.id, c.member_id;
```

Lưu toàn bộ kết quả ra file `before.csv`.

### Sau khi chạy — chụp lại và so

Chạy đúng truy vấn trên, lưu ra `after.csv`, rồi `diff before.csv after.csv`.

**Phải không có khác biệt nào.** Có khác biệt nghĩa là một buổi cũ vừa bị
đổi tiền — quay lui ngay và tìm nguyên nhân trước khi làm tiếp.

Kiểm tra thêm rằng chưa buổi nào rơi sang nhánh mới:

```sql
SELECT count(*) FROM session_court_bookings WHERE price_per_hour <> 0;
-- kỳ vọng: 0
```

### Rollback

```sql
ALTER TABLE public.session_court_bookings DROP COLUMN IF EXISTS price_per_hour;
ALTER TABLE public.session_intervals      DROP COLUMN IF EXISTS court_cost;
ALTER TABLE public.sessions               DROP COLUMN IF EXISTS shuttle_usage;
DROP TABLE IF EXISTS public.shuttle_types;
DROP FUNCTION IF EXISTS public.set_session_court_bookings(uuid, jsonb);
DROP FUNCTION IF EXISTS public.set_session_shuttle_usage(uuid, jsonb);
```

Sau đó nạp lại `refresh_interval_courts` và `calculate_session_costs` từ
commit trước Task 1.
```

- [ ] **Step 3: Kiểm tra script chạy sạch**

```bash
./db-tests/down.sh && ./db-tests/up.sh
docker exec -i bmt-test psql -U postgres -d bmt -v ON_ERROR_STOP=1 -q \
  < docs/migrations/2026-09-09-phase1-pricing.sql
./db-tests/run.sh
```

Kỳ vọng: script chạy idempotent trên database đã ở trạng thái đích, mọi test `PASS`.

- [ ] **Step 4: Commit**

```bash
git add docs/migrations/
git commit -m "docs(db): add phase 1 pricing migration and money parity runbook"
```

---

## Task 6: Kiểu TypeScript và khóa i18n

Làm trước phần giao diện để các task sau có sẵn kiểu và chuỗi.

**Files:**
- Modify: `src/types/index.ts`
- Modify: `src/locales/messages.ts`

**Interfaces:**
- Produces:

```ts
export interface CourtBooking {
  id: string
  session_id: string
  court_name: string
  start_time: string
  end_time: string
  price_per_hour: number
  created_at: string
}

export interface ShuttleType {
  id: string
  name: string
  tube_price: number
  per_tube: number
  is_active: boolean
}

export interface ShuttleUsageEntry {
  type_id: string
  name: string
  tube_price: number
  per_tube: number
  used: number
}

/** Draft row inside CourtBookingEditor: times are "HH:mm" in VN local time. */
export interface CourtBookingDraft {
  id?: string
  court_name: string
  start_time: string
  end_time: string
  price_per_hour: number
}
```

- [ ] **Step 1: Thêm kiểu**

Trong `src/types/index.ts`: thêm `price_per_hour: number` vào `CourtBooking`, thêm `court_cost: number` vào `Interval`, thêm `shuttle_usage: ShuttleUsageEntry[]` vào `SessionSummary`, và thêm ba interface mới ở trên.

- [ ] **Step 2: Thêm khóa i18n**

Trong `src/locales/messages.ts`, thêm vào **cả** khối `vi` và khối `en`:

```ts
// vi
courtBooking: {
  title: 'Danh sách sân',
  addCourt: 'Thêm sân',
  addSlot: 'Thêm khung giờ',
  courtName: 'Tên sân',
  pricePerHour: 'Giá mỗi giờ',
  removeSlot: 'Xóa khung giờ',
  total: 'Tổng tiền sân',
  overlapError: 'Hai khung giờ của cùng một sân bị trùng nhau',
  outOfBoundsError: 'Khung giờ phải nằm trong giờ buổi',
  endBeforeStartError: 'Giờ kết thúc phải sau giờ bắt đầu',
  intervalPreview: 'Sẽ tạo {count} khung 30 phút',
},
shuttle: {
  title: 'Tiền cầu',
  type: 'Loại cầu',
  addType: 'Thêm loại cầu',
  tubePrice: 'Giá một ống',
  perTube: 'Số quả mỗi ống',
  used: 'Số quả đã dùng',
  total: 'Tổng tiền cầu',
  empty: 'Chưa nhập cầu nào',
  catalogTitle: 'Danh mục loại cầu',
  catalogEmpty: 'Chưa có loại cầu nào',
  saved: 'Đã lưu tiền cầu',
},
```

```ts
// en
courtBooking: {
  title: 'Courts',
  addCourt: 'Add court',
  addSlot: 'Add time slot',
  courtName: 'Court name',
  pricePerHour: 'Price per hour',
  removeSlot: 'Remove slot',
  total: 'Court total',
  overlapError: 'Two slots on the same court overlap',
  outOfBoundsError: 'Slot must fall inside the session time',
  endBeforeStartError: 'End time must be after start time',
  intervalPreview: 'Will create {count} 30-minute slots',
},
shuttle: {
  title: 'Shuttle cost',
  type: 'Shuttle type',
  addType: 'Add shuttle type',
  tubePrice: 'Price per tube',
  perTube: 'Shuttles per tube',
  used: 'Shuttles used',
  total: 'Shuttle total',
  empty: 'No shuttles recorded yet',
  catalogTitle: 'Shuttle catalogue',
  catalogEmpty: 'No shuttle types yet',
  saved: 'Shuttle cost saved',
},
```

- [ ] **Step 3: Kiểm tra**

```bash
pnpm install
pnpm type-check
pnpm i18n:audit
```

Kỳ vọng: type-check sạch; audit không báo khóa thiếu ở một trong hai ngôn ngữ.

- [ ] **Step 4: Commit**

```bash
git add src/types/index.ts src/locales/messages.ts
git commit -m "feat(types): add court pricing and shuttle usage types plus i18n keys"
```

---

## Task 7: Cài Vitest

Repo chưa có test framework nào. `.planning/codebase/TESTING.md` đã đề xuất sẵn Vitest cho stack này; task này làm đúng đề xuất đó, ở mức tối thiểu đủ chạy.

**Files:**
- Modify: `package.json`
- Create: `vitest.config.ts`
- Create: `src/utils/__tests__/courtCost.test.ts`
- Create: `src/utils/courtCost.ts`

**Interfaces:**
- Produces:
  - `pnpm test` — chạy Vitest một lần rồi thoát
  - `src/utils/courtCost.ts`:
    - `courtTotal(bookings: CourtBookingDraft[]): number` — tổng tiền sân của một danh sách nháp
    - `findOverlaps(bookings: CourtBookingDraft[]): number[]` — chỉ số các dòng chồng giờ với một dòng khác cùng `court_name`
    - `shuttleTotal(usage: ShuttleUsageEntry[]): number`

Ba hàm này là phần logic duy nhất trong giao diện có thể tính sai tiền, nên chúng nằm ngoài component để test được mà không cần dựng DOM.

- [ ] **Step 1: Cài dependency**

```bash
pnpm add -D vitest@^3 happy-dom@^15
```

Thêm vào `scripts` trong `package.json`:

```json
"test": "vitest run",
"test:watch": "vitest"
```

- [ ] **Step 2: Cấu hình**

Tạo `vitest.config.ts`:

```ts
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vitest/config'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  test: {
    globals: true,
    environment: 'happy-dom',
  },
})
```

- [ ] **Step 3: Viết test đỏ**

Tạo `src/utils/__tests__/courtCost.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { courtTotal, findOverlaps, shuttleTotal } from '@/utils/courtCost'
import type { CourtBookingDraft, ShuttleUsageEntry } from '@/types'

const draft = (
  court_name: string,
  start_time: string,
  end_time: string,
  price_per_hour: number,
): CourtBookingDraft => ({ court_name, start_time, end_time, price_per_hour })

describe('courtTotal', () => {
  it('charges each slot for the hours it covers', () => {
    expect(
      courtTotal([
        draft('Sân 1', '17:00', '18:00', 120000),
        draft('Sân 1', '18:00', '19:00', 130000),
        draft('Sân 2', '18:00', '20:00', 135000),
      ]),
    ).toBe(520000) // 120000 + 130000 + 270000
  })

  it('handles half hours', () => {
    expect(courtTotal([draft('Sân 1', '18:00', '18:30', 120000)])).toBe(60000)
  })

  it('returns zero for an empty list', () => {
    expect(courtTotal([])).toBe(0)
  })
})

describe('findOverlaps', () => {
  it('flags two slots that overlap on the same court', () => {
    expect(
      findOverlaps([
        draft('Sân 1', '17:00', '18:30', 120000),
        draft('Sân 1', '18:00', '19:00', 130000),
      ]),
    ).toEqual([0, 1])
  })

  it('allows slots that merely touch', () => {
    expect(
      findOverlaps([
        draft('Sân 1', '17:00', '18:00', 120000),
        draft('Sân 1', '18:00', '19:00', 130000),
      ]),
    ).toEqual([])
  })

  it('allows overlapping slots on different courts', () => {
    expect(
      findOverlaps([
        draft('Sân 1', '17:00', '19:00', 120000),
        draft('Sân 2', '17:00', '19:00', 135000),
      ]),
    ).toEqual([])
  })
})

describe('shuttleTotal', () => {
  it('prices part of a tube', () => {
    const usage: ShuttleUsageEntry[] = [
      { type_id: 'a', name: 'Vina', tube_price: 315000, per_tube: 12, used: 3 },
      { type_id: 'b', name: 'Victor', tube_price: 360000, per_tube: 12, used: 2 },
    ]
    expect(shuttleTotal(usage)).toBe(138750)
  })

  it('treats a zero tube size as zero rather than dividing by it', () => {
    expect(
      shuttleTotal([{ type_id: 'a', name: 'X', tube_price: 100000, per_tube: 0, used: 5 }]),
    ).toBe(0)
  })
})
```

- [ ] **Step 4: Chạy test, xác nhận đỏ**

```bash
pnpm test
```

Kỳ vọng: fail vì `src/utils/courtCost.ts` chưa tồn tại.

- [ ] **Step 5: Viết hàm**

Tạo `src/utils/courtCost.ts`:

```ts
import type { CourtBookingDraft, ShuttleUsageEntry } from '@/types'

/** "HH:mm" → số phút kể từ nửa đêm. */
function toMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number)
  return h * 60 + m
}

/** Tổng tiền sân của một danh sách nháp, tính theo số giờ mỗi khung phủ. */
export function courtTotal(bookings: CourtBookingDraft[]): number {
  return bookings.reduce((sum, b) => {
    const hours = (toMinutes(b.end_time) - toMinutes(b.start_time)) / 60
    return hours > 0 ? sum + b.price_per_hour * hours : sum
  }, 0)
}

/**
 * Chỉ số các khung giờ chồng lên một khung khác của cùng một sân.
 * Khung chồng nhau làm refresh_interval_courts cộng tiền sân hai lần,
 * nên giao diện phải chặn lưu chứ không chỉ cảnh báo.
 */
export function findOverlaps(bookings: CourtBookingDraft[]): number[] {
  const bad = new Set<number>()
  for (let i = 0; i < bookings.length; i++) {
    for (let j = i + 1; j < bookings.length; j++) {
      const a = bookings[i]
      const b = bookings[j]
      if (a.court_name !== b.court_name) continue
      if (toMinutes(a.start_time) < toMinutes(b.end_time) &&
          toMinutes(b.start_time) < toMinutes(a.end_time)) {
        bad.add(i)
        bad.add(j)
      }
    }
  }
  return [...bad].sort((x, y) => x - y)
}

/** Tổng tiền cầu. Phải khớp công thức trong set_session_shuttle_usage. */
export function shuttleTotal(usage: ShuttleUsageEntry[]): number {
  return usage.reduce((sum, e) => {
    if (!e.per_tube) return sum
    return sum + (e.tube_price / e.per_tube) * e.used
  }, 0)
}
```

- [ ] **Step 6: Chạy test, xác nhận xanh**

```bash
pnpm test
pnpm type-check
```

- [ ] **Step 7: Commit**

```bash
git add package.json pnpm-lock.yaml vitest.config.ts src/utils/courtCost.ts src/utils/__tests__/
git commit -m "test: add vitest and cover court/shuttle money helpers"
```

---

## Task 8: `CourtBookingEditor.vue`

**Files:**
- Create: `src/components/session/CourtBookingEditor.vue`
- Create: `src/components/session/__tests__/CourtBookingEditor.test.ts`

**Interfaces:**
- Consumes: `courtTotal`, `findOverlaps` từ Task 7; kiểu `CourtBookingDraft` từ Task 6
- Produces:

```ts
defineProps<{
  bookings: CourtBookingDraft[]
  sessionStart: string   // "HH:mm" giờ Việt Nam
  sessionEnd: string     // "HH:mm"
  defaultPrice: number
  disabled?: boolean
}>()

defineEmits<{
  'update:bookings': [CourtBookingDraft[]]
  'update:valid': [boolean]
}>()
```

Component **không** tự gọi Supabase. Nó chỉ soạn mảng và báo hợp lệ hay không; việc lưu do trang cha làm. Nhờ vậy dùng được cho cả buổi chưa tồn tại (form tạo) lẫn buổi đã có (trang chi tiết).

Bố cục: mỗi sân một thẻ, trong thẻ là các khung giờ. Trích phần validate từ `src/components/session/SessionHeader.vue:150-179` trước khi xóa file đó ở Task 12.

- [ ] **Step 1: Viết test đỏ**

Tạo `src/components/session/__tests__/CourtBookingEditor.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import CourtBookingEditor from '@/components/session/CourtBookingEditor.vue'
import type { CourtBookingDraft } from '@/types'

const base: CourtBookingDraft[] = [
  { court_name: 'Sân 1', start_time: '17:00', end_time: '18:00', price_per_hour: 120000 },
  { court_name: 'Sân 1', start_time: '18:00', end_time: '19:00', price_per_hour: 130000 },
  { court_name: 'Sân 2', start_time: '18:00', end_time: '20:00', price_per_hour: 135000 },
]

function mountEditor(bookings = base) {
  setActivePinia(createPinia())
  return mount(CourtBookingEditor, {
    props: { bookings, sessionStart: '17:00', sessionEnd: '20:00', defaultPrice: 120000 },
  })
}

describe('CourtBookingEditor', () => {
  it('groups slots under one card per court', () => {
    const w = mountEditor()
    expect(w.findAll('[data-testid="court-card"]')).toHaveLength(2)
  })

  it('shows the court total', () => {
    const w = mountEditor()
    expect(w.get('[data-testid="court-total"]').text()).toContain('520.000')
  })

  it('reports invalid when two slots on one court overlap', async () => {
    const w = mountEditor([
      { court_name: 'Sân 1', start_time: '17:00', end_time: '18:30', price_per_hour: 120000 },
      { court_name: 'Sân 1', start_time: '18:00', end_time: '19:00', price_per_hour: 130000 },
    ])
    await w.vm.$nextTick()
    expect(w.emitted('update:valid')?.at(-1)).toEqual([false])
    expect(w.text()).toContain('trùng nhau')
  })

  it('reports invalid when a slot falls outside the session window', async () => {
    const w = mountEditor([
      { court_name: 'Sân 1', start_time: '16:00', end_time: '18:00', price_per_hour: 120000 },
    ])
    await w.vm.$nextTick()
    expect(w.emitted('update:valid')?.at(-1)).toEqual([false])
  })

  it('adds a court seeded with the session window and default price', async () => {
    const w = mountEditor()
    await w.get('[data-testid="add-court"]').trigger('click')
    const emitted = w.emitted('update:bookings')?.at(-1)?.[0] as CourtBookingDraft[]
    expect(emitted).toHaveLength(4)
    expect(emitted[3]).toMatchObject({
      start_time: '17:00',
      end_time: '20:00',
      price_per_hour: 120000,
    })
  })

  it('keeps at least one slot', async () => {
    const w = mountEditor([base[0]])
    expect(w.get('[data-testid="remove-slot-0"]').attributes('disabled')).toBeDefined()
  })
})
```

Cài `@vue/test-utils`:

```bash
pnpm add -D @vue/test-utils@^2
```

- [ ] **Step 2: Chạy test, xác nhận đỏ**

```bash
pnpm test
```

Kỳ vọng: fail vì component chưa tồn tại.

- [ ] **Step 3: Viết component**

Tạo `src/components/session/CourtBookingEditor.vue`. Điểm bắt buộc:

- Nhóm bằng `computed` gom `props.bookings` theo `court_name`, giữ chỉ số gốc để emit lại đúng mảng phẳng.
- Mỗi thẻ sân có `data-testid="court-card"`; nút thêm sân `data-testid="add-court"`; nút thêm khung giờ `data-testid="add-slot-<court>"`; nút xóa khung `data-testid="remove-slot-<index>"`; tổng tiền `data-testid="court-total"`.
- Tổng tiền dùng `courtTotal`, hiển thị qua `formatCurrency` từ `@/utils/formatters`.
- Hợp lệ khi: `findOverlaps` rỗng, mọi khung có `end_time > start_time`, mọi khung nằm trong `[sessionStart, sessionEnd]`, và còn ít nhất một khung. `watch` giá trị này với `{ immediate: true }` rồi emit `update:valid`.
- Nút xóa khung bị `disabled` khi tổng số khung bằng 1.
- Thêm sân: đẩy một khung mới `{ court_name: 'Sân ' + (số sân + 1), start_time: sessionStart, end_time: sessionEnd, price_per_hour: defaultPrice }`.
- Mọi nút và input có `min-h-11`; thẻ dùng `rounded-xl border border-gray-200`; tiêu đề sân dùng `text-[20px] font-bold leading-[1.2]`; dưới `sm` xếp dọc, từ `sm` mới xếp ngang.
- Mọi chuỗi qua `t('courtBooking.…')`.

- [ ] **Step 4: Chạy test, xác nhận xanh**

```bash
pnpm test && pnpm type-check
```

- [ ] **Step 5: Commit**

```bash
git add src/components/session/CourtBookingEditor.vue src/components/session/__tests__/ package.json pnpm-lock.yaml
git commit -m "feat(session): add a shared court booking editor with per-slot pricing"
```

---

## Task 9: Dọn `CreateSessionView`

**Files:**
- Modify: `src/views/CreateSessionView.vue`

**Interfaces:**
- Consumes: `CourtBookingEditor` từ Task 8; `create_session_with_bookings` 8 tham số từ Task 3

- [ ] **Step 1: Bỏ hardcode và nhúng editor**

Xóa khối khởi tạo cứng ở `src/views/CreateSessionView.vue:41-43`:

```ts
const bookings = ref<BookingSlot[]>([
  { court_name: 'Sân 1', start_time: '18:00', end_time: '20:00' },
])
```

Thay bằng khởi tạo bám theo giờ buổi, và đồng bộ lại khi giờ buổi đổi:

```ts
const bookings = ref<CourtBookingDraft[]>([
  {
    court_name: 'Sân 1',
    start_time: form.value.startTime,
    end_time: form.value.endTime,
    price_per_hour: 0,
  },
])

// Khung giờ nào vẫn đang trùng khít giờ buổi thì đi theo khi admin đổi giờ.
// Khung đã được sửa tay thì để yên.
watch(
  () => [form.value.startTime, form.value.endTime] as const,
  ([newStart, newEnd], [oldStart, oldEnd]) => {
    bookings.value = bookings.value.map((b) =>
      b.start_time === oldStart && b.end_time === oldEnd
        ? { ...b, start_time: newStart, end_time: newEnd }
        : b,
    )
  },
)
```

Xóa `addBooking`, `removeBooking`, `isBookingEndBeforeStart`, `isBookingOutOfBounds`, `validateBookingTime` và toàn bộ markup soạn sân trong template. Thay bằng:

```vue
<CourtBookingEditor
  v-model:bookings="bookings"
  :session-start="form.startTime"
  :session-end="form.endTime"
  :default-price="0"
  @update:valid="bookingsValid = $event"
/>
```

- [ ] **Step 2: Bỏ ô tiền cầu, làm rõ ô phí sân**

Xóa `shuttleFee` khỏi `form` và xóa input tương ứng. Trong lời gọi RPC, truyền `p_shuttle_fee: 0`.

Đổi nhãn ô `courtFee` sang khóa mới `session.courtFeeAddon` và thêm dòng mô tả bên dưới, để phân biệt với giá theo giờ của từng sân:

```vue
<p class="mt-1 text-sm text-gray-500">{{ t('session.courtFeeAddonHint') }}</p>
```

Thêm hai khóa vào `messages.ts` (cả `vi` và `en`):
- `session.courtFeeAddonHint` — vi: `'Khoản phí sân cố định của cả buổi, cộng thêm ngoài giá theo giờ của từng sân.'` / en: `'A flat court charge for the whole session, added on top of each court hourly price.'`

- [ ] **Step 3: Thêm xem trước số interval**

```ts
const intervalPreview = computed(() => {
  const [sh, sm] = form.value.startTime.split(':').map(Number)
  const [eh, em] = form.value.endTime.split(':').map(Number)
  const minutes = eh * 60 + em - (sh * 60 + sm)
  return minutes > 0 ? Math.ceil(minutes / 30) : 0
})
```

Hiện dưới cặp ô giờ: `{{ t('courtBooking.intervalPreview', { count: intervalPreview }) }}`.

- [ ] **Step 4: Chặn submit khi sân không hợp lệ**

```ts
const bookingsValid = ref(true)
```

Thêm `|| !bookingsValid` vào `:disabled` của nút tạo, và kiểm tra lại trong `createSession()` trước khi gọi RPC.

- [ ] **Step 5: Kiểm tra**

```bash
pnpm type-check && pnpm test && pnpm i18n:audit
```

Chạy `pnpm dev`, mở `/create-session`, và xác nhận bằng tay:
- Đổi giờ buổi từ 18:00–20:00 sang 17:00–19:00 → khung giờ của sân 1 đi theo.
- Thêm sân 2, đặt hai khung giá khác nhau cho sân 1 → tổng tiền sân cập nhật đúng.
- Đặt hai khung chồng nhau trên cùng một sân → hiện lỗi và nút tạo bị khóa.

- [ ] **Step 6: Commit**

```bash
git add src/views/CreateSessionView.vue src/locales/messages.ts
git commit -m "feat(session): drop hardcoded court slot and use the shared editor on create"
```

---

## Task 10: Sửa giờ buổi và giờ sân ở trang chi tiết

Đây là phần khôi phục khả năng đã mất khi `SessionHeader.vue` bị bỏ rơi.

**Files:**
- Modify: `src/views/SessionDetailView.vue`

**Interfaces:**
- Consumes: `CourtBookingEditor`; RPC `recreate_session_intervals`, `set_session_court_bookings`

- [ ] **Step 1: Nạp court booking và dựng bản nháp cho editor**

`CourtBookingEditor` làm việc với `CourtBookingDraft` — giờ dạng `"HH:mm"` theo giờ Việt Nam — còn DB trả về ISO UTC. Cần cả hai ref và một bước đổi qua lại.

Thêm state vào `SessionDetailView.vue`, cạnh các ref sẵn có ở dòng ~51:

```ts
import type { CourtBooking, CourtBookingDraft } from '@/types'

const courtBookings = ref<CourtBooking[]>([])
const courtBookingDrafts = ref<CourtBookingDraft[]>([])
const bookingsValid = ref(true)
```

Trong `fetchData`, nhánh `if (!refreshCostsOnly)`, thêm:

```ts
const { data: bookingsData, error: bookingsError } = await supabase
  .from('session_court_bookings')
  .select('*')
  .eq('session_id', sessionId)
  .order('court_name', { ascending: true })
  .order('start_time', { ascending: true })
if (bookingsError) throw bookingsError
courtBookings.value = bookingsData || []
```

Và trong `startEditing` — hàm mở form sửa; nếu chưa có thì tạo nó và cho nút Sửa gọi vào đây thay vì gán thẳng `isEditingSession = true`:

```ts
function startEditing() {
  if (!session.value) return
  isEditingSession.value = true
  sessionForm.value.session_start = toVNHHmm(session.value.start_time)
  sessionForm.value.session_end = toVNHHmm(session.value.end_time)
  courtBookingDrafts.value = courtBookings.value.map((b) => ({
    id: b.id,
    court_name: b.court_name,
    start_time: toVNHHmm(b.start_time),
    end_time: toVNHHmm(b.end_time),
    price_per_hour: b.price_per_hour ?? 0,
  }))
  // Buổi cũ chưa có court booking nào: mở sẵn một khung phủ cả buổi.
  if (courtBookingDrafts.value.length === 0) {
    courtBookingDrafts.value = [{
      court_name: 'Sân 1',
      start_time: sessionForm.value.session_start,
      end_time: sessionForm.value.session_end,
      price_per_hour: sessionForm.value.price_per_hour ?? 0,
    }]
  }
}
```

- [ ] **Step 2: Thêm ô giờ vào form sửa**

Thêm `session_start` và `session_end` (dạng `"HH:mm"` giờ Việt Nam) vào `sessionForm`. Trích hàm đổi múi giờ từ `SessionHeader.vue:60-63` trước khi xóa file:

```ts
/** Convert ISO UTC string → "HH:mm" in Vietnam timezone (UTC+7) */
function toVNHHmm(iso: string): string {
  const vnMs = new Date(iso).getTime() + 7 * 3600 * 1000
  return new Date(vnMs).toISOString().slice(11, 16)
}
```

Thêm hai input `type="time"` vào lưới form sửa ở dòng ~897, và cảnh báo đỏ khi giờ thay đổi — chuỗi `session.intervalsResetWarning` đã có sẵn trong `messages.ts`:

```vue
<div v-if="timesChanged" class="md:col-span-2 lg:col-span-5">
  <div class="flex items-start gap-2 rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-800">
    <span class="mt-0.5">⚠️</span>
    <span>{{ t('session.intervalsResetWarning') }}</span>
  </div>
</div>
```

- [ ] **Step 3: Gọi hai RPC khi lưu**

Trong `saveSession`, trước lệnh `update` bảng `sessions` đang có:

```ts
const sessionDate = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Ho_Chi_Minh' })
  .format(new Date(session.value.start_time))
const newStartUTC = new Date(`${sessionDate}T${sessionForm.value.session_start}:00+07:00`)
const newEndUTC = new Date(`${sessionDate}T${sessionForm.value.session_end}:00+07:00`)

if (newEndUTC <= newStartUTC) {
  toast.error(t.value('createSession.endTimeError'))
  return
}

const timeChanged =
  newStartUTC.getTime() !== new Date(session.value.start_time).getTime() ||
  newEndUTC.getTime() !== new Date(session.value.end_time).getTime()

if (timeChanged) {
  // Also refreshes interval courts internally.
  const { error: recreateErr } = await supabase.rpc('recreate_session_intervals', {
    p_session_id: sessionId,
    p_start_time: newStartUTC.toISOString(),
    p_end_time: newEndUTC.toISOString(),
  })
  if (recreateErr) throw recreateErr
}
```

Sau lệnh `update`, lưu court booking qua RPC — chuyển `"HH:mm"` về ISO đúng ngày buổi:

```ts
const { error: bookingsErr } = await supabase.rpc('set_session_court_bookings', {
  p_session_id: sessionId,
  p_bookings: courtBookingDrafts.value.map((b) => ({
    court_name: b.court_name,
    start_time: new Date(`${sessionDate}T${b.start_time}:00+07:00`).toISOString(),
    end_time: new Date(`${sessionDate}T${b.end_time}:00+07:00`).toISOString(),
    price_per_hour: b.price_per_hour,
  })),
})
if (bookingsErr) throw bookingsErr
```

- [ ] **Step 4: Nhúng editor**

Trong khối `v-if="isEditingSession && authStore.isAdmin"`, dưới lưới ô nhập:

```vue
<CourtBookingEditor
  v-model:bookings="courtBookingDrafts"
  :session-start="sessionForm.session_start"
  :session-end="sessionForm.session_end"
  :default-price="sessionForm.price_per_hour"
  @update:valid="bookingsValid = $event"
/>
```

Khóa nút Lưu khi `!bookingsValid`.

- [ ] **Step 5: Kiểm tra bằng tay**

```bash
pnpm type-check && pnpm dev
```

Trên một buổi `open`:
- Sửa giờ buổi → số interval trong lưới điểm danh đổi theo, cảnh báo đỏ hiện ra trước khi lưu.
- Thêm hai khung giá cho một sân → bảng chi phí xem trước đổi số ngay sau khi lưu.
- Trên buổi đã `waiting_for_payment` → không thấy khối sửa nào.

- [ ] **Step 6: Commit**

```bash
git add src/views/SessionDetailView.vue
git commit -m "feat(session): restore session time and court editing on the detail page"
```

---

## Task 11: Nhập tiền cầu và danh mục loại cầu

**Files:**
- Create: `src/composables/useShuttleTypes.ts`
- Create: `src/components/session/ShuttleUsageEditor.vue`
- Create: `src/components/session/__tests__/ShuttleUsageEditor.test.ts`
- Modify: `src/views/SessionDetailView.vue`
- Modify: `src/views/SettingsView.vue`

**Interfaces:**
- Consumes: `shuttleTotal` từ Task 7; `set_session_shuttle_usage` từ Task 4
- Produces:
  - `useShuttleTypes()` → `{ types, activeTypes, loading, fetchTypes, addType, updateType, toggleActive }`
  - `ShuttleUsageEditor` props `{ sessionId: string; usage: ShuttleUsageEntry[]; disabled?: boolean }`, emit `{ saved: [ShuttleUsageEntry[]] }`

- [ ] **Step 1: Viết composable**

Tạo `src/composables/useShuttleTypes.ts`. Theo đúng khuôn `src/composables/useBankConfig.ts` đang có: ghi thẳng bảng, vì RLS ở Task 4 đã chặn người không phải admin.

```ts
import { ref, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import type { ShuttleType } from '@/types'

const types = ref<ShuttleType[]>([])
const loading = ref(false)
let loaded = false

export function useShuttleTypes() {
  const activeTypes = computed(() => types.value.filter((t) => t.is_active))

  async function fetchTypes(force = false) {
    if (loaded && !force) return
    loading.value = true
    try {
      const { data, error } = await supabase
        .from('shuttle_types')
        .select('*')
        .order('name', { ascending: true })
      if (error) throw error
      types.value = data || []
      loaded = true
    } finally {
      loading.value = false
    }
  }

  async function addType(input: Omit<ShuttleType, 'id'>) {
    const { error } = await supabase.from('shuttle_types').insert(input)
    if (error) throw error
    await fetchTypes(true)
  }

  async function updateType(id: string, patch: Partial<Omit<ShuttleType, 'id'>>) {
    const { error } = await supabase.from('shuttle_types').update(patch).eq('id', id)
    if (error) throw error
    await fetchTypes(true)
  }

  async function toggleActive(type: ShuttleType) {
    await updateType(type.id, { is_active: !type.is_active })
  }

  return { types, activeTypes, loading, fetchTypes, addType, updateType, toggleActive }
}
```

Ref đặt ngoài hàm nên mọi nơi gọi dùng chung một danh sách — giống cách `useBankConfig` làm, tránh mỗi component tự fetch lại.

- [ ] **Step 2: Viết test đỏ cho editor**

Tạo `src/components/session/__tests__/ShuttleUsageEditor.test.ts`:

```ts
import { describe, it, expect, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import ShuttleUsageEditor from '@/components/session/ShuttleUsageEditor.vue'
import type { ShuttleUsageEntry } from '@/types'

vi.mock('@/composables/useShuttleTypes', () => ({
  useShuttleTypes: () => ({
    activeTypes: { value: [
      { id: 'a', name: 'Vina', tube_price: 315000, per_tube: 12, is_active: true },
      { id: 'b', name: 'Victor', tube_price: 360000, per_tube: 12, is_active: true },
    ] },
    loading: { value: false },
    fetchTypes: vi.fn(),
  }),
}))

const usage: ShuttleUsageEntry[] = [
  { type_id: 'a', name: 'Vina', tube_price: 315000, per_tube: 12, used: 3 },
]

function mountEditor(u = usage) {
  setActivePinia(createPinia())
  return mount(ShuttleUsageEditor, { props: { sessionId: 's1', usage: u } })
}

describe('ShuttleUsageEditor', () => {
  it('shows the running total', () => {
    expect(mountEditor().get('[data-testid="shuttle-total"]').text()).toContain('78.750')
  })

  it('increments the count with the plus stepper', async () => {
    const w = mountEditor()
    await w.get('[data-testid="inc-0"]').trigger('click')
    expect(w.get('[data-testid="shuttle-total"]').text()).toContain('105.000')
  })

  it('never goes below zero', async () => {
    const w = mountEditor([{ ...usage[0], used: 0 }])
    await w.get('[data-testid="dec-0"]').trigger('click')
    expect(w.get('[data-testid="used-0"]').attributes('value')).toBe('0')
  })

  it('shows an empty state when nothing is recorded', () => {
    expect(mountEditor([]).text()).toContain('Chưa nhập cầu nào')
  })
})
```

- [ ] **Step 3: Chạy test, xác nhận đỏ, rồi viết component**

```bash
pnpm test
```

Tạo `src/components/session/ShuttleUsageEditor.vue`. Điểm bắt buộc:

- Mỗi dòng: `<select>` chọn loại cầu từ `activeTypes`, stepper `−` / `<input type="number">` / `+`, và tiền của dòng đó.
- `data-testid`: `inc-<i>`, `dec-<i>`, `used-<i>`, `shuttle-total`, `add-row`, `save`.
- Chọn loại cầu thì **chép** `name`, `tube_price`, `per_tube` vào dòng — đó là snapshot, không phải tham chiếu sống.
- `used` không xuống dưới 0.
- Tổng dùng `shuttleTotal`, hiển thị qua `formatCurrency`.
- Nút Lưu gọi `supabase.rpc('set_session_shuttle_usage', { p_session_id: props.sessionId, p_usage: rows })`, toast `t('shuttle.saved')`, rồi emit `saved`.
- Nút `−`/`+` có `min-h-11 min-w-11` — đây là target chạm chính trên điện thoại.

- [ ] **Step 4: Nhúng vào trang chi tiết**

Trong `SessionDetailView.vue`, đặt ngay trên `<SessionExtraCharges>`:

```vue
<ShuttleUsageEditor
  v-if="session.status === 'open' && authStore.isAdmin"
  :session-id="sessionId"
  :usage="session.shuttle_usage || []"
  @saved="fetchData()"
/>
```

- [ ] **Step 5: Thêm mục danh mục vào Settings**

Trong `SettingsView.vue`, thêm một thẻ `t('shuttle.catalogTitle')` bên dưới phần ngân hàng: danh sách loại cầu với tên, giá ống, số quả mỗi ống, nút bật/tắt `is_active`, và form thêm. Dùng `useShuttleTypes`. Theo đúng cấu trúc thẻ và class của phần ngân hàng đang có trong file.

- [ ] **Step 6: Kiểm tra**

```bash
pnpm test && pnpm type-check && pnpm i18n:audit
```

Bằng tay: thêm hai loại cầu ở `/settings`; mở một buổi `open`, chọn Vina nhập 3 quả và Victor nhập 2 quả, lưu, và xác nhận bảng chi phí xem trước đổi theo đúng 138.750₫.

- [ ] **Step 7: Commit**

```bash
git add src/composables/useShuttleTypes.ts src/components/session/ShuttleUsageEditor.vue src/components/session/__tests__/ src/views/SessionDetailView.vue src/views/SettingsView.vue
git commit -m "feat(session): record shuttle usage from a reusable type catalogue"
```

---

## Task 12: Xóa component chết và cập nhật tài liệu

**Files:**
- Delete: `src/components/session/SessionHeader.vue`, `SessionAttendanceGrid.vue`, `SessionCostSummary.vue`, `SessionPaymentTable.vue`, `SessionGroupPaymentBar.vue`
- Delete: `src/components/MemberUnpaidSessionsModal.vue`
- Modify: `docs/context/06-frontend-arch.md`
- Modify: `docs/context/01-database-schema.md`
- Modify: `docs/context/02-business-logic.md`
- Modify: `docs/context/09-feature-audit-2026-09.md`

- [ ] **Step 1: Xác nhận không còn ai import**

```bash
for c in SessionHeader SessionAttendanceGrid SessionCostSummary SessionPaymentTable SessionGroupPaymentBar MemberUnpaidSessionsModal; do
  printf "%-28s " "$c"
  grep -rl "$c" src/ --include=*.vue --include=*.ts | grep -v "$c.vue" | tr '\n' ' '
  echo
done
```

Kỳ vọng: mọi dòng trống sau tên component. Nếu có file nào hiện ra thì **dừng** — Task 8 và 10 lẽ ra đã trích hết phần cần dùng.

- [ ] **Step 2: Xóa**

```bash
git rm src/components/session/SessionHeader.vue \
       src/components/session/SessionAttendanceGrid.vue \
       src/components/session/SessionCostSummary.vue \
       src/components/session/SessionPaymentTable.vue \
       src/components/session/SessionGroupPaymentBar.vue \
       src/components/MemberUnpaidSessionsModal.vue
pnpm type-check && pnpm test
```

- [ ] **Step 3: Cập nhật tài liệu**

- `01-database-schema.md`: thêm `session_court_bookings.price_per_hour`, `session_intervals.court_cost`, `sessions.shuttle_usage`, bảng `shuttle_types`. Bỏ ghi chú "ít dùng" ở `session_court_bookings` — nay nó giữ giá.
- `02-business-logic.md`: cập nhật công thức tiền sân sang dạng `CASE WHEN court_cost > 0`; thêm `set_session_court_bookings` và `set_session_shuttle_usage` vào bảng RPC; ghi rõ `create_session_with_bookings` chỉ còn một bản.
- `06-frontend-arch.md`: bỏ `components/session/*` cũ; thêm `CourtBookingEditor.vue`, `ShuttleUsageEditor.vue`, `useShuttleTypes.ts`, `SettingsView.vue`, `CashPaymentModal.vue`, `stores/bankConfig.ts`. Sửa mục "Sessions list pattern" cho khớp thực tế: `DashboardView` đọc thẳng `view_session_summary`, chưa dùng `search_sessions_list`.
- `09-feature-audit-2026-09.md`: đánh dấu các mục đã đóng, giữ nguyên phần còn tồn.

- [ ] **Step 4: Commit**

```bash
git add -A src/components docs/context
git commit -m "refactor: delete six stale session components and sync the docs"
```

---

## Self-review khi kết thúc

- [ ] `./db-tests/up.sh && ./db-tests/run.sh` xanh từ máy sạch
- [ ] `pnpm test && pnpm type-check && pnpm i18n:audit` xanh
- [ ] Cổng đối chiếu tiền: `before.csv` và `after.csv` giống hệt nhau
- [ ] `SELECT count(*) FROM session_court_bookings WHERE price_per_hour <> 0` trả về 0 ngay sau migration
- [ ] Không có lệnh ghi nào chạy lên `bufpmpehugzysvmbjlub`
- [ ] `docs/sql-export/` đã phản ánh đúng mọi thay đổi trong plan này
- [ ] Sáu component đã bị xóa, không còn chỗ nào import
