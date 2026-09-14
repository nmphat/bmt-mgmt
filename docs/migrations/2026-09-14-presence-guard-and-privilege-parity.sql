-- Presence guard + privilege parity + NOT NULL trên ba cột tiền của sessions.
-- Chạy một lần, sau 2026-09-11-court-pricing-guards.sql.
--
-- Nội dung được chép nguyên văn từ docs/sql-export/*.sql (nguồn sự thật),
-- gồm năm thay đổi:
--   1. calculate_session_costs -- mẫu số chỉ đếm người ĐÃ đăng ký buổi
--   2. prevent_presence_for_unregistered_member (MỚI) + trigger
--      check_presence_member_registered trên interval_presence
--   3. create_session_with_bookings -- SECURITY DEFINER + search_path +
--      admin check, chặn tên sân rỗng, COALESCE ba tham số tiền về 0
--   4. recreate_session_intervals   -- SECURITY DEFINER + search_path +
--      admin check
--   5. sessions.price_per_hour / court_fee_addon / shuttle_fee_total
--      SET DEFAULT 0 + SET NOT NULL
--
-- Toàn bộ hàm dùng CREATE OR REPLACE, KHÔNG DROP: DROP rồi CREATE sẽ áp lại
-- ALTER DEFAULT PRIVILEGES của Supabase và lặng lẽ trả EXECUTE cho anon.
-- Hai hàm ở bước 3 và 4 đang TỒN TẠI nên CREATE OR REPLACE giữ nguyên ACL
-- cũ của chúng -- mà ACL cũ chính là cái phải sửa, nên REVOKE ở cuối script
-- là bắt buộc, và phải REVOKE FROM PUBLIC, anon (thiếu một trong hai vế là
-- no-op hoàn toàn).
--
-- KHÔNG có backfill, KHÔNG có DELETE. ALTER TABLE ở bước 5 chỉ siết
-- constraint, không sửa một dòng dữ liệu nào (production: 0/54 buổi có NULL).
-- Idempotent: chạy lại lần hai không đổi gì (SET NOT NULL trên cột đã NOT
-- NULL là no-op, DROP TRIGGER IF EXISTS + CREATE TRIGGER dựng lại y hệt).

-- ============================================================
-- TRƯỚC KHI CHẠY -- chạy riêng, lưu kết quả lại để so sánh
-- ============================================================
--
-- 1) Money parity: tính lại toàn bộ và so với snapshot đã chốt.
--    Kỳ vọng: 0 dòng lệch, 0 đồng chênh. Đây là bất biến của migration này.
--
--   WITH recomputed AS (
--     SELECT s.id AS session_id, c.member_id, c.final_total
--     FROM sessions s
--     CROSS JOIN LATERAL calculate_session_costs(s.id) c
--     WHERE s.deleted_at IS NULL
--   )
--   SELECT count(*) FILTER (WHERE r.final_total IS DISTINCT FROM snap.final_amount) AS mismatched_rows,
--          COALESCE(sum(abs(r.final_total - snap.final_amount)), 0)                 AS vnd_drift,
--          count(*)                                                                 AS compared_rows
--   FROM session_costs_snapshot snap
--   JOIN recomputed r ON r.session_id = snap.session_id AND r.member_id = snap.member_id;
--   -- kỳ vọng: mismatched_rows = 0, vnd_drift = 0, compared_rows = 277
--
-- 2) Điểm danh của người CHƯA đăng ký buổi -- đây là thứ bước 1 sửa.
--    Đo ngày 2026-09-14: 3 dòng, tất cả thuộc MỘT buổi đã 'cancelled', buổi
--    đó có 0 snapshot và đã thu 0 đồng. Vì thế parity ở (1) không đổi.
--
--   SELECT si.session_id, s.status, s.title, count(*) AS ghost_presence_rows,
--          count(*) FILTER (WHERE EXISTS (SELECT 1 FROM session_costs_snapshot cs
--                                         WHERE cs.session_id = si.session_id)) AS rows_on_finalized_session
--   FROM interval_presence p
--   JOIN session_intervals si ON si.id = p.interval_id
--   JOIN sessions s ON s.id = si.session_id
--   WHERE NOT EXISTS (SELECT 1 FROM session_registrations r
--                     WHERE r.session_id = si.session_id AND r.member_id = p.member_id)
--   GROUP BY si.session_id, s.status, s.title;
--   -- kỳ vọng: rows_on_finalized_session = 0 trên MỌI dòng.
--   -- Nếu khác 0: DỪNG LẠI. Một buổi đã chốt đang mang hình dạng này thì
--   -- bước 1 sẽ làm parity ở (1) lệch, và phải đối chiếu bằng tay trước.
--   -- Trigger ở bước 2 chỉ ràng buộc dòng GHI MỚI, không đụng dòng cũ.
--
-- 3) Ba cột tiền có NULL nào không (bước 5 sẽ SET NOT NULL).
--
--   SELECT count(*) FILTER (WHERE price_per_hour IS NULL)    AS null_price,
--          count(*) FILTER (WHERE court_fee_addon IS NULL)   AS null_addon,
--          count(*) FILTER (WHERE shuttle_fee_total IS NULL) AS null_shuttle,
--          count(*)                                          AS total_sessions
--   FROM sessions;
--   -- kỳ vọng: 0 / 0 / 0 / 54. Nếu khác 0, SET NOT NULL sẽ ném lỗi và CẢ
--   -- script cuộn lại -- đúng như mong muốn: hãy điền giá trị rồi chạy lại.
--
-- 4) Quyền HIỆN TẠI của hai hàm sắp được siết -- đọc proacl THÔ:
--
--   SELECT p.proname, p.prosecdef, p.proconfig, p.proacl
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public'
--     AND p.proname IN ('create_session_with_bookings','recreate_session_intervals');
--   -- kỳ vọng TRƯỚC khi chạy: prosecdef = f, proconfig = NULL, và proacl
--   -- còn '=X/postgres' (PUBLIC) và/hoặc 'anon=X/postgres'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ============================================================
-- 1. calculate_session_costs -- mẫu số đếm đúng nhóm người của tử số
-- ============================================================
-- real_present_count trước đây đếm MỌI dòng interval_presence, trong khi
-- truy vấn ngoài join session_registrations nên chỉ người đã đăng ký mới ra
-- hóa đơn. Một dòng điểm danh của người chưa đăng ký vì thế chia nhỏ tiền
-- thêm một suất rồi vứt suất đó đi.
CREATE OR REPLACE FUNCTION public.calculate_session_costs(p_session_id uuid)
 RETURNS TABLE(member_id uuid, display_name text, final_total numeric, total_court_fee numeric, total_shuttle_fee numeric, total_extra_fee numeric, intervals_count integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_court_fee_addon      NUMERIC;
    v_price_per_hour       NUMERIC;
    v_total_shuttle_fee    NUMERIC;
    v_total_court_units    INT := 0;
    v_total_intervals      INT := 0;  -- fallback denominator when court bookings don't overlap
    v_ghost_count          INT;
    v_has_priced_booking   BOOLEAN;   -- buổi này dùng giá theo sân hay công thức giờ cũ
BEGIN
    -- 1. Load session config
    SELECT s.court_fee_addon, s.price_per_hour, s.shuttle_fee_total
    INTO v_court_fee_addon, v_price_per_hour, v_total_shuttle_fee
    FROM sessions s
    WHERE s.id = p_session_id;

    -- 1b. Mô hình giá được chốt MỘT LẦN cho cả buổi, không chọn lại theo
    -- từng interval. Chỉ cần một booking có giá là buổi này tính theo giá
    -- sân thật; những khung không có giá (price_per_hour = 0) khi đó đóng
    -- góp đúng 0 đồng, chứ không âm thầm rơi về công thức giờ cũ và bịa ra
    -- tiền cho một khung mà thực tế không tốn gì.
    SELECT EXISTS (
        SELECT 1 FROM session_court_bookings b
        WHERE b.session_id = p_session_id AND b.price_per_hour > 0
    ) INTO v_has_priced_booking;

    -- 2. Total court-units (SUM of active_court_count across all intervals)
    SELECT COALESCE(SUM(si.active_court_count), 0),
           COUNT(si.id)
    INTO v_total_court_units, v_total_intervals
    FROM session_intervals si
    WHERE si.session_id = p_session_id;

    -- 3. Count ghost members
    WITH member_presence_counts AS (
        SELECT r.member_id, COUNT(p.id) FILTER (WHERE p.is_present = true) AS presence_count
        FROM session_registrations r
        JOIN session_intervals i ON i.session_id = r.session_id
        LEFT JOIN interval_presence p ON p.interval_id = i.id AND p.member_id = r.member_id
        WHERE r.session_id = p_session_id
        GROUP BY r.member_id
    )
    SELECT COUNT(*) INTO v_ghost_count
    FROM member_presence_counts
    WHERE presence_count = 0;

    -- 4. Compute costs
    RETURN QUERY
    WITH
    ghost_members AS (
        SELECT r.member_id
        FROM session_registrations r
        JOIN session_intervals i ON i.session_id = r.session_id
        LEFT JOIN interval_presence p ON p.interval_id = i.id AND p.member_id = r.member_id
        WHERE r.session_id = p_session_id
        GROUP BY r.member_id
        HAVING COUNT(p.id) FILTER (WHERE p.is_present = true) = 0
    ),

    -- Mẫu số phải đếm ĐÚNG nhóm người mà tử số chia tiền cho. Truy vấn ở
    -- dưới join session_registrations, nên chỉ người ĐÃ đăng ký mới có mặt
    -- trong hóa đơn; nhưng real_present_count trước đây đếm MỌI dòng
    -- interval_presence. Một dòng điểm danh của người chưa đăng ký vì thế
    -- làm phình mẫu số mà không thêm ai vào tử số: suất tiền sân và tiền
    -- cầu của người đó không tới hóa đơn nào -- không lỗi, không cảnh báo,
    -- tiền biến mất. Trigger check_presence_member_registered chặn dòng
    -- MỚI; điều kiện dưới đây là thứ giữ cho các dòng CŨ không ăn tiền.
    interval_stats AS (
        SELECT
            i.id AS interval_id,
            i.active_court_count,
            i.court_cost,
            COUNT(p.member_id) FILTER (WHERE p.is_present = true) AS real_present_count
        FROM session_intervals i
        LEFT JOIN interval_presence p ON p.interval_id = i.id
            AND EXISTS (SELECT 1 FROM session_registrations r
                        WHERE r.session_id = p_session_id AND r.member_id = p.member_id)
        WHERE i.session_id = p_session_id
        GROUP BY i.id, i.active_court_count, i.court_cost
    ),

    member_interval_costs AS (
        SELECT
            m.id AS mem_id,
            m.display_name,

            -- A. COURT FEE — Option C additive (booking cost + addon)
            CASE
                WHEN (ist.real_present_count + v_ghost_count) > 0 THEN
                    CASE
                        WHEN gm.member_id IS NOT NULL OR p.is_present = true THEN
                            CASE
                                WHEN v_total_court_units > 0 THEN
                                    -- Normal: both booking cost and addon weighted by court-units.
                                    -- booking_cost prefers the real per-booking price when the
                                    -- session has one; sessions created before per-court pricing
                                    -- have court_cost = 0 and fall back to the old formula.
                                    -- Nhánh được chọn theo cờ của cả buổi (v_has_priced_booking),
                                    -- không theo từng interval: buổi có giá sân thì MỌI interval
                                    -- dùng court_cost (kể cả interval bằng 0 -- đúng là không tốn
                                    -- tiền); buổi không có giá sân nào thì MỌI interval dùng công
                                    -- thức giờ cũ. Trộn hai mô hình trong cùng một buổi là cách
                                    -- tiền sân bị bịa thêm cho khung sân miễn phí.
                                    (
                                        CASE
                                            WHEN v_has_priced_booking THEN ist.court_cost
                                            ELSE (v_price_per_hour / 2.0) * ist.active_court_count
                                        END
                                        +
                                        (COALESCE(v_court_fee_addon, 0) * ist.active_court_count::numeric / v_total_court_units)
                                    ) / (ist.real_present_count + v_ghost_count)
                                WHEN v_total_intervals > 0 AND COALESCE(v_court_fee_addon, 0) > 0 THEN
                                    -- Fallback: court bookings don't overlap with intervals
                                    -- (e.g. timezone mismatch). Distribute addon equally per interval.
                                    -- price_per_hour booking cost = 0 (no valid court overlap).
                                    (v_court_fee_addon::numeric / v_total_intervals)
                                    / (ist.real_present_count + v_ghost_count)
                                ELSE 0
                            END
                        ELSE 0
                    END
                ELSE 0
            END AS court_cost,

            -- B. SHUTTLE FEE — only real attendees
            CASE
                WHEN ist.real_present_count > 0 AND v_total_court_units > 0 THEN
                    CASE
                        WHEN p.is_present = true THEN
                            (v_total_shuttle_fee * ist.active_court_count::numeric / v_total_court_units)
                            / ist.real_present_count
                        ELSE 0
                    END
                WHEN ist.real_present_count > 0 AND v_total_intervals > 0 THEN
                    -- Fallback for shuttle when no court overlap either
                    CASE
                        WHEN p.is_present = true THEN
                            (v_total_shuttle_fee / v_total_intervals) / ist.real_present_count
                        ELSE 0
                    END
                ELSE 0
            END AS shuttle_cost,

            CASE WHEN p.is_present = true THEN 1 ELSE 0 END AS is_present_flag

        FROM members m
        CROSS JOIN session_intervals i
        JOIN interval_stats ist ON ist.interval_id = i.id
        LEFT JOIN interval_presence p ON p.interval_id = i.id AND p.member_id = m.id
        JOIN session_registrations r ON r.member_id = m.id AND r.session_id = p_session_id
        LEFT JOIN ghost_members gm ON gm.member_id = m.id
        WHERE i.session_id = p_session_id
    ),

    extra_fee_calc AS (
        SELECT ex.member_id, SUM(ex.amount) AS total_extra
        FROM session_extra_charges ex
        WHERE ex.session_id = p_session_id
        GROUP BY ex.member_id
    )

    SELECT
        mic.mem_id,
        mic.display_name,
        COALESCE(CEIL((SUM(mic.court_cost) + SUM(mic.shuttle_cost) + COALESCE(ef.total_extra, 0)) / 1000.0) * 1000, 0) AS final_total,
        COALESCE(SUM(mic.court_cost), 0)   AS total_court_fee,
        COALESCE(SUM(mic.shuttle_cost), 0) AS total_shuttle_fee,
        COALESCE(ef.total_extra, 0)         AS total_extra_fee,
        COALESCE(SUM(mic.is_present_flag), 0)::INT AS intervals_count
    FROM member_interval_costs mic
    LEFT JOIN extra_fee_calc ef ON ef.member_id = mic.mem_id
    GROUP BY mic.mem_id, mic.display_name, ef.total_extra
    ORDER BY mic.display_name ASC;
END;
$function$;

-- ============================================================
-- 2. Trigger chặn điểm danh cho người chưa đăng ký buổi
-- ============================================================
-- Cùng hình dạng với check_charge_member_registered ở migration trước, chỉ
-- khác là dòng interval_presence không mang session_id nên phải lần ngược
-- interval_id -> session_intervals -> session_id.
CREATE OR REPLACE FUNCTION public.prevent_presence_for_unregistered_member()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Cùng một kiểu hỏng như prevent_charge_for_unregistered_member, nhưng ở
    -- phía MẪU SỐ: calculate_session_costs join session_registrations nên chỉ
    -- người đã đăng ký mới ra hóa đơn, còn số người có mặt trong mỗi interval
    -- lại đếm từ interval_presence. Một dòng điểm danh của người chưa đăng ký
    -- chia nhỏ tiền của cả buổi thêm một suất rồi vứt suất đó đi -- không lỗi,
    -- không cảnh báo, tiền biến mất.
    -- Chặn ở tầng bảng vì SessionDetailView.vue ghi thẳng vào interval_presence
    -- qua PostgREST (upsert), không đi qua RPC nào. Khác với bảng
    -- session_extra_charges, dòng ở đây không có session_id: phải lần ngược
    -- interval_id -> session_intervals -> session_id rồi mới tra đăng ký.
    IF NOT EXISTS (
        SELECT 1
        FROM session_intervals i
        JOIN session_registrations r ON r.session_id = i.session_id
        WHERE i.id = NEW.interval_id AND r.member_id = NEW.member_id
    ) THEN
        RAISE EXCEPTION 'Thành viên này chưa đăng ký buổi, không thể điểm danh';
    END IF;

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS check_presence_member_registered ON public.interval_presence;
CREATE TRIGGER check_presence_member_registered BEFORE INSERT OR UPDATE ON interval_presence FOR EACH ROW EXECUTE FUNCTION prevent_presence_for_unregistered_member();

-- ============================================================
-- 3. create_session_with_bookings -- hardening + tên sân + tiền NULL
-- ============================================================
-- SECURITY DEFINER + SET search_path + admin check (route /create-session đã
-- là requiresAdmin), guard tên sân rỗng bằng tiếng Việt thay vì để CHECK ném
-- 23514 tiếng Anh, và COALESCE ba tham số tiền về 0 để NOT NULL ở bước 5
-- không biến một trường bị thiếu thành 23502 trên màn hình người dùng.
CREATE OR REPLACE FUNCTION public.create_session_with_bookings(p_title text, p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_price_per_hour numeric, p_shuttle_fee numeric, p_created_by uuid, p_bookings jsonb, p_court_fee_addon numeric DEFAULT 0)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_session_id UUID;
    v_interval_start TIMESTAMPTZ;
    v_interval_end TIMESTAMPTZ;
    v_idx INT := 0;
    v_booking_item JSONB;
    v_court TEXT;
BEGIN
    -- Cùng mức bảo vệ với mọi RPC ghi buổi khác của nhánh này. Route
    -- /create-session đã là requiresAuth + requiresAdmin, nên guard này chỉ
    -- nói ở tầng database đúng thứ ứng dụng đã có ý định; nó không đóng
    -- thêm đường nào mà UI đang dùng.
    IF NOT EXISTS (
        SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Chỉ admin được thực hiện thao tác này';
    END IF;

    -- Hai guard dưới đây kiểm tra cùng thứ mà set_session_court_bookings
    -- kiểm tra, và phải chạy TRƯỚC khi ghi bất cứ dòng nào: đây là đường
    -- tạo buổi duy nhất, và CreateSessionView hiển thị nguyên văn
    -- error.message cho người dùng -- để CHECK constraint tự chặn thì
    -- người dùng nhận một chuỗi 23514 tiếng Anh.
    IF p_bookings IS NOT NULL AND jsonb_array_length(p_bookings) > 0 THEN
        -- Một sân không tên là vô nghĩa, và mặc định lặng lẽ về 'Sân 1' còn
        -- tệ hơn im lặng: nó đặt cho người dùng một cái tên họ không gõ, và
        -- hai khung đều không tên sẽ cùng thành 'Sân 1' rồi báo "trùng giờ"
        -- -- một lỗi nói về thứ admin không hề làm. Nhận cùng một luật với
        -- set_session_court_bookings, hàm sửa chính những dòng này: buổi nào
        -- tạo được thì phải sửa lại được.
        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_bookings) e
            WHERE e->>'court_name' IS NULL OR e->>'court_name' ~ '^\s*$'
        ) THEN
            RAISE EXCEPTION 'Thiếu tên sân (court_name) trong dữ liệu đặt sân';
        END IF;

        -- Giờ kết thúc phải sau giờ bắt đầu.
        SELECT e->>'court_name' INTO v_court
        FROM jsonb_array_elements(p_bookings) e
        WHERE (e->>'end_time')::timestamptz <= (e->>'start_time')::timestamptz
        LIMIT 1;
        IF v_court IS NOT NULL THEN
            RAISE EXCEPTION 'Giờ kết thúc phải sau giờ bắt đầu (sân "%")', v_court;
        END IF;

        -- Hai khung cùng một sân mà chồng giờ nhau thì tiền sân bị tính hai
        -- lần: một giờ sân 120000 thành 240000.
        WITH b AS (
            SELECT e->>'court_name' AS court,
                   (e->>'start_time')::timestamptz AS st,
                   (e->>'end_time')::timestamptz   AS et,
                   ord
            FROM jsonb_array_elements(p_bookings) WITH ORDINALITY t(e, ord)
        )
        SELECT x.court INTO v_court
        FROM b x JOIN b y ON y.ord > x.ord
        WHERE x.court = y.court AND x.st < y.et AND x.et > y.st
        LIMIT 1;
        IF v_court IS NOT NULL THEN
            RAISE EXCEPTION 'Sân "%" bị đặt trùng giờ', v_court;
        END IF;
    END IF;

    INSERT INTO sessions (
        title, start_time, end_time, price_per_hour, shuttle_fee_total,
        court_fee_addon, created_by, status
    )
    -- Ba cột tiền này là NOT NULL DEFAULT 0. NULL từ client là một trường bị
    -- thiếu chứ không phải một ý định, và 0 đúng là mặc định mà chính cột đã
    -- khai báo -- nên COALESCE về 0 ở đây thay vì để cột ném 23502 tiếng Anh
    -- lên thẳng CreateSessionView. Buổi 0 đồng không âm thầm trôi được nữa:
    -- finalize_session từ chối chốt một buổi không có gì để chia.
    VALUES (
        p_title, p_start_time, p_end_time,
        COALESCE(p_price_per_hour, 0), COALESCE(p_shuttle_fee, 0),
        COALESCE(p_court_fee_addon, 0), p_created_by, 'open'
    )
    RETURNING id INTO v_session_id;

    v_interval_start := p_start_time;

    WHILE v_interval_start < p_end_time LOOP
        v_interval_end := v_interval_start + INTERVAL '30 minutes';

        IF v_interval_end > p_end_time THEN
            v_interval_end := p_end_time;
        END IF;

        INSERT INTO session_intervals (session_id, start_time, end_time, idx, active_court_count)
        VALUES (v_session_id, v_interval_start, v_interval_end, v_idx, 0);

        v_interval_start := v_interval_end;
        v_idx := v_idx + 1;
    END LOOP;

    IF p_bookings IS NOT NULL AND jsonb_array_length(p_bookings) > 0 THEN
        FOR v_booking_item IN SELECT * FROM jsonb_array_elements(p_bookings)
        LOOP
            INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time, price_per_hour)
            VALUES (
                v_session_id,
                v_booking_item->>'court_name',
                (v_booking_item->>'start_time')::TIMESTAMPTZ,
                (v_booking_item->>'end_time')::TIMESTAMPTZ,
                COALESCE((v_booking_item->>'price_per_hour')::numeric, 0)
            );
        END LOOP;
    ELSE
        INSERT INTO session_court_bookings (session_id, start_time, end_time, court_name)
        VALUES (v_session_id, p_start_time, p_end_time, 'Sân 1 (Mặc định)');
    END IF;

    PERFORM refresh_interval_courts(v_session_id);

    RETURN v_session_id;
END;
$function$;

-- ============================================================
-- 4. recreate_session_intervals -- hardening
-- ============================================================
-- Câu lệnh đầu tiên của hàm này xóa MỌI dòng interval_presence của buổi, nên
-- nó phải hỏi quyền trước khi làm bất cứ gì. update_session_details gọi nó
-- lồng bên trong; cả hai đều SECURITY DEFINER cùng một owner và auth.uid()
-- đọc GUC request.jwt.claims chứ không đọc current_user, nên lời gọi lồng
-- vẫn thấy đúng người gọi thật.
CREATE OR REPLACE FUNCTION public.recreate_session_intervals(p_session_id uuid, p_start_time timestamp with time zone, p_end_time timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
  v_interval_start TIMESTAMPTZ;
  v_interval_end   TIMESTAMPTZ;
  v_idx            INT := 0;
BEGIN
  -- Câu lệnh ĐẦU TIÊN của hàm này xóa sạch điểm danh của cả buổi, nên nó
  -- phải hỏi quyền trước khi làm bất cứ gì. update_session_details gọi hàm
  -- này lồng bên trong: cả hai đều SECURITY DEFINER cùng một owner, và
  -- auth.uid() đọc GUC request.jwt.claims của phiên chứ không đọc
  -- current_user, nên lời gọi lồng vẫn thấy đúng người gọi thật
  -- (15_update_session_details.test.sql pin điều này).
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Chỉ admin được thực hiện thao tác này';
  END IF;

  -- 1. Delete presence records for old intervals (cascade-safe manual delete)
  DELETE FROM interval_presence
  WHERE interval_id IN (
    SELECT id FROM session_intervals WHERE session_id = p_session_id
  );

  -- 2. Delete old intervals
  DELETE FROM session_intervals WHERE session_id = p_session_id;

  -- 3. Update session start/end times
  UPDATE sessions
  SET start_time = p_start_time,
      end_time   = p_end_time,
      updated_at = now()
  WHERE id = p_session_id;

  -- 4. Create new 30-min intervals
  v_interval_start := p_start_time;
  WHILE v_interval_start < p_end_time LOOP
    v_interval_end := v_interval_start + INTERVAL '30 minutes';
    IF v_interval_end > p_end_time THEN
      v_interval_end := p_end_time;
    END IF;

    INSERT INTO session_intervals (session_id, start_time, end_time, idx, active_court_count)
    VALUES (p_session_id, v_interval_start, v_interval_end, v_idx, 0);

    v_interval_start := v_interval_end;
    v_idx := v_idx + 1;
  END LOOP;

  -- 5. Recalculate active_court_count from existing court bookings
  PERFORM refresh_interval_courts(p_session_id);
END;
$function$;

-- ============================================================
-- 5. Ba cột tiền của sessions: SET DEFAULT 0 + SET NOT NULL
-- ============================================================
-- price_per_hour = NULL làm (price_per_hour / 2.0) * active_court_count ra
-- NULL, NULL lan qua tổng, và cả buổi thành miễn phí trên nhánh giá cũ mà
-- không có gì báo. Production: 0/54 buổi có NULL, nên không cần backfill.
-- Nếu có NULL, SET NOT NULL ném lỗi và CẢ script cuộn lại -- đó là hành vi
-- đúng, không được "sửa" bằng cách UPDATE bừa về 0.
ALTER TABLE public.sessions ALTER COLUMN price_per_hour    SET DEFAULT 0;
ALTER TABLE public.sessions ALTER COLUMN court_fee_addon   SET DEFAULT 0;
ALTER TABLE public.sessions ALTER COLUMN shuttle_fee_total SET DEFAULT 0;

ALTER TABLE public.sessions ALTER COLUMN price_per_hour    SET NOT NULL;
ALTER TABLE public.sessions ALTER COLUMN court_fee_addon   SET NOT NULL;
ALTER TABLE public.sessions ALTER COLUMN shuttle_fee_total SET NOT NULL;

-- ============================================================
-- 6. Quyền
-- ============================================================
-- anon tới được EXECUTE bằng HAI đường độc lập: grant mặc định của
-- PostgreSQL cho PUBLIC ('=X/postgres') và ALTER DEFAULT PRIVILEGES của
-- Supabase cấp thẳng cho anon ('anon=X/postgres'). REVOKE thiếu một trong
-- hai vế là no-op hoàn toàn, và has_function_privilege() trả true ở CẢ hai
-- trường hợp nên nó không phân biệt được hỏng với không hỏng. Kiểm chứng
-- bằng proacl THÔ ở phần "SAU KHI CHẠY".
REVOKE EXECUTE ON FUNCTION public.create_session_with_bookings(text, timestamptz, timestamptz, numeric, numeric, uuid, jsonb, numeric) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.create_session_with_bookings(text, timestamptz, timestamptz, numeric, numeric, uuid, jsonb, numeric) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.recreate_session_intervals(uuid, timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.recreate_session_intervals(uuid, timestamptz, timestamptz) TO authenticated;

-- Hàm trigger; không ai được gọi nó qua REST API.
REVOKE EXECUTE ON FUNCTION public.prevent_presence_for_unregistered_member() FROM PUBLIC, anon, authenticated;

COMMIT;

-- ============================================================
-- SAU KHI CHẠY -- so với kết quả đã lưu ở phần "TRƯỚC KHI CHẠY"
-- ============================================================
--
-- 1) Money parity: chạy LẠI ĐÚNG câu ở mục (1) bên trên.
--    Kỳ vọng KHÔNG ĐỔI: mismatched_rows = 0, vnd_drift = 0, compared_rows = 277.
--    Nếu khác 0: một buổi ĐÃ CHỐT có dòng điểm danh của người chưa đăng ký
--    (mục 2 của phần trước lẽ ra đã bắt được), dừng lại và rollback.
--
-- 2) Buổi 'cancelled' mang 3 dòng điểm danh thừa nay tính ra ĐỦ tiền.
--    Nó có 0 snapshot nên không có hóa đơn nào thay đổi; câu này chỉ để
--    nhìn thấy con số đã khớp lại với view:
--
--   SELECT s.id, s.title, s.status,
--          (SELECT sum(c.total_court_fee) FROM calculate_session_costs(s.id) c) AS engine_court,
--          v.total_court_cost                                                    AS view_court
--   FROM sessions s JOIN view_session_summary v ON v.id = s.id
--   WHERE EXISTS (
--     SELECT 1 FROM interval_presence p
--     JOIN session_intervals si ON si.id = p.interval_id
--     WHERE si.session_id = s.id
--       AND NOT EXISTS (SELECT 1 FROM session_registrations r
--                       WHERE r.session_id = si.session_id AND r.member_id = p.member_id));
--   -- kỳ vọng: engine_court = view_court (trước khi chạy là 180000 vs 240000)
--
-- 3) Trigger tồn tại:
--
--   SELECT tgname FROM pg_trigger
--   WHERE tgrelid = 'public.interval_presence'::regclass AND NOT tgisinternal
--   ORDER BY tgname;
--   -- kỳ vọng: check_presence_member_registered, check_session_closed
--
-- 4) Ba cột tiền đã NOT NULL và DEFAULT 0:
--
--   SELECT column_name, is_nullable, column_default
--   FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'sessions'
--     AND column_name IN ('price_per_hour','court_fee_addon','shuttle_fee_total')
--   ORDER BY column_name;
--   -- kỳ vọng cả ba: is_nullable = NO, column_default = 0
--
-- 5) Quyền của HAI hàm vừa siết -- đọc proacl THÔ, KHÔNG dùng
--    has_function_privilege (nó trả true ở cả trường hợp hỏng lẫn không hỏng):
--
--   SELECT p.proname, p.prosecdef, p.proconfig, p.proacl
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public'
--     AND p.proname IN ('create_session_with_bookings','recreate_session_intervals');
--   -- kỳ vọng cho cả hai: prosecdef = t
--   --                     proconfig = {"search_path=public, pg_temp"}
--   --                     proacl    = {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--   --                     -- KHÔNG có '=X/' (PUBLIC), KHÔNG có 'anon='
--
-- 6) Kiểm tra nhanh bằng dữ liệu thật, trong transaction tự cuộn lại:
--
--   BEGIN;
--   INSERT INTO interval_presence (interval_id, member_id, is_present)
--   SELECT si.id, (SELECT id FROM members WHERE NOT EXISTS (
--            SELECT 1 FROM session_registrations r
--            WHERE r.session_id = si.session_id AND r.member_id = members.id) LIMIT 1), true
--   FROM session_intervals si LIMIT 1;   -- kỳ vọng: lỗi tiếng Việt
--   ROLLBACK;
--
-- ============================================================
-- ROLLBACK
-- ============================================================
--
--   BEGIN;
--   DROP TRIGGER IF EXISTS check_presence_member_registered ON public.interval_presence;
--   ALTER TABLE public.sessions ALTER COLUMN price_per_hour    DROP NOT NULL;
--   ALTER TABLE public.sessions ALTER COLUMN court_fee_addon   DROP NOT NULL;
--   ALTER TABLE public.sessions ALTER COLUMN shuttle_fee_total DROP NOT NULL;
--   -- rồi nạp lại ba hàm từ git tại commit ngay trước script này
--   -- (docs/sql-export/06_functions.sql @ 9247953), bằng CREATE OR REPLACE,
--   -- KHÔNG DROP.
--   COMMIT;
--
-- Quyền KHÔNG tự quay lại khi nạp lại thân hàm: nếu thật sự muốn trả
-- create_session_with_bookings / recreate_session_intervals về trạng thái
-- cũ thì phải GRANT EXECUTE ... TO PUBLIC, anon một cách có chủ đích --
-- nhưng đừng, đó chính là lỗ hổng script này vá.
-- prevent_presence_for_unregistered_member có thể để lại: không trigger nào
-- gọi nó sau khi DROP TRIGGER, và nó đã bị REVOKE khỏi mọi role.
