-- Phase 0 -- security lockdown + two money bugs
-- Run once, as the postgres/owner role, in the Supabase SQL editor.
-- Everything is inside one transaction: a failure rolls the whole thing back.

BEGIN;

-- 1. Functions first, so the writes they perform keep working once the
--    permissive policies come off in step 3. Bodies below are copied
--    verbatim from docs/sql-export/06_functions.sql at HEAD -- do not
--    retype or reformat them; if this ever needs to change, edit the
--    export first and re-copy.

CREATE OR REPLACE FUNCTION public.add_manual_payment(p_snapshot_id uuid, p_amount numeric, p_note text DEFAULT 'Tiền mặt'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_final_amount NUMERIC;
    v_current_paid NUMERIC;
    v_new_paid NUMERIC;
BEGIN
    -- Function runs as its owner, so it must check the caller itself.
    IF NOT EXISTS (
        SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Chỉ admin được thực hiện thao tác này';
    END IF;

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

CREATE OR REPLACE FUNCTION public.finalize_session(p_session_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    r RECORD;
    v_payment_code TEXT;
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
END;
$function$;

CREATE OR REPLACE FUNCTION public.remove_member_from_session(p_session_id uuid, p_member_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_status TEXT;
BEGIN
    -- Function runs as its owner, so it must check the caller itself.
    IF NOT EXISTS (
        SELECT 1 FROM members WHERE user_id = auth.uid() AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Chỉ admin được thực hiện thao tác này';
    END IF;

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
$function$;

CREATE OR REPLACE FUNCTION public.create_group_payment(p_snapshot_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
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
$function$;

CREATE OR REPLACE FUNCTION public.health()
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path = public, pg_temp
AS $function$
  select 1;
$function$;

-- 2. Function grants. Copied verbatim from docs/sql-export/09_grants.sql
--    at HEAD. This is the corrected form: anon reaches EXECUTE on a new
--    function through two independent grants (PostgreSQL's default grant
--    to PUBLIC, and Supabase's own ALTER DEFAULT PRIVILEGES grant direct
--    to anon), so both PUBLIC and anon must be revoked or the other one
--    silently keeps anon in.

-- Function-level grants. Supabase exposes every function in the public
-- schema through /rest/v1/rpc, so anything that writes money must be
-- explicitly revoked from anon.
--
-- anon reaches EXECUTE on a newly created function through two independent
-- grants, and both must be revoked or the other one silently keeps anon in:
--   - PostgreSQL grants EXECUTE to PUBLIC on every function by default, and
--     anon is implicitly a member of PUBLIC, so `REVOKE ... FROM anon`
--     alone is a no-op — anon still gets in through PUBLIC.
--   - Supabase's own ALTER DEFAULT PRIVILEGES also grants EXECUTE directly
--     to anon (and authenticated, service_role) on every new function in
--     this schema, so `REVOKE ... FROM PUBLIC` alone is also a no-op here —
--     anon still gets in through its own direct grant.
-- A `DROP` followed by `CREATE` on any of these three functions re-applies
-- Supabase's default privileges from scratch and silently restores anon's
-- access; `CREATE OR REPLACE` preserves the existing ACL and is safe.
-- Whoever recreates one of these functions with DROP/CREATE must re-run
-- this file afterward.

REVOKE EXECUTE ON FUNCTION public.add_manual_payment(uuid, numeric, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.finalize_session(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.remove_member_from_session(uuid, uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.add_manual_payment(uuid, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_session(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_member_from_session(uuid, uuid) TO authenticated;

-- create_group_payment stays callable by anon: guests pay from the home page.
GRANT EXECUTE ON FUNCTION public.create_group_payment(uuid[]) TO anon, authenticated;

-- Read-only, safe for guests.
GRANT EXECUTE ON FUNCTION public.check_qr_status(text) TO anon, authenticated;

-- Trigger function; nothing should call it over the REST API.
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

-- 3. Close the holes: drop the permissive policies that let anon read
--    and write the money tables directly. bank_config's other policies
--    (bank_config_public_read plus the three bank_config_admin_* policies)
--    already match production and are left untouched here -- only
--    "Public Access" is a stray leftover policy being removed.
DROP POLICY IF EXISTS "Public Access" ON public.session_costs_snapshot;
DROP POLICY IF EXISTS "Public Access" ON public.session_payments;
DROP POLICY IF EXISTS "Public Access" ON public.bank_config;

-- 4. Leftover from another project (a tournament app). It reads teams,
--    team_members, registrations, user_profiles, user_quiz_scores,
--    draft_snapshots and audit_log, none of which exist in this schema,
--    so it could never have executed successfully here.
DROP FUNCTION IF EXISTS public.rpc_generate_draft(uuid, integer, text);

COMMIT;
