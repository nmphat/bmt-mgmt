CREATE OR REPLACE FUNCTION public.add_manual_payment(p_snapshot_id uuid, p_amount numeric, p_note text DEFAULT 'Tiền mặt'::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_final_amount NUMERIC;
    v_current_paid NUMERIC;
    v_new_paid NUMERIC;
BEGIN
    IF p_snapshot_id IS NULL THEN
        RAISE EXCEPTION 'p_snapshot_id is required';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'p_amount must be > 0';
    END IF;

    -- 1. Lấy thông tin hiện tại của khoản nợ
    SELECT final_amount, paid_amount
    INTO v_final_amount, v_current_paid
    FROM session_costs_snapshot
    WHERE id = p_snapshot_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Snapshot not found: %', p_snapshot_id;
    END IF;

    -- 2. Insert vào bảng Payments
    INSERT INTO session_payments (
        snapshot_id,
        amount,
        transaction_id,
        raw_content,
        payment_method,
        note
    )
    VALUES (
        p_snapshot_id,
        p_amount,
        'CASH-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS') || '-' || substr(md5(random()::text), 1, 6),
        p_note,
        'cash',
        p_note
    );

    -- 3. Cập nhật lại Snapshot
    v_new_paid := COALESCE(v_current_paid, 0) + p_amount;

    UPDATE session_costs_snapshot
    SET
        paid_amount = v_new_paid,
        status = CASE
            WHEN v_new_paid >= v_final_amount THEN 'paid'::public.payment_status
            ELSE 'partial'::public.payment_status
        END
    WHERE id = p_snapshot_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.add_member_to_session_full_presence(p_session_id uuid, p_member_id uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
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
$function$

CREATE OR REPLACE FUNCTION public.batch_add_members_to_session(p_session_id uuid, p_member_ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
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
$function$

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
BEGIN
    -- 1. Load session config
    SELECT s.court_fee_addon, s.price_per_hour, s.shuttle_fee_total
    INTO v_court_fee_addon, v_price_per_hour, v_total_shuttle_fee
    FROM sessions s
    WHERE s.id = p_session_id;

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
            COUNT(p.member_id) FILTER (WHERE p.is_present = true) AS real_present_count
        FROM session_intervals i
        LEFT JOIN interval_presence p ON p.interval_id = i.id
        WHERE i.session_id = p_session_id
        GROUP BY i.id, i.active_court_count
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
                                    -- Normal: both booking cost and addon weighted by court-units
                                    (
                                        ((v_price_per_hour / 2.0) * ist.active_court_count)
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
$function$

CREATE OR REPLACE FUNCTION public.check_qr_status(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_type TEXT;
    v_target_amount NUMERIC; -- Số tiền mục tiêu cần thu của mã này
    v_current_remaining NUMERIC; -- Số nợ thực tế còn lại trong DB
    v_paid_progress NUMERIC; -- Số tiền đã trả được cho mục tiêu này
    v_details JSONB;
BEGIN
    -- 1. CASE SINGLE (CL...)
    IF p_code LIKE 'CL%' THEN
        SELECT 
            'single',
            scs.final_amount, -- Với Single, mục tiêu luôn là Tổng bill
            (scs.final_amount - scs.paid_amount), -- Nợ còn lại
            jsonb_build_array(
                jsonb_build_object(
                    'name', m.display_name,
                    'amount', scs.final_amount, -- Tổng nợ gốc
                    'remaining', (scs.final_amount - scs.paid_amount), -- Còn nợ
                    'status', scs.status
                )
            )
        INTO v_type, v_target_amount, v_current_remaining, v_details
        FROM session_costs_snapshot scs
        JOIN members m ON m.id = scs.member_id
        WHERE scs.payment_code = p_code;
        
        -- Với Single, paid_progress chính là tổng đã trả
        v_paid_progress := v_target_amount - v_current_remaining;

    -- 2. CASE GROUP (GR...)
    ELSIF p_code LIKE 'GR%' THEN
        -- Bước 1: Lấy mục tiêu ban đầu của Group (Lúc tạo mã nợ bao nhiêu?)
        SELECT total_amount INTO v_target_amount
        FROM group_payment_requests
        WHERE group_code = p_code;

        -- Bước 2: Tính tổng nợ THỰC TẾ hiện tại của các thành viên trong list
        SELECT 
            'group',
            COALESCE(SUM(s.final_amount - s.paid_amount), 0),
            jsonb_agg(
                jsonb_build_object(
                    'name', m.display_name,
                    'amount', (s.final_amount - s.paid_amount), -- Hiển thị số tiền CÒN PHẢI TRẢ cho user dễ biết
                    'status', s.status
                ) ORDER BY s.status DESC
            )
        INTO v_type, v_current_remaining, v_details
        FROM group_payment_requests g
        JOIN session_costs_snapshot s ON s.id = ANY(g.snapshot_ids)
        JOIN members m ON m.id = s.member_id
        WHERE g.group_code = p_code;

        -- Bước 3: Tính xem đã trả được bao nhiêu cho cái Target đó
        -- Ví dụ: Target 30k. Thực tế còn nợ 30k -> Progress = 0
        -- User trả 10k -> Thực tế còn nợ 20k -> Progress = 30 - 20 = 10k.
        v_paid_progress := GREATEST(0, v_target_amount - v_current_remaining);

    ELSE
        RETURN jsonb_build_object('found', false);
    END IF;

    -- 3. Return Result
    IF v_type IS NULL THEN
        RETURN jsonb_build_object('found', false);
    END IF;

    RETURN jsonb_build_object(
        'found', true,
        'type', v_type,
        'code', p_code,
        'total', v_target_amount, -- Số tiền cần thanh toán cho QR này
        'paid', v_paid_progress,  -- Số tiền đã vào (tương ứng với QR này)
        'remaining', v_current_remaining, -- Số tiền còn thiếu
        'success', (v_current_remaining <= 1000), -- Cho phép sai số 1000đ
        'details', v_details
    );
END;
$function$

CREATE OR REPLACE FUNCTION public.check_session_completion()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_unpaid_count INT;
BEGIN
    -- Chỉ chạy khi trạng thái snapshot thay đổi thành 'paid'
    IF NEW.status = 'paid' THEN
        -- Đếm xem trong session này còn ai CHƯA paid không (trừ người vừa update xong)
        SELECT COUNT(*) INTO v_unpaid_count
        FROM session_costs_snapshot
        WHERE session_id = NEW.session_id 
          AND status != 'paid'
          AND id != NEW.id; -- Trừ bản ghi hiện tại ra cho chắc

        -- Nếu không còn ai nợ (count = 0) -> Update Session thành DONE
        IF v_unpaid_count = 0 THEN
            UPDATE sessions 
            SET status = 'done', updated_at = NOW()
            WHERE id = NEW.session_id AND status = 'waiting_for_payment';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$function$

CREATE OR REPLACE FUNCTION public.create_group_payment(p_snapshot_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_total NUMERIC := 0;
    v_code TEXT;
    v_fingerprint TEXT;
    v_sorted_ids UUID[];
    v_existing_group_code TEXT;
BEGIN
    -- 1. Tính tổng tiền hiện tại
    SELECT COALESCE(SUM(final_amount - paid_amount), 0)
    INTO v_total
    FROM session_costs_snapshot
    WHERE id = ANY(p_snapshot_ids);

    IF v_total <= 0 THEN
        RAISE EXCEPTION 'Số tiền thanh toán không hợp lệ (bằng 0 hoặc đã trả hết).';
    END IF;

    -- 2. Tạo "Vân tay" (Fingerprint) từ danh sách ID đã sắp xếp
    -- Sắp xếp để đảm bảo chọn [A, B] hay [B, A] đều ra cùng 1 mã
    SELECT array_agg(x ORDER BY x) INTO v_sorted_ids FROM unnest(p_snapshot_ids) x;
    v_fingerprint := md5(array_to_string(v_sorted_ids, ','));

    -- 3. CƠ CHẾ CHỐNG SPAM: Kiểm tra mã cũ còn hạn
    SELECT group_code INTO v_existing_group_code
    FROM group_payment_requests
    WHERE fingerprint = v_fingerprint 
      AND expires_at > now(); -- Chỉ lấy mã còn sống

    -- 4. Nếu tìm thấy mã cũ -> TÁI SỬ DỤNG (REUSE)
    IF v_existing_group_code IS NOT NULL THEN
        -- Cập nhật lại số tiền (đề phòng Admin vừa sửa giá thủ công)
        UPDATE group_payment_requests 
        SET total_amount = v_total 
        WHERE group_code = v_existing_group_code;

        -- Trả về mã cũ, KHÔNG TẠO DÒNG MỚI
        RETURN jsonb_build_object(
            'group_code', v_existing_group_code,
            'total_amount', v_total
        );
    END IF;

    -- 5. Nếu chưa có -> Mới tạo dòng mới
    v_code := 'GR' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
    v_code := upper(v_code);

    INSERT INTO group_payment_requests (
        group_code, 
        snapshot_ids, 
        total_amount, 
        fingerprint,
        expires_at
    )
    VALUES (
        v_code, 
        p_snapshot_ids, 
        v_total, 
        v_fingerprint,
        now() + interval '1 day' -- Mã tồn tại 1 ngày
    );

    RETURN jsonb_build_object(
        'group_code', v_code,
        'total_amount', v_total
    );
END;
$function$

CREATE OR REPLACE FUNCTION public.create_session_with_bookings(p_title text, p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_price_per_hour numeric, p_shuttle_fee numeric, p_created_by uuid, p_bookings jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_session_id UUID;
    v_interval_start TIMESTAMPTZ;
    v_interval_end TIMESTAMPTZ;
    v_idx INT := 0;
    v_booking_item JSONB;
BEGIN
    INSERT INTO sessions (
        title, start_time, end_time, price_per_hour, shuttle_fee_total, created_by, status
    )
    VALUES (
        p_title, p_start_time, p_end_time, p_price_per_hour, p_shuttle_fee, p_created_by, 'open'
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
            INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time)
            VALUES (
                v_session_id,
                COALESCE(v_booking_item->>'court_name', v_booking_item->>'name', 'Sân 1'),
                (v_booking_item->>'start_time')::TIMESTAMPTZ,
                (v_booking_item->>'end_time')::TIMESTAMPTZ
            );
        END LOOP;
    ELSE
        INSERT INTO session_court_bookings (session_id, start_time, end_time, court_name)
        VALUES (v_session_id, p_start_time, p_end_time, 'Sân 1 (Mặc định)');
    END IF;

    PERFORM refresh_interval_courts(v_session_id);

    RETURN v_session_id;
END;
$function$

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
BEGIN
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
            INSERT INTO session_court_bookings (session_id, court_name, start_time, end_time)
            VALUES (
                v_session_id,
                COALESCE(v_booking_item->>'court_name', v_booking_item->>'name', 'Sân 1'),
                (v_booking_item->>'start_time')::TIMESTAMPTZ,
                (v_booking_item->>'end_time')::TIMESTAMPTZ
            );
        END LOOP;
    ELSE
        INSERT INTO session_court_bookings (session_id, start_time, end_time, court_name)
        VALUES (v_session_id, p_start_time, p_end_time, 'Sân 1 (Mặc định)');
    END IF;

    PERFORM refresh_interval_courts(v_session_id);

    RETURN v_session_id;
END;
$function$

CREATE OR REPLACE FUNCTION public.finalize_session(p_session_id uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    r RECORD;
    v_payment_code TEXT;
BEGIN
    -- 1. Update Session Status
    UPDATE sessions 
    SET status = 'waiting_for_payment', updated_at = NOW()
    WHERE id = p_session_id;

    -- 2. Loop tính toán
    FOR r IN SELECT * FROM calculate_session_costs(p_session_id)
    LOOP
        IF r.final_total > 0 THEN -- Hoặc <> 0 nếu chấp nhận âm? Thường nợ âm thì host trả tiền mặt, ko tạo QR.
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
                extra_fee_amount = EXCLUDED.extra_fee_amount;
        END IF;
    END LOOP;
END;
$function$

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  INSERT INTO public.members (user_id, display_name, role, is_active)
  VALUES (
    new.id, -- Lấy ID từ bên Auth
    COALESCE(new.raw_user_meta_data->>'full_name', new.email), -- Lấy tên hoặc email làm tên hiển thị
    'member', -- Mặc định là member thường (Muốn admin thì sửa tay trong DB sau)
    true
  );
  RETURN new;
END;
$function$

CREATE OR REPLACE FUNCTION public.prevent_change_on_locked_session()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_session_id UUID;
    v_status TEXT; -- hoặc session_status
BEGIN
    -- 1. Tìm Session ID
    IF TG_TABLE_NAME = 'interval_presence' THEN
        SELECT si.session_id INTO v_session_id
        FROM session_intervals si
        WHERE si.id = COALESCE(NEW.interval_id, OLD.interval_id);
        
    ELSIF TG_TABLE_NAME = 'session_registrations' THEN
        v_session_id := COALESCE(NEW.session_id, OLD.session_id);
    END IF;

    -- 2. Kiểm tra trạng thái Session
    SELECT status::text INTO v_status FROM sessions WHERE id = v_session_id;

    IF v_status != 'open' THEN
        RAISE EXCEPTION 'Session đang khóa (Status: %). Không thể chỉnh sửa.', v_status;
    END IF;

    -- [QUAN TRỌNG] Logic Return chuẩn cho Trigger
    IF (TG_OP = 'DELETE') THEN
        RETURN OLD; -- Nếu xóa, phải trả về OLD
    END IF;
    
    RETURN NEW; -- Nếu thêm/sửa, trả về NEW
END;
$function$

CREATE OR REPLACE FUNCTION public.recreate_session_intervals(p_session_id uuid, p_start_time timestamp with time zone, p_end_time timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_interval_start TIMESTAMPTZ;
  v_interval_end   TIMESTAMPTZ;
  v_idx            INT := 0;
BEGIN
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
$function$

CREATE OR REPLACE FUNCTION public.refresh_interval_courts(p_session_id uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Update lại active_court_count cho từng interval thuộc session đó
    UPDATE session_intervals si
    SET active_court_count = (
        SELECT COUNT(*)
        FROM session_court_bookings b
        WHERE b.session_id = p_session_id
          -- Logic Overlap: Booking bắt đầu trước khi Interval kết thúc 
          -- VÀ Booking kết thúc sau khi Interval bắt đầu
          AND b.start_time < si.end_time
          AND b.end_time > si.start_time
    )
    WHERE si.session_id = p_session_id;
END;
$function$

CREATE OR REPLACE FUNCTION public.remove_member_from_session(p_session_id uuid, p_member_id uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status TEXT;
BEGIN
    -- 1. Kiểm tra trạng thái Session (Chỉ cho xóa khi OPEN)
    SELECT status::text INTO v_status FROM sessions WHERE id = p_session_id;
    
    IF v_status != 'open' THEN
        RAISE EXCEPTION 'Không thể xóa thành viên khi Session đang ở trạng thái "%". Vui lòng mở lại session trước.', v_status;
    END IF;

    -- 2. Xóa Extra Charges (Tiền nước/nợ riêng)
    DELETE FROM session_extra_charges 
    WHERE session_id = p_session_id AND member_id = p_member_id;

    -- 3. Xóa Interval Presence (Điểm danh)
    DELETE FROM interval_presence 
    WHERE member_id = p_member_id
      AND interval_id IN (
          SELECT id FROM session_intervals WHERE session_id = p_session_id
      );

    -- 4. Xóa Snapshot (Nếu đã lỡ tính toán tiền nong trước đó)
    -- Chỉ xóa nếu chưa thanh toán (status != 'paid') để an toàn
    DELETE FROM session_costs_snapshot 
    WHERE session_id = p_session_id AND member_id = p_member_id AND status != 'paid';

    -- 5. Cuối cùng: Xóa Registration
    DELETE FROM session_registrations 
    WHERE session_id = p_session_id AND member_id = p_member_id;

END;
$function$

CREATE OR REPLACE FUNCTION public.trigger_refresh_courts()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM refresh_interval_courts(COALESCE(NEW.session_id, OLD.session_id));
    RETURN NULL;
END;
$function$

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$

CREATE OR REPLACE FUNCTION public.get_session_delete_impact(p_session_id uuid)
 RETURNS TABLE(session_id uuid, registrations_count integer, intervals_count integer, presence_count integer, court_bookings_count integer, extra_charges_count integer, snapshots_count integer, payments_count integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        s.id,
        (
            SELECT count(*)::integer
            FROM public.session_registrations r
            WHERE r.session_id = s.id
        ) AS registrations_count,
        (
            SELECT count(*)::integer
            FROM public.session_intervals i
            WHERE i.session_id = s.id
        ) AS intervals_count,
        (
            SELECT count(*)::integer
            FROM public.interval_presence p
            JOIN public.session_intervals i ON i.id = p.interval_id
            WHERE i.session_id = s.id
        ) AS presence_count,
        (
            SELECT count(*)::integer
            FROM public.session_court_bookings b
            WHERE b.session_id = s.id
        ) AS court_bookings_count,
        (
            SELECT count(*)::integer
            FROM public.session_extra_charges ex
            WHERE ex.session_id = s.id
        ) AS extra_charges_count,
        (
            SELECT count(*)::integer
            FROM public.session_costs_snapshot sc
            WHERE sc.session_id = s.id
        ) AS snapshots_count,
        (
            SELECT count(*)::integer
            FROM public.session_payments sp
            JOIN public.session_costs_snapshot sc ON sc.id = sp.snapshot_id
            WHERE sc.session_id = s.id
        ) AS payments_count
    FROM public.sessions s
    WHERE s.id = p_session_id
        AND s.deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session not found or already deleted';
    END IF;
END;
$function$

CREATE OR REPLACE FUNCTION public.soft_delete_cancelled_session(p_session_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_deleted_at timestamp with time zone;
    v_impact RECORD;
BEGIN
    SELECT status::text, deleted_at
    INTO v_status, v_deleted_at
    FROM public.sessions
    WHERE id = p_session_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session not found';
    END IF;

    IF v_deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object(
            'session_id', p_session_id,
            'deleted', false,
            'message', 'already_deleted'
        );
    END IF;

    IF v_status <> 'cancelled' THEN
        RAISE EXCEPTION 'Only cancelled sessions can be deleted';
    END IF;

    SELECT * INTO v_impact
    FROM public.get_session_delete_impact(p_session_id)
    LIMIT 1;

    IF COALESCE(v_impact.payments_count, 0) > 0 THEN
        RAISE EXCEPTION 'Cancelled session still has payment records';
    END IF;

    -- Session-lock trigger only allows mutations while status='open'.
    UPDATE public.sessions
    SET status = 'open',
            updated_at = now()
    WHERE id = p_session_id;

    DELETE FROM public.interval_presence p
    USING public.session_intervals i
    WHERE p.interval_id = i.id
        AND i.session_id = p_session_id;

    DELETE FROM public.session_payments sp
    USING public.session_costs_snapshot sc
    WHERE sp.snapshot_id = sc.id
        AND sc.session_id = p_session_id;

    DELETE FROM public.session_costs_snapshot
    WHERE session_id = p_session_id;

    DELETE FROM public.session_extra_charges
    WHERE session_id = p_session_id;

    DELETE FROM public.session_registrations
    WHERE session_id = p_session_id;

    DELETE FROM public.session_court_bookings
    WHERE session_id = p_session_id;

    DELETE FROM public.session_intervals
    WHERE session_id = p_session_id;

    UPDATE public.sessions
        SET status = 'cancelled',
            deleted_at = now(),
            updated_at = now()
    WHERE id = p_session_id;

    RETURN jsonb_build_object(
        'session_id', p_session_id,
        'deleted', true,
        'registrations_count', COALESCE(v_impact.registrations_count, 0),
        'intervals_count', COALESCE(v_impact.intervals_count, 0),
        'presence_count', COALESCE(v_impact.presence_count, 0),
        'court_bookings_count', COALESCE(v_impact.court_bookings_count, 0),
        'extra_charges_count', COALESCE(v_impact.extra_charges_count, 0),
        'snapshots_count', COALESCE(v_impact.snapshots_count, 0),
        'payments_count', COALESCE(v_impact.payments_count, 0)
    );
END;
$function$

CREATE OR REPLACE FUNCTION public.soft_delete_cancelled_sessions_bulk(p_session_ids uuid[])
 RETURNS TABLE(session_id uuid, deleted boolean, message text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_session_id uuid;
BEGIN
    IF p_session_ids IS NULL OR array_length(p_session_ids, 1) IS NULL THEN
        RETURN;
    END IF;

    IF array_length(p_session_ids, 1) > 50 THEN
        RAISE EXCEPTION 'Bulk delete limit exceeded (max 50 sessions per request)';
    END IF;

    FOREACH v_session_id IN ARRAY p_session_ids LOOP
        BEGIN
            PERFORM public.soft_delete_cancelled_session(v_session_id);
            RETURN QUERY SELECT v_session_id, true, 'ok'::text;
        EXCEPTION WHEN OTHERS THEN
            RETURN QUERY SELECT v_session_id, false, SQLERRM;
        END;
    END LOOP;
END;
$function$

CREATE OR REPLACE FUNCTION public.gc_soft_deleted_sessions(p_older_than interval DEFAULT '30 days'::interval)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_session_id uuid;
    v_deleted_count integer := 0;
BEGIN
    FOR v_session_id IN
        SELECT s.id
        FROM public.sessions s
        WHERE s.deleted_at IS NOT NULL
            AND s.deleted_at < now() - p_older_than
    LOOP
        DELETE FROM public.interval_presence p
        USING public.session_intervals i
        WHERE p.interval_id = i.id
            AND i.session_id = v_session_id;

        DELETE FROM public.session_payments sp
        USING public.session_costs_snapshot sc
        WHERE sp.snapshot_id = sc.id
            AND sc.session_id = v_session_id;

        DELETE FROM public.session_costs_snapshot
        WHERE session_id = v_session_id;

        DELETE FROM public.session_extra_charges
        WHERE session_id = v_session_id;

        DELETE FROM public.session_registrations
        WHERE session_id = v_session_id;

        DELETE FROM public.session_court_bookings
        WHERE session_id = v_session_id;

        DELETE FROM public.session_intervals
        WHERE session_id = v_session_id;

        DELETE FROM public.sessions
        WHERE id = v_session_id
            AND deleted_at IS NOT NULL
            AND deleted_at < now() - p_older_than;

        v_deleted_count := v_deleted_count + 1;
    END LOOP;

    RETURN v_deleted_count;
END;
$function$

DO $do$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.unschedule(jobid)
        FROM cron.job
        WHERE jobname = 'gc_soft_deleted_sessions_daily';

        PERFORM cron.schedule(
            'gc_soft_deleted_sessions_daily',
            '0 3 * * *',
            $job$SELECT public.gc_soft_deleted_sessions(interval '30 days');$job$
        );
    END IF;
EXCEPTION WHEN OTHERS THEN
    -- Non-blocking when pg_cron is not available.
    NULL;
END;
$do$;
