-- Mọi hàm trong schema public mà GHI vào bảng đều phải mang đủ bộ bảo vệ,
-- và cả bốn thuộc tính đều vô hình với mọi test khác: nếu bị gỡ, hàm vẫn
-- chạy đúng và toàn bộ bộ test vẫn xanh.
--   - prosecdef: SECURITY INVOKER thì hàm chạy bằng quyền người gọi và
--     toàn bộ phòng thủ tụt xuống còn một lớp RLS.
--   - proconfig: RESET search_path thì search_path của người gọi quyết định
--     hàm nào được gọi bên trong thân hàm.
--   - proacl: anon tới được EXECUTE bằng HAI đường độc lập -- grant mặc
--     định của PostgreSQL cho PUBLIC (ACL '=X/postgres') và ALTER DEFAULT
--     PRIVILEGES của Supabase cấp thẳng cho anon ('anon=X/postgres').
--     REVOKE thiếu một trong hai là no-op. Phải đọc proacl thô;
--     has_function_privilege() trả về true ở CẢ hai trường hợp (hỏng và
--     không hỏng) nên nó không phân biệt được.
--   - admin check: authenticated PHẢI giữ EXECUTE để ứng dụng gọi được,
--     nên thứ duy nhất chặn một thành viên đã đăng nhập là câu IF trong
--     thân hàm.
--
-- File này TRƯỚC ĐÂY quét một mảng SÁU tên gõ tay. Đó đúng là lý do hai
-- vòng làm việc về quyền vẫn bỏ sót add_member_to_session_full_presence và
-- batch_add_members_to_session: không ai nhớ thêm tên vào mảng. Nay nó liệt
-- kê ĐỘNG mọi hàm ghi bảng, với miễn trừ ghi rõ từng cái một ở dưới. Một
-- hàm ghi bảng mới, chưa được gia cố, làm file này ĐỎ mà không cần ai nhớ gì.
--
-- db-tests/drift-check.sql đọc đúng bốn thứ này trên production, nhưng
-- drift-check.sh là một lệnh chạy tay, không nằm trong run.sh.
BEGIN;

DO $$
DECLARE
  r RECORD;

  -- ── Miễn trừ, mỗi mục kèm lý do ──

  -- Không cần SECURITY DEFINER + search_path ghim.
  -- Họ soft-delete/gc: SECURITY INVOKER theo chủ ý, anon đã bị REVOKE, và
  -- không màn hình nào gọi (xem chú thích trong 09_grants.sql).
  -- gc_soft_deleted_sessions chạy bằng pg_cron.
  v_skip_secdef text[] := ARRAY[
    'soft_delete_cancelled_session',
    'soft_delete_cancelled_sessions_bulk',
    'gc_soft_deleted_sessions'
  ];

  -- Được phép cho anon EXECUTE.
  -- create_group_payment và check_qr_status là luồng khách vãng lai trả
  -- tiền từ trang chủ: người quét mã QR chưa đăng nhập bao giờ.
  v_skip_acl text[] := ARRAY[
    'create_group_payment',
    'check_qr_status'
  ];

  -- Không cần admin check trong thân hàm.
  -- create_group_payment / check_qr_status: khách vãng lai, xem trên.
  -- refresh_interval_courts: được gọi từ trigger_refresh_courts (SECURITY
  --   INVOKER) khi admin ghi thẳng vào session_court_bookings; một admin
  --   check ở đây sẽ làm hỏng chính trigger đó. Nó chỉ tính lại
  --   active_court_count / court_cost từ dữ liệu đã có, không nhận tiền
  --   từ người gọi.
  -- Họ soft-delete/gc: xem v_skip_secdef.
  v_skip_admin text[] := ARRAY[
    'create_group_payment',
    'check_qr_status',
    'refresh_interval_courts',
    'soft_delete_cancelled_session',
    'soft_delete_cancelled_sessions_bulk',
    'gc_soft_deleted_sessions'
  ];

  v_found int := 0;
