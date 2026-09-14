-- Court pricing guards + one atomic session update.
-- Chạy một lần, sau 2026-09-11-court-name-not-null.sql.
--
-- Nội dung được chép nguyên văn từ docs/sql-export/*.sql (nguồn sự thật),
-- gồm bảy thay đổi:
--   1. calculate_session_costs  -- chốt mô hình giá MỘT LẦN cho cả buổi
--   2. view_session_summary     -- bản sao của cùng biểu thức đó
--   3. create_session_with_bookings -- guard đảo giờ / trùng sân
--   4. set_session_court_bookings   -- guard payload NULL / đảo giờ / trùng sân
--   5. set_session_shuttle_usage    -- guard tube_price âm
--   6. finalize_session             -- từ chối chốt buổi không có gì để chia
--   7. update_session_details (MỚI) -- gộp ba lời gọi sửa buổi vào 1 transaction
--      + trigger chặn phụ thu cho người chưa đăng ký buổi
--
-- Toàn bộ dùng CREATE OR REPLACE, KHÔNG DROP: DROP rồi CREATE sẽ áp lại
-- ALTER DEFAULT PRIVILEGES của Supabase và lặng lẽ trả EXECUTE cho anon.
-- update_session_details là hàm MỚI nên nó nhận grant mặc định đó khi được
-- tạo; REVOKE ở cuối script là bắt buộc, và phải REVOKE FROM PUBLIC, anon
-- (thiếu một trong hai vế là no-op).
--
-- KHÔNG có backfill, KHÔNG có ALTER TABLE, KHÔNG có DELETE. Idempotent:
-- chạy lại lần hai không đổi gì.

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
--   -- kỳ vọng: mismatched_rows = 0, vnd_drift = 0, compared_rows = 266
--
-- 2) Cờ mô hình giá: buổi nào đang có booking CÓ giá?
--    Đo ngày 2026-09-11: 47/47 booking đều price_per_hour = 0, nên MỌI buổi
--    hiện có đi nhánh "công thức giờ cũ" và không buổi nào đổi số tiền.
--
--   SELECT count(*) FILTER (WHERE price_per_hour > 0) AS priced_bookings,
--          count(*)                                   AS total_bookings
--   FROM session_court_bookings;
--   -- kỳ vọng: priced_bookings = 0
--
-- 3) Phụ thu của người CHƯA đăng ký buổi (trigger ở bước 7 sẽ chặn).
--    Trigger chỉ ràng buộc dòng GHI MỚI, không đụng dòng cũ, nên script này
--    chạy được kể cả khi số này khác 0 -- nhưng nếu khác 0 thì DỪNG LẠI và
--    xử lý dữ liệu đó trước: đó đúng là những khoản tiền đang biến mất.
--
--   SELECT count(*) FROM session_extra_charges ex
--   WHERE NOT EXISTS (SELECT 1 FROM session_registrations r
--                     WHERE r.session_id = ex.session_id AND r.member_id = ex.member_id);
--   -- kỳ vọng: 0
--
-- 4) Buổi đang mở mà chốt ra 0 đồng cho tất cả (bước 6 sẽ từ chối chốt).
--
--   SELECT s.id, s.title FROM sessions s
--   WHERE s.deleted_at IS NULL AND s.status = 'open'
--     AND NOT EXISTS (SELECT 1 FROM calculate_session_costs(s.id) c WHERE c.final_total > 0);
--   -- mỗi dòng ở đây là một buổi sẽ KHÔNG chốt được cho tới khi nhập tiền

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ============================================================
-- 1. calculate_session_costs
-- ============================================================
-- Nhánh tiền sân trước đây được chọn theo TỪNG interval trên
-- `ist.court_cost > 0`, không phân biệt được "khung này giá 0" với "buổi
-- này tính theo giờ". Nay cờ được chốt một lần cho cả buổi.
-- court_fee_addon giữ nguyên cách chia theo trọng số court-unit.
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
-- 2. view_session_summary
-- ============================================================
-- View mang bản sao của đúng biểu thức trên; nếu không sửa cùng lúc thì
-- danh sách buổi và hóa đơn thật sẽ lệch nhau ở đúng những buổi trộn giá.
CREATE OR REPLACE VIEW public.view_session_summary AS  SELECT id,
    title,
    start_time,
    end_time,
    (start_time)::date AS session_date,
    status,
    price_per_hour,
    default_court_count,
    COALESCE(court_fee_addon, (0)::numeric) AS court_fee_addon,
    (COALESCE(
        CASE
            WHEN (EXISTS ( SELECT 1
                   FROM session_court_bookings b
                  WHERE ((b.session_id = s.id) AND (b.price_per_hour > (0)::numeric))))
            THEN ( SELECT sum(si.court_cost) AS sum
                     FROM session_intervals si
                    WHERE (si.session_id = s.id))
            ELSE ( SELECT sum(((si.active_court_count)::numeric * (s.price_per_hour / (2)::numeric))) AS sum
                     FROM session_intervals si
                    WHERE (si.session_id = s.id))
        END, (0)::numeric) + COALESCE(court_fee_addon, (0)::numeric)) AS total_court_cost,
    shuttle_fee_total,
    COALESCE(( SELECT sum(ex.amount) AS sum
           FROM session_extra_charges ex
          WHERE (ex.session_id = s.id)), (0)::numeric) AS total_extra_cost,
    ( SELECT count(*) AS count
           FROM session_registrations r
          WHERE (r.session_id = s.id)) AS total_registrations,
    ( SELECT count(*) AS count
           FROM session_intervals si
          WHERE (si.session_id = s.id)) AS total_intervals,
    COALESCE(( SELECT sum(sc.paid_amount) AS sum
           FROM session_costs_snapshot sc
          WHERE (sc.session_id = s.id)), (0)::numeric) AS total_collected
       FROM sessions s
  WHERE (s.deleted_at IS NULL);

-- ============================================================
-- 3. create_session_with_bookings
-- ============================================================
-- Thêm guard đảo giờ và trùng sân, chạy TRƯỚC khi ghi dòng nào. Hàm này
-- vẫn là SECURITY INVOKER, không đổi quyền -- xem phần "Còn lại" ở README.
CREATE OR REPLACE FUNCTION public.create_session_with_bookings(p_title text, p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_price_per_hour numeric, p_shuttle_fee numeric, p_created_by uuid, p_bookings jsonb, p_court_fee_addon numeric DEFAULT 0)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_session_id UUID;
    v_interval_start TIMESTAMPTZ;
    v_interval_end TIMESTAMPTZ;
    v_idx INT := 0;
    v_booking_item JSONB;
    v_court TEXT;
BEGIN
    -- Hai guard dưới đây kiểm tra cùng thứ mà set_session_court_bookings
    -- kiểm tra, và phải chạy TRƯỚC khi ghi bất cứ dòng nào: đây là đường
    -- tạo buổi duy nhất, và CreateSessionView hiển thị nguyên văn
    -- error.message cho người dùng -- để CHECK constraint tự chặn thì
    -- người dùng nhận một chuỗi 23514 tiếng Anh.
    IF p_bookings IS NOT NULL AND jsonb_array_length(p_bookings) > 0 THEN
        -- Giờ kết thúc phải sau giờ bắt đầu.
        SELECT COALESCE(e->>'court_name', e->>'name', 'Sân 1') INTO v_court
        FROM jsonb_array_elements(p_bookings) e
        WHERE (e->>'end_time')::timestamptz <= (e->>'start_time')::timestamptz
        LIMIT 1;
        IF v_court IS NOT NULL THEN
            RAISE EXCEPTION 'Giờ kết thúc phải sau giờ bắt đầu (sân "%")', v_court;
        END IF;

        -- Hai khung cùng một sân mà chồng giờ nhau thì tiền sân bị tính hai
        -- lần: một giờ sân 120000 thành 240000. So sánh theo đúng tên sân sẽ
        -- được ghi (kể cả khi rơi về mặc định 'Sân 1').
        WITH b AS (
            SELECT COALESCE(e->>'court_name', e->>'name', 'Sân 1') AS court,
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
    VALUES (
        p_title, p_start_time, p_end_time, p_price_per_hour, p_shuttle_fee,
        p_court_fee_addon, p_created_by, 'open'
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
                COALESCE(v_booking_item->>'court_name', v_booking_item->>'name', 'Sân 1'),
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
-- 4. set_session_court_bookings
-- ============================================================
-- Thêm guard payload NULL, đảo giờ, trùng sân. '[]' vẫn hợp lệ.
CREATE OR REPLACE FUNCTION public.set_session_court_bookings(p_session_id uuid, p_bookings jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_status TEXT;
    v_court  TEXT;
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

    -- Payload NULL là dữ liệu hỏng, không phải một ý định. jsonb_array_elements(NULL)
    -- trả về 0 dòng, nên mọi guard bên dưới đều "đạt" một cách vô nghĩa, DELETE
    -- vẫn chạy và cả buổi mất sạch tiền sân mà không có lỗi nào.
    -- '[]' thì NGƯỢC LẠI là hợp lệ và phải giữ nguyên như vậy: admin bỏ hết sân
    -- để quay về tính tiền bằng court_fee_addon là một thao tác có thật.
    IF p_bookings IS NULL THEN
        RAISE EXCEPTION 'Thiếu dữ liệu đặt sân (bookings)';
    END IF;

    -- Một sân không tên là vô nghĩa. Thiếu key, JSON null, hoặc chỉ có
    -- khoảng trắng (kể cả tab, xuống dòng -- trim() một tham số chỉ cắt
    -- ký tự space 0x20, không cắt các khoảng trắng khác) đều phải bị chặn
    -- ở đây, trước khi ghi -- không lặng lẽ mặc định về 'Sân 1' như
    -- create_session_with_bookings vẫn làm. IS NULL vẫn cần giữ riêng vì
    -- '~' so với NULL cho ra NULL chứ không phải true, nên regex một mình
    -- sẽ để lọt key bị thiếu.
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_bookings) e
        WHERE e->>'court_name' IS NULL OR e->>'court_name' ~ '^\s*$'
    ) THEN
        RAISE EXCEPTION 'Thiếu tên sân (court_name) trong dữ liệu đặt sân';
    END IF;

    -- Giờ kết thúc phải sau giờ bắt đầu. session_court_bookings_time_order_check
    -- cũng chặn, nhưng nó ném 23514 kèm chuỗi tiếng Anh thẳng lên màn hình.
    SELECT e->>'court_name' INTO v_court
    FROM jsonb_array_elements(p_bookings) e
    WHERE (e->>'end_time')::timestamptz <= (e->>'start_time')::timestamptz
    LIMIT 1;
    IF v_court IS NOT NULL THEN
        RAISE EXCEPTION 'Giờ kết thúc phải sau giờ bắt đầu (sân "%")', v_court;
    END IF;

    -- Hai khung cùng một sân mà chồng giờ nhau thì refresh_interval_courts
    -- cộng cả hai vào cùng một interval: một giờ sân 120000 bị tính thành
    -- 240000. src/utils/courtCost.ts đã chặn, nhưng đó là máy người dùng.
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

-- ============================================================
-- 5. set_session_shuttle_usage
-- ============================================================
-- Thêm guard tube_price âm. tube_price = 0 vẫn hợp lệ.
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

    -- Mỗi phần tử phải có đủ used/tube_price/per_tube và hợp lệ -- thiếu
    -- (NULL) thì SUM() bên dưới sẽ lặng lẽ bỏ qua phần tử đó (đóng góp 0)
    -- trong khi nó vẫn được lưu trong shuttle_usage, làm breakdown và tổng
    -- lệch nhau mà không có tín hiệu gì; used âm thì lặng lẽ trừ tiền;
    -- per_tube = 0 thì NULLIF bên dưới cũng lặng lẽ biến phần tử thành 0.
    -- Từ chối cả ba trước khi ghi.
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_usage) e WHERE e->>'used' IS NULL) THEN
        RAISE EXCEPTION 'Thiếu số lượng ống cầu (used) trong dữ liệu tiền cầu';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_usage) e WHERE e->>'tube_price' IS NULL) THEN
        RAISE EXCEPTION 'Thiếu giá ống cầu (tube_price) trong dữ liệu tiền cầu';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_usage) e WHERE e->>'per_tube' IS NULL) THEN
        RAISE EXCEPTION 'Thiếu số cầu mỗi ống (per_tube) trong dữ liệu tiền cầu';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_usage) e WHERE (e->>'used')::numeric < 0) THEN
        RAISE EXCEPTION 'Số lượng ống cầu (used) không được âm';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_usage) e WHERE (e->>'per_tube')::numeric <= 0) THEN
        RAISE EXCEPTION 'Số cầu mỗi ống (per_tube) phải lớn hơn 0';
    END IF;
    -- tube_price âm thuộc đúng nhóm "lặng lẽ trừ tiền" mà các guard trên
    -- sinh ra để chặn: shuttle_fee_total ra số âm và tiền cầu của từng
    -- thành viên cũng âm theo.
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_usage) e WHERE (e->>'tube_price')::numeric < 0) THEN
        RAISE EXCEPTION 'Giá ống cầu (tube_price) không được âm';
    END IF;

    -- Breakdown và tổng tiền được ghi trong cùng một lệnh, nên không có
    -- đường nào để hai giá trị lệch nhau. Tổng được làm tròn một lần, về
    -- nguyên đồng, sau khi cộng hết -- không làm tròn từng phần tử.
    UPDATE sessions
    SET shuttle_usage = p_usage,
        shuttle_fee_total = ROUND(COALESCE((
            SELECT SUM(
                (e->>'tube_price')::numeric
                / NULLIF((e->>'per_tube')::numeric, 0)
                * (e->>'used')::numeric
            )
            FROM jsonb_array_elements(p_usage) e
        ), 0)),
        updated_at = now()
    WHERE id = p_session_id;
END;
$function$;

-- ============================================================
-- 6. finalize_session
-- ============================================================
-- Từ chối chốt khi vòng lặp không ghi được dòng snapshot nào. UPDATE
-- trạng thái vẫn nằm TRƯỚC vòng lặp (trigger check_session_completion phụ
-- thuộc vào điều đó); RAISE hủy cả lời gọi nên nó được cuộn lại.
CREATE OR REPLACE FUNCTION public.finalize_session(p_session_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    r RECORD;
    v_payment_code TEXT;
    v_rows INT := 0;
BEGIN
    -- Function runs as its owner, so it must check the caller itself.
    IF NOT EXISTS (
        SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Chỉ admin được thực hiện thao tác này';
    END IF;

    -- 1. Update Session Status
    UPDATE sessions 
    SET status = 'waiting_for_payment', updated_at = NOW()
    WHERE id = p_session_id;

    -- 2. Loop tính toán
    FOR r IN SELECT * FROM calculate_session_costs(p_session_id)
    LOOP
        IF r.final_total > 0 THEN -- Hoặc <> 0 nếu chấp nhận âm? Thường nợ âm thì host trả tiền mặt, ko tạo QR.
            v_rows := v_rows + 1;
            v_payment_code := 'CL' || substr(md5(random()::text), 1, 6); 

            INSERT INTO session_costs_snapshot (
                session_id, 
                member_id, 
                final_amount, 
                payment_code, 
                status,
                court_fee_amount,
                shuttle_fee_amount,
                extra_fee_amount -- [MỚI]
            )
            VALUES (
                p_session_id,
                r.member_id,
                r.final_total,
                upper(v_payment_code),
                'pending',
                r.total_court_fee,
                r.total_shuttle_fee,
                r.total_extra_fee -- [MỚI]
            )
            ON CONFLICT (session_id, member_id) DO UPDATE
            SET
                final_amount = EXCLUDED.final_amount,
                court_fee_amount = EXCLUDED.court_fee_amount,
                shuttle_fee_amount = EXCLUDED.shuttle_fee_amount,
                extra_fee_amount = EXCLUDED.extra_fee_amount,
                -- Recompute status: re-finalizing after a price change must not
                -- leave a row marked 'paid' while it owes money again.
                status = CASE
                    WHEN session_costs_snapshot.paid_amount >= EXCLUDED.final_amount
                        THEN 'paid'::public.payment_status
                    WHEN session_costs_snapshot.paid_amount > 0
                        THEN 'partial'::public.payment_status
                    ELSE 'pending'::public.payment_status
                END;
        END IF;
    END LOOP;

    -- 3. Chốt mà không ghi được dòng nợ nào nghĩa là buổi đã sang
    -- "waiting_for_payment" trong khi không ai nợ đồng nào, không có QR nào
    -- được tạo và không có gì để đòi -- im lặng hoàn toàn. Hình dạng này gần
    -- như luôn là quên nhập tiền chứ không phải một buổi miễn phí thật.
    -- RAISE ở đây hủy cả lời gọi, nên UPDATE trạng thái ở bước 1 cũng bị
    -- cuộn lại và buổi vẫn ở nguyên trạng thái cũ (được khóa bằng test).
    IF v_rows = 0 THEN
        RAISE EXCEPTION 'Buổi này không có khoản nào để chia cho thành viên. Kiểm tra lại giá sân và phụ thu tiền sân (court_fee_addon) trước khi chốt.';
    END IF;
END;
$function$;

-- ============================================================
-- 7. update_session_details (HÀM MỚI) + trigger phụ thu
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_session_details(p_session_id uuid, p_title text, p_status session_status, p_court_fee_addon numeric, p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_bookings jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_status TEXT;
    v_start  TIMESTAMPTZ;
    v_end    TIMESTAMPTZ;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Chỉ admin được thực hiện thao tác này';
    END IF;

    SELECT s.status::text, s.start_time, s.end_time
    INTO v_status, v_start, v_end
    FROM sessions s WHERE s.id = p_session_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Không tìm thấy buổi: %', p_session_id;
    END IF;
    IF v_status <> 'open' THEN
        RAISE EXCEPTION 'Không thể sửa buổi khi đang ở trạng thái "%".', v_status;
    END IF;

    -- Ba bước dưới đây trước kia là ba lời gọi PostgREST rời nhau từ
    -- SessionDetailView: dựng lại interval, UPDATE sessions, ghi sân. Hỏng ở
    -- giữa thì điểm danh đã bị xóa còn hai bước sau bị bỏ dở, và buổi ở lại
    -- trạng thái không ai dựng lại được. Gộp vào một hàm là gộp vào một
    -- transaction: hỏng bước nào thì cuộn lại hết.
    --
    -- Chỉ dựng lại interval khi giờ THẬT SỰ đổi: recreate_session_intervals
    -- xóa toàn bộ điểm danh, không được chạy khi admin chỉ sửa tiêu đề.
    IF p_start_time IS DISTINCT FROM v_start OR p_end_time IS DISTINCT FROM v_end THEN
        PERFORM recreate_session_intervals(p_session_id, p_start_time, p_end_time);
    END IF;

    -- Ghi sân SAU khi interval đã dời sang khung giờ mới (để
    -- refresh_interval_courts bên trong nó tính tiền theo đúng khung mới) và
    -- TRƯỚC khi đổi status (nó từ chối buổi không còn 'open').
    PERFORM set_session_court_bookings(p_session_id, p_bookings);

    UPDATE sessions
    SET title           = p_title,
        status          = p_status,
        court_fee_addon = p_court_fee_addon,
        updated_at      = now()
    WHERE id = p_session_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.prevent_charge_for_unregistered_member()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- calculate_session_costs join session_registrations, nên một dòng
    -- session_extra_charges của người CHƯA đăng ký buổi không bao giờ tới
    -- được hóa đơn của ai: không lỗi, không cảnh báo, tiền biến mất.
    -- Chặn ở tầng bảng chứ không ở RPC vì SessionExtraCharges.vue ghi thẳng
    -- vào bảng qua PostgREST, không đi qua RPC nào. CHECK constraint không
    -- làm được việc này (CHECK không được chứa subquery); khóa ngoại ghép
    -- (session_id, member_id) thì làm được nhưng chỉ ném 23503 tiếng Anh.
    IF NOT EXISTS (
        SELECT 1 FROM session_registrations r
        WHERE r.session_id = NEW.session_id AND r.member_id = NEW.member_id
    ) THEN
        RAISE EXCEPTION 'Thành viên này chưa đăng ký buổi, không thể thêm phụ thu';
    END IF;

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS check_charge_member_registered ON public.session_extra_charges;
CREATE TRIGGER check_charge_member_registered BEFORE INSERT OR UPDATE ON session_extra_charges FOR EACH ROW EXECUTE FUNCTION prevent_charge_for_unregistered_member();

-- anon tới được EXECUTE bằng HAI đường độc lập: grant mặc định của
-- PostgreSQL cho PUBLIC ('=X/postgres') và ALTER DEFAULT PRIVILEGES của
-- Supabase cấp thẳng cho anon ('anon=X/postgres'). REVOKE thiếu một trong
-- hai vế là no-op hoàn toàn. Kiểm chứng bằng proacl thô ở phần "SAU KHI
-- CHẠY" -- has_function_privilege() trả true ở cả hai trường hợp nên nó
-- không phân biệt được hỏng với không hỏng.
REVOKE EXECUTE ON FUNCTION public.update_session_details(uuid, text, session_status, numeric, timestamptz, timestamptz, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_session_details(uuid, text, session_status, numeric, timestamptz, timestamptz, jsonb) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.prevent_charge_for_unregistered_member() FROM PUBLIC, anon, authenticated;

COMMIT;

-- ============================================================
-- SAU KHI CHẠY -- so với kết quả đã lưu ở phần "TRƯỚC KHI CHẠY"
-- ============================================================
--
-- 1) Money parity: chạy LẠI ĐÚNG câu ở mục (1) bên trên.
--    Kỳ vọng KHÔNG ĐỔI: mismatched_rows = 0, vnd_drift = 0, compared_rows = 266.
--    Nếu con số này khác 0 sau khi chạy, dừng lại và rollback (xem cuối file):
--    có buổi thật đang có booking price_per_hour > 0 mà đợt đo không thấy.
--
-- 2) Quyền của hàm mới -- đọc proacl THÔ, không dùng has_function_privilege:
--
--   SELECT p.proname, p.prosecdef, p.proconfig, p.proacl
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public'
--     AND p.proname IN ('update_session_details','set_session_court_bookings',
--                       'set_session_shuttle_usage','refresh_interval_courts');
--   -- kỳ vọng cho cả bốn: prosecdef = t
--   --                     proconfig = {"search_path=public, pg_temp"}
--   --                     proacl    KHÔNG chứa '=X/' (PUBLIC) và KHÔNG chứa 'anon='
--
-- 3) Trigger phụ thu tồn tại:
--
--   SELECT tgname FROM pg_trigger
--   WHERE tgrelid = 'public.session_extra_charges'::regclass AND NOT tgisinternal;
--   -- kỳ vọng: check_charge_member_registered
--
-- 4) Kiểm tra nhanh bằng dữ liệu thật, trong transaction tự cuộn lại:
--
--   BEGIN;
--   SELECT set_session_court_bookings('<một buổi đang open>', NULL);  -- kỳ vọng: lỗi tiếng Việt
--   ROLLBACK;
--
-- ============================================================
-- ROLLBACK
-- ============================================================
-- Không có thay đổi schema nào để đảo ngược ngoài trigger. Để quay lại
-- trạng thái trước script này:
--
--   BEGIN;
--   DROP TRIGGER IF EXISTS check_charge_member_registered ON public.session_extra_charges;
--   -- rồi nạp lại sáu hàm + view từ git tại commit ngay trước script này
--   -- (docs/sql-export/{05_views,06_functions}.sql @ 41f557e), bằng
--   -- CREATE OR REPLACE, KHÔNG DROP.
--   COMMIT;
--
-- update_session_details có thể để lại: không có gì gọi nó sau khi
-- SessionDetailView quay về ba lời gọi cũ, và nó đã bị REVOKE khỏi anon.
-- Nếu muốn bỏ hẳn: DROP FUNCTION public.update_session_details(uuid, text,
-- session_status, numeric, timestamptz, timestamptz, jsonb);
