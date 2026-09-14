-- Interval không có ai điểm danh + tiền cầu + guard giờ sân + quét quyền.
-- Chạy một lần, sau 2026-09-14-presence-guard-and-privilege-parity.sql.
--
-- TÊN FILE CÓ CHỮ 'b' LÀ CỐ Ý. '2026-09-14-empty-...' sắp TRƯỚC
-- '2026-09-14-presence-...' theo thứ tự tên file ('e' < 'p'), nên chạy lại cả
-- thư mục sẽ áp presence-guard SAU file này và hoàn tác calculate_session_costs
-- cùng create_session_with_bookings về bản cũ -- đúng cái bẫy mà
-- 2026-09-11-view-total-court-cost.sql đã dính. '14b' > '14-' ở cả locale lẫn
-- LC_ALL=C, nên thứ tự tên file nay TRÙNG với thứ tự phải chạy. Kiểm chứng:
-- container dựng từ export trước nhánh + toàn bộ thư mục theo thứ tự tên file
-- cho drift 0 dòng so với container dựng thẳng từ docs/sql-export/.
--
-- Nội dung được chép NGUYÊN VĂN từ docs/sql-export/*.sql (nguồn sự thật),
-- gồm bảy hàm, không có ALTER TABLE, không có backfill, không có DELETE:
--
--   1. calculate_session_costs
--      a) Tiền sân của một interval mà KHÔNG AI điểm danh trước đây trả về 0
--         và biến mất khỏi mọi hóa đơn, trong khi view_session_summary vẫn
--         cộng đủ -- hai con số trên cùng một màn hình admin lệch nhau mà
--         không có gì đối chiếu. Nay khung đó chia đều cho MỌI người đã đăng
--         ký buổi: sân đã đặt là tốn tiền dù không ai bước vào, và người đặt
--         là người nợ (đúng lý do ghost đang phải trả tiền sân). Ghost nằm
--         trong nhóm đó nên chỉ chịu ĐÚNG MỘT suất, không bị tính hai lần.
--      b) Tiền cầu nay cân theo RIÊNG những interval có người, thay vì theo
--         tổng đơn vị sân của mọi interval. Ghost không trả tiền cầu (luật
--         đã chốt), nên phần tiền cầu của một khung không ai có mặt trước
--         đây không có ai nhận và rơi ra ngoài mọi hóa đơn.
--   2. finalize_session -- từ chối chốt một buổi có shuttle_fee_total > 0 mà
--      chưa ai được điểm danh. Tiền sân của buổi đó vẫn khác 0 nên guard
--      "không có khoản nào để chia" cũ KHÔNG nổ và buổi chốt sạch sẽ với
--      nguyên tiền cầu không đòi của ai.
--   3. set_session_court_bookings  -- khung sân phải nằm TRONG giờ của buổi
--   4. create_session_with_bookings -- cùng guard đó ở đường tạo buổi
--   5. update_session_details      -- COALESCE(p_court_fee_addon, 0)
--   6. add_member_to_session_full_presence -- SECURITY DEFINER + search_path
--      + admin check
--   7. batch_add_members_to_session        -- như trên
--
-- TIỀN CŨ KHÔNG ĐƯỢC PHÉP NHÚC NHÍCH. Bước 1 chỉ đổi hành vi ở những buổi có
-- ít nhất một interval KHÔNG AI điểm danh; đo trên production: hiện không có
-- buổi nào như vậy. Câu 2) trong khối TRƯỚC KHI CHẠY đếm đúng con số đó và
-- phải ra 0 -- nếu khác 0, DỪNG LẠI, vì khi đó bước 1 sẽ dời một hóa đơn đã
-- chốt. Khối money parity (câu 1) là chốt chặn cuối: chạy trước và chạy lại
-- sau, cả hai phải cho 0 dòng lệch / 0 đồng chênh trên 277 dòng snapshot.
--
-- Toàn bộ hàm dùng CREATE OR REPLACE, KHÔNG DROP: DROP rồi CREATE sẽ áp lại
-- ALTER DEFAULT PRIVILEGES của Supabase và lặng lẽ trả EXECUTE cho anon.
-- Hai hàm ở bước 6 và 7 đang TỒN TẠI, nên CREATE OR REPLACE GIỮ NGUYÊN ACL
-- cũ của chúng -- mà ACL cũ chính là cái phải sửa. REVOKE ở cuối script vì
-- thế không phải dọn dẹp, nó LÀ toàn bộ phần sửa quyền, và phải REVOKE
-- FROM PUBLIC, anon: anon tới được EXECUTE bằng hai grant độc lập (mặc định
-- của PostgreSQL cho PUBLIC = '=X/postgres', và ALTER DEFAULT PRIVILEGES của
-- Supabase cấp thẳng cho anon = 'anon=X/postgres'), thiếu một vế là no-op
-- hoàn toàn. Phải đọc proacl THÔ để kiểm chứng; has_function_privilege() trả
-- true ở cả hai trường hợp nên nó không phân biệt được.
--
-- Idempotent: chạy lại lần hai không đổi gì (CREATE OR REPLACE ghi lại cùng
-- một thân hàm, REVOKE/GRANT trên ACL đã đúng là no-op).

-- ============================================================
-- TRƯỚC KHI CHẠY -- chạy riêng, lưu kết quả lại để so sánh
-- ============================================================
--
-- 1) Money parity: tính lại toàn bộ và so với snapshot đã chốt.
--    Kỳ vọng: 0 dòng lệch, 0 đồng chênh, 277 dòng so sánh.
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
--
-- 2) DỪNG LẠI NẾU KHÁC 0. Interval không có ai điểm danh, trên những buổi đã
--    có dòng snapshot (tức là đã chốt tiền). Đây là hình dạng duy nhất mà
--    bước 1 làm đổi số tiền.
--
--   SELECT count(*) AS empty_intervals_on_settled_sessions
--   FROM session_intervals si
--   JOIN sessions s ON s.id = si.session_id AND s.deleted_at IS NULL
--   WHERE EXISTS (SELECT 1 FROM session_costs_snapshot snap WHERE snap.session_id = s.id)
--     AND NOT EXISTS (
--       SELECT 1 FROM interval_presence p
--       JOIN session_registrations r ON r.member_id = p.member_id AND r.session_id = s.id
--       WHERE p.interval_id = si.id AND p.is_present = true);
--   -- kỳ vọng: 0
--
-- 3) Booking nằm ngoài giờ buổi -- guard ở bước 3 và 4 chỉ chặn lần ghi SAU,
--    nó không sửa dữ liệu đang có. Con số này cho biết còn bao nhiêu dòng cũ
--    cần sửa tay trên màn hình sửa buổi (script này KHÔNG đụng vào chúng).
--
--   SELECT b.session_id, b.court_name, b.start_time, b.end_time,
--          s.start_time AS session_start, s.end_time AS session_end
--   FROM session_court_bookings b
--   JOIN sessions s ON s.id = b.session_id AND s.deleted_at IS NULL
--   WHERE b.start_time < s.start_time OR b.end_time > s.end_time
--   ORDER BY b.session_id;
--
-- 4) Buổi có tiền cầu mà chưa ai được điểm danh -- guard mới ở bước 2 sẽ từ
--    chối chốt những buổi này. Buổi đã chốt rồi thì không ảnh hưởng.
--
--   SELECT s.id, s.title, s.status, s.shuttle_fee_total
--   FROM sessions s
--   WHERE s.deleted_at IS NULL AND s.shuttle_fee_total > 0
--     AND s.status = 'open'
--     AND NOT EXISTS (
--       SELECT 1 FROM interval_presence p
--       JOIN session_intervals i ON i.id = p.interval_id AND i.session_id = s.id
--       WHERE p.is_present = true)
--   ORDER BY s.start_time;
--
-- 5) ACL THÔ của hai hàm sắp được gia cố. Kỳ vọng TRƯỚC khi chạy:
--    prosecdef = f, proconfig = NULL, và proacl CHỨA '=X/postgres' và/hoặc
--    'anon=X/postgres'.
--
--   SELECT p.proname, p.prosecdef, p.proconfig, p.proacl
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public'
--     AND p.proname IN ('add_member_to_session_full_presence',
--                       'batch_add_members_to_session');

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ============================================================
-- 1. calculate_session_costs -- interval không ai điểm danh vẫn phải có người trả
-- ============================================================
-- a) Tiền sân: mẫu số rơi về v_registered_count khi real_present_count = 0.
-- Phép chia được đưa ra NGOÀI cả hai nhánh tử số, nên số học của tử số
-- không đổi một ký tự nào: buổi nào cũng có người ở mọi interval thì mẫu số
-- vẫn là real_present_count + v_ghost_count và không một đồng nào xê dịch.
-- b) Tiền cầu: cân theo v_present_court_units / v_present_intervals.
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
    v_registered_count     INT;       -- mẫu số tiền sân của interval không có ai điểm danh
    v_present_court_units  INT := 0;  -- đơn vị sân của RIÊNG những interval có người
    v_present_intervals    INT := 0;  -- số interval có người (fallback của tiền cầu)
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

    -- 3b. Mẫu số của một interval mà KHÔNG AI điểm danh. Sân đã đặt là tốn
    -- tiền dù không ai bước vào, và người đặt là người nợ -- nên khung đó
    -- chia đều cho MỌI người đã đăng ký buổi, đúng lý do đang bắt ghost trả
    -- tiền sân. Trước đây khung đó trả về 0 và toàn bộ tiền sân của nó không
    -- vào hóa đơn của ai.
    SELECT COUNT(*) INTO v_registered_count
    FROM session_registrations r
    WHERE r.session_id = p_session_id;

    -- 3c. Mẫu số của tiền cầu. Tiền cầu chỉ chia cho người CÓ MẶT -- ghost
    -- không trả tiền cầu, luật này đã chốt -- nên trọng số của nó phải chạy
    -- trên RIÊNG những interval có người. Chia cho v_total_court_units
    -- (tính trên MỌI interval) khiến phần tiền cầu của một khung không ai
    -- có mặt không có ai nhận: nó rơi ra ngoài mọi hóa đơn, không lỗi,
    -- không cảnh báo, và danh sách buổi cũng không hiện ra được. Cả buổi
    -- không ai điểm danh thì cả hai biến này bằng 0 và tiền cầu không có
    -- chỗ nào hợp lệ để đi -- đó đúng là lúc finalize_session phải từ chối.
    SELECT COALESCE(SUM(si.active_court_count), 0), COUNT(*)
    INTO v_present_court_units, v_present_intervals
    FROM session_intervals si
    WHERE si.session_id = p_session_id
      AND EXISTS (
          SELECT 1 FROM interval_presence p
          JOIN session_registrations r
            ON r.member_id = p.member_id AND r.session_id = p_session_id
          WHERE p.interval_id = si.id AND p.is_present = true
      );

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
            -- Ai trả khung này: người có mặt + ghost. Nhưng một interval mà
            -- KHÔNG AI điểm danh thì trước đây cả biểu thức trả 0 và tiền
            -- sân của khung đó biến mất khỏi mọi hóa đơn -- trong khi danh
            -- sách buổi vẫn cộng đủ, nên hai con số trên cùng một màn hình
            -- admin lệch nhau mà không có gì đối chiếu. Nay khung đó chia
            -- đều cho mọi người đã đăng ký (v_registered_count). Ghost nằm
            -- trong số đó nên vẫn chỉ chịu ĐÚNG MỘT suất của khung, không
            -- bị tính hai lần.
            CASE
                WHEN gm.member_id IS NOT NULL OR p.is_present = true
                     OR ist.real_present_count = 0 THEN
                    (
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
                                    )
                                WHEN v_total_intervals > 0 AND COALESCE(v_court_fee_addon, 0) > 0 THEN
                                    -- Fallback: court bookings don't overlap with intervals
                                    -- (e.g. timezone mismatch). Distribute addon equally per interval.
                                    -- price_per_hour booking cost = 0 (no valid court overlap).
                                    (v_court_fee_addon::numeric / v_total_intervals)
                                ELSE 0
                            END
                    ) / CASE
                            WHEN ist.real_present_count = 0 THEN v_registered_count
                            ELSE ist.real_present_count + v_ghost_count
                        END
                ELSE 0
            END AS court_cost,

            -- B. SHUTTLE FEE — only real attendees
            -- Mẫu số là v_present_court_units / v_present_intervals (xem 3c),
            -- không phải tổng trên mọi interval: chỉ những khung có người
            -- mới có người để nhận phần tiền cầu của mình.
            CASE
                WHEN p.is_present = true AND v_present_court_units > 0 THEN
                    (v_total_shuttle_fee * ist.active_court_count::numeric / v_present_court_units)
                    / ist.real_present_count
                WHEN p.is_present = true AND v_present_intervals > 0 THEN
                    -- Fallback for shuttle when no court overlap either
                    (v_total_shuttle_fee / v_present_intervals) / ist.real_present_count
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
-- 2. finalize_session -- từ chối buổi có tiền cầu mà chưa ai điểm danh
-- ============================================================
-- Guard cũ chỉ nổ khi KHÔNG ghi được dòng nợ nào. Buổi toàn ghost vẫn có
-- tiền sân để chia nên nó không nổ, và buổi chốt sạch sẽ với nguyên
-- shuttle_fee_total không đòi của ai. RAISE cuộn lại cả UPDATE trạng thái ở
-- bước 1, y như guard cũ.
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
    v_shuttle_split NUMERIC := 0;
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
        v_shuttle_split := v_shuttle_split + r.total_shuttle_fee;

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

    -- 4. Tiền cầu chỉ chia cho người CÓ MẶT. Buổi mà không ai được điểm
    -- danh (mọi người đăng ký đều là ghost) vẫn có tiền sân để chia, nên
    -- guard ở trên KHÔNG nổ và buổi chốt sạch sẽ với nguyên shuttle_fee_total
    -- không đòi của ai. Đó gần như luôn là quên điểm danh chứ không phải một
    -- buổi mua cầu rồi không ai đánh. RAISE cuộn lại cả UPDATE trạng thái ở
    -- bước 1, y như guard trên.
    IF v_shuttle_split = 0
       AND COALESCE((SELECT s.shuttle_fee_total FROM sessions s WHERE s.id = p_session_id), 0) > 0 THEN
        RAISE EXCEPTION 'Buổi này có tiền cầu nhưng chưa ai được điểm danh, không có ai để chia. Điểm danh trước khi chốt.';
    END IF;
END;
$function$;

-- ============================================================
-- 3. set_session_court_bookings -- khung sân phải nằm trong giờ buổi
-- ============================================================
-- refresh_interval_courts cắt overlap bằng LEAST/GREATEST, nên phần thò ra
-- ngoài biến mất TRƯỚC khi tới interval nào: một sân 10:00-14:00 giá
-- 120000/h trên buổi 11:00-12:00 ghi đủ 480000 vào bảng nhưng chỉ 120000
-- được chia. Ở đây view ĐỒNG Ý với engine nên không màn hình nào hiện ra con
-- số thật. Guard KHÔNG sửa dữ liệu cũ -- xem câu 3) ở khối TRƯỚC KHI CHẠY.
CREATE OR REPLACE FUNCTION public.set_session_court_bookings(p_session_id uuid, p_bookings jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_status TEXT;
    v_court  TEXT;
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

    -- Khung sân phải nằm TRONG giờ của buổi. refresh_interval_courts cắt
    -- overlap bằng LEAST/GREATEST, nên phần thò ra ngoài biến mất TRƯỚC khi
    -- tới interval nào: một sân 10:00-14:00 giá 120000/h trên buổi
    -- 11:00-12:00 ghi đủ 480000 vào session_court_bookings nhưng chỉ 120000
    -- được chia. Ở đây view ĐỒNG Ý với engine -- cả hai đọc court_cost đã bị
    -- cắt -- nên không màn hình nào hiện ra con số thật; chỗ duy nhất còn
    -- giữ sự thật là start_time/end_time của chính dòng booking.
    -- Trường hợp cực đoan tệ hơn: khung không chạm interval nào đẩy
    -- v_total_court_units về 0 và calculate_session_costs rơi vào nhánh
    -- fallback -- nhánh bỏ qua cả court_cost lẫn price_per_hour cũ.
    -- CourtBookingEditor đã chặn (isOutOfBounds), nhưng đó là máy người dùng.
    SELECT e->>'court_name' INTO v_court
    FROM jsonb_array_elements(p_bookings) e
    WHERE (e->>'start_time')::timestamptz < v_start
       OR (e->>'end_time')::timestamptz   > v_end
    LIMIT 1;
    IF v_court IS NOT NULL THEN
        RAISE EXCEPTION 'Khung giờ của sân "%" nằm ngoài giờ của buổi', v_court;
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
-- 4. create_session_with_bookings -- cùng guard đó ở đường tạo buổi
-- ============================================================
-- Buổi tạo được thì phải sửa lại được: nếu chỉ đường SỬA từ chối hình dạng
-- này thì màn hình sửa buổi không lưu lại được chính buổi vừa tạo.
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

        -- Khung sân phải nằm TRONG giờ của buổi. refresh_interval_courts cắt
        -- overlap bằng LEAST/GREATEST, nên phần thò ra ngoài biến mất TRƯỚC khi
        -- tới interval nào: một sân 10:00-14:00 giá 120000/h trên buổi
        -- 11:00-12:00 ghi đủ 480000 vào session_court_bookings nhưng chỉ 120000
        -- được chia. Ở đây view ĐỒNG Ý với engine -- cả hai đọc court_cost đã bị
        -- cắt -- nên không màn hình nào hiện ra con số thật; chỗ duy nhất còn
        -- giữ sự thật là start_time/end_time của chính dòng booking.
        -- Trường hợp cực đoan tệ hơn: khung không chạm interval nào đẩy
        -- v_total_court_units về 0 và calculate_session_costs rơi vào nhánh
        -- fallback -- nhánh bỏ qua cả court_cost lẫn price_per_hour cũ.
        -- CourtBookingEditor đã chặn (isOutOfBounds), nhưng đó là máy người dùng.
        SELECT e->>'court_name' INTO v_court
        FROM jsonb_array_elements(p_bookings) e
        WHERE (e->>'start_time')::timestamptz < p_start_time
           OR (e->>'end_time')::timestamptz   > p_end_time
        LIMIT 1;
        IF v_court IS NOT NULL THEN
            RAISE EXCEPTION 'Khung giờ của sân "%" nằm ngoài giờ của buổi', v_court;
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
-- 5. update_session_details -- COALESCE(p_court_fee_addon, 0)
-- ============================================================
-- court_fee_addon là NOT NULL DEFAULT 0 và SessionDetailView in nguyên văn
-- error.message, nên để NULL chạm tới cột là đưa cho người dùng một chuỗi
-- 23502 tiếng Anh. create_session_with_bookings đã COALESCE từ vòng trước.
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

    -- court_fee_addon là NOT NULL DEFAULT 0. SessionDetailView bind nó bằng
    -- v-model.number trên một input type="number", nên xóa trắng ô đó gửi
    -- lên NULL -- và saveSession in nguyên văn error.message, tức là người
    -- dùng nhận một chuỗi 23502 tiếng Anh. COALESCE về đúng DEFAULT mà cột
    -- đã khai báo, y như create_session_with_bookings vẫn làm; NOT NULL vẫn
    -- là chốt chặn cho mọi writer khác.
    UPDATE sessions
    SET title           = p_title,
        status          = p_status,
        court_fee_addon = COALESCE(p_court_fee_addon, 0),
        updated_at      = now()
    WHERE id = p_session_id;
END;
$function$;

-- ============================================================
-- 6. add_member_to_session_full_presence -- SECURITY DEFINER + admin check
-- ============================================================
-- Hàm ghi session_registrations và interval_presence -- số dòng
-- interval_presence chính là mẫu số chia tiền. Trước đây: secdef = false,
-- không search_path, không admin check, anon giữ EXECUTE qua CẢ HAI đường và
-- chỉ bị RLS chặn. Một thành viên đã đăng nhập mà không phải admin thì không
-- bị chặn gì cả.
CREATE OR REPLACE FUNCTION public.add_member_to_session_full_presence(p_session_id uuid, p_member_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
BEGIN
    -- Function runs as its owner, so it must check the caller itself.
    -- Hàm này ghi session_registrations và interval_presence -- số dòng của
    -- interval_presence chính là mẫu số chia tiền, nên một thành viên đã
    -- đăng nhập nhưng không phải admin gọi được nó là kéo được hóa đơn của
    -- mọi người khác xuống.
    IF NOT EXISTS (
        SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Chỉ admin được thực hiện thao tác này';
    END IF;

    -- 1. Đăng ký thành viên vào Session
    -- Cột is_registered_not_attended đã bị loại bỏ, chỉ cần đảm bảo có registration row.
    INSERT INTO session_registrations (session_id, member_id)
    VALUES (p_session_id, p_member_id)
    ON CONFLICT (session_id, member_id) 
    DO NOTHING;

    -- 2. Tick điểm danh (Present = True) cho TẤT CẢ interval của session này
    INSERT INTO interval_presence (interval_id, member_id, is_present)
    SELECT i.id, p_member_id, true
    FROM session_intervals i
    WHERE i.session_id = p_session_id
    ON CONFLICT (interval_id, member_id)
    DO UPDATE SET is_present = true;

END;
$function$;

-- ============================================================
-- 7. batch_add_members_to_session -- SECURITY DEFINER + admin check
-- ============================================================
-- Như trên. Review dựng lại: một non-admin đã đăng nhập gọi hàm này và hóa
-- đơn của mọi người khác tụt xuống -- A từ 280000 còn 164000.
CREATE OR REPLACE FUNCTION public.batch_add_members_to_session(p_session_id uuid, p_member_ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
BEGIN
    -- Function runs as its owner, so it must check the caller itself.
    -- Hàm này ghi session_registrations và interval_presence -- số dòng của
    -- interval_presence chính là mẫu số chia tiền, nên một thành viên đã
    -- đăng nhập nhưng không phải admin gọi được nó là kéo được hóa đơn của
    -- mọi người khác xuống.
    IF NOT EXISTS (
        SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Chỉ admin được thực hiện thao tác này';
    END IF;

    -- 1. Batch Insert vào bảng Registration
    -- Dùng hàm unnest() để "bung" mảng ra thành các dòng dữ liệu
    INSERT INTO session_registrations (session_id, member_id)
    SELECT p_session_id, m_id
    FROM unnest(p_member_ids) AS m_id
    ON CONFLICT (session_id, member_id) 
    DO NOTHING;

    -- 2. Batch Insert vào bảng Presence (Matrix bùng nổ)
    -- Tạo tổ hợp (Cross Join) giữa: Tất cả Intervals của Session x Tất cả Member vừa thêm
    INSERT INTO interval_presence (interval_id, member_id, is_present)
    SELECT i.id, m_id, true
    FROM session_intervals i
    CROSS JOIN unnest(p_member_ids) AS m_id
    WHERE i.session_id = p_session_id
    ON CONFLICT (interval_id, member_id)
    DO UPDATE SET is_present = true;

END;
$function$;

-- ============================================================
-- 8. Quyền EXECUTE cho hai hàm vừa gia cố
-- ============================================================
-- CREATE OR REPLACE ở bước 6 và 7 GIỮ NGUYÊN ACL cũ, nên hai lệnh REVOKE
-- dưới đây là toàn bộ phần sửa quyền, không phải dọn dẹp. Phải có CẢ HAI vế
-- PUBLIC và anon trong cùng một REVOKE: thiếu một vế là no-op hoàn toàn và
-- has_function_privilege() vẫn trả true, đúng cách repo này đã bị lọt bốn lần.
REVOKE EXECUTE ON FUNCTION public.add_member_to_session_full_presence(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.batch_add_members_to_session(uuid, uuid[]) FROM PUBLIC, anon;

GRANT  EXECUTE ON FUNCTION public.add_member_to_session_full_presence(uuid, uuid) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.batch_add_members_to_session(uuid, uuid[]) TO authenticated;

COMMIT;

-- ============================================================
-- SAU KHI CHẠY -- chạy riêng, so với kết quả đã lưu ở trên
-- ============================================================
--
-- 1) Money parity lần hai. PHẢI giống hệt lần đầu: 0 dòng lệch, 0 đồng
--    chênh, 277 dòng so sánh. Đây là bất biến của migration này.
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
--   -- kỳ vọng: 0 | 0 | 277
--
-- 2) Engine so với danh sách buổi, trên MỌI buổi chưa xóa. Đây là phép đo
--    mà money parity KHÔNG làm được: parity chỉ chứng minh engine không đổi,
--    nó không chứng minh engine thu đúng số tiền câu lạc bộ đã trả. So bằng
--    sai số 0.01 đồng vì hai vế cộng cùng một số tiền theo thứ tự khác nhau.
--
--   SELECT count(*) AS sessions_where_the_list_and_the_bills_disagree
--   FROM view_session_summary v
--   WHERE abs(v.total_court_cost
--             - COALESCE((SELECT sum(c.total_court_fee)
--                         FROM calculate_session_costs(v.id) c), 0)) >= 0.01
--     AND EXISTS (SELECT 1 FROM session_registrations r WHERE r.session_id = v.id);
--   -- kỳ vọng: 0
--
-- 3) ACL THÔ của hai hàm vừa gia cố. Không được còn '=X/' (PUBLIC) và không
--    được còn 'anon='. KHÔNG dùng has_function_privilege() để kiểm tra --
--    nó trả true ở cả trường hợp hỏng lẫn không hỏng.
--
--   SELECT p.proname, p.prosecdef, p.proconfig, p.proacl
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public'
--     AND p.proname IN ('add_member_to_session_full_presence',
--                       'batch_add_members_to_session');
--   -- kỳ vọng cả hai: prosecdef = t
--   --                 proconfig = {"search_path=public, pg_temp"}
--   --                 proacl    = {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--
-- 4) Cùng một câu hỏi, dạng đỏ/xanh một dòng:
--
--   SELECT p.proname,
--          p.prosecdef
--            AND array_to_string(p.proconfig, ',') = 'search_path=public, pg_temp'
--            AND p.proacl::text !~ '[{,]=X/'
--            AND p.proacl::text !~ '[{,]anon='
--            AND p.proacl::text ~  '[{,]authenticated=X/' AS fully_hardened
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public'
--     AND p.proname IN ('add_member_to_session_full_presence',
--                       'batch_add_members_to_session');
--   -- kỳ vọng: cả hai dòng fully_hardened = t
--
-- 5) view_session_summary vẫn là bản chốt mô hình giá một lần cho cả buổi.
--    Script này không đụng view, nhưng 2026-09-11-view-total-court-cost.sql
--    từng hoàn tác nó khi chạy lại cả thư mục theo thứ tự tên file.
--
--   SELECT CASE WHEN pg_get_viewdef('public.view_session_summary'::regclass)
--                 ~ 'si.court_cost > ' THEN 'per-interval (SAI)'
--               ELSE 'session-level (đúng)' END;
--   -- kỳ vọng: session-level (đúng)

-- ============================================================
-- ROLLBACK
-- ============================================================
-- Không có ALTER TABLE, không có dữ liệu bị ghi, nên rollback chỉ là nạp lại
-- bảy hàm ở bản trước. Chạy trong MỘT transaction:
--
--   BEGIN;
--   -- nạp lại từ 43674cc:docs/sql-export/06_functions.sql các hàm:
--   --   calculate_session_costs, finalize_session, set_session_court_bookings,
--   --   create_session_with_bookings, update_session_details,
--   --   add_member_to_session_full_presence, batch_add_members_to_session
--   -- KHÔNG DROP -- CREATE OR REPLACE giữ ACL.
--   COMMIT;
--
-- Phần quyền ở bước 8 KHÔNG cần rollback và không nên rollback: trả EXECUTE
-- cho anon trên hai hàm ghi bảng đó là mở lại đúng lỗ vừa bịt. Nếu bắt buộc
-- phải trả (một client nào đó thật sự gọi bằng anon key):
--   GRANT EXECUTE ON FUNCTION public.add_member_to_session_full_presence(uuid, uuid) TO anon;
--   GRANT EXECUTE ON FUNCTION public.batch_add_members_to_session(uuid, uuid[]) TO anon;