BEGIN
  FOR r IN
    SELECT p.proname, p.prosecdef,
           coalesce(array_to_string(p.proconfig, ','), '-') AS cfg,
           coalesce(p.proacl::text, '-')                    AS acl,
           p.prosrc ~ 'Chỉ admin được thực hiện thao tác này' AS has_admin_check
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      -- Hàm do extension cài (pgcrypto, uuid-ossp, pg_trgm): không phải mã
      -- của dự án. Lọc bằng pg_depend chứ không bằng một danh sách tên gõ
      -- tay -- cài thêm extension không được làm file này đỏ.
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
      -- Ba helper chỉ có trong test bed.
      AND p.proname NOT IN ('assert_eq', 'assert_money_eq', 'assert_denied', 'login_as')
      -- Hàm trigger không gọi thẳng qua REST được (Postgres từ chối: "trigger
      -- functions can only be called as triggers"), nên quyền EXECUTE trên
      -- chúng không mở đường ghi nào. Lọc theo kiểu trả về, không theo tên.
      AND p.prorettype <> 'trigger'::regtype
      -- Thân hàm có ghi bảng không. UPDATE/INSERT INTO/DELETE FROM là ba
      -- câu duy nhất ghi được; 'updated_at' không khớp vì \M đòi hết từ.
      AND p.prosrc ~* '\m(insert\s+into|update|delete\s+from)\M'
    ORDER BY p.proname
  LOOP
    v_found := v_found + 1;

    IF NOT r.proname = ANY(v_skip_secdef) THEN
      IF NOT r.prosecdef THEN
        RAISE EXCEPTION 'FAIL %() writes a table but is SECURITY INVOKER, must be SECURITY DEFINER (or listed in v_skip_secdef with a reason)', r.proname;
      END IF;

      IF r.cfg <> 'search_path=public, pg_temp' THEN
        RAISE EXCEPTION 'FAIL %() writes a table but has search_path "%", must be "search_path=public, pg_temp"', r.proname, r.cfg;
      END IF;
    END IF;

    IF NOT r.proname = ANY(v_skip_acl) THEN
      IF r.acl = '-' THEN
        RAISE EXCEPTION 'FAIL %() has a NULL proacl — default privileges are back and PUBLIC can EXECUTE', r.proname;
      END IF;
      IF r.acl ~ '[{,]=X/' THEN
        RAISE EXCEPTION 'FAIL %() still grants EXECUTE to PUBLIC (acl %)', r.proname, r.acl;
      END IF;
      IF r.acl ~ '[{,]anon=' THEN
        RAISE EXCEPTION 'FAIL %() still grants EXECUTE to anon (acl %)', r.proname, r.acl;
      END IF;
    END IF;

    IF r.acl !~ '[{,]authenticated=X/' THEN
      RAISE EXCEPTION 'FAIL %() no longer grants EXECUTE to authenticated (acl %) — the app cannot call it', r.proname, r.acl;
    END IF;

    IF NOT r.proname = ANY(v_skip_admin) AND NOT r.has_admin_check THEN
      RAISE EXCEPTION 'FAIL %() writes a table with no admin check in its body — authenticated holds EXECUTE, so any signed-in member can call it (or list it in v_skip_admin with a reason)', r.proname;
    END IF;

    RAISE NOTICE 'ok   %() hardened', r.proname;
  END LOOP;

  -- Nếu điều kiện liệt kê ở trên hỏng (regex sai, lọc quá tay) thì vòng lặp
  -- chạy 0 lần và mọi assertion ở trên "đạt" trong im lặng. Con số này là
  -- thứ duy nhất phát hiện được điều đó. Sửa lên khi thêm hàm ghi bảng mới.
  IF v_found < 14 THEN
    RAISE EXCEPTION 'FAIL the sweep only found % table-writing functions — the enumeration itself is broken', v_found;
  END IF;
  RAISE NOTICE 'ok   swept % table-writing functions in public', v_found;
END $$;

ROLLBACK;
