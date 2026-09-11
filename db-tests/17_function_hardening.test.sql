-- Bốn hàm SECURITY DEFINER ghi tiền của nhánh này phải giữ nguyên ba thuộc
-- tính, và cả ba đều vô hình với mọi test khác: nếu bị gỡ, hàm vẫn chạy
-- đúng và toàn bộ bộ test vẫn xanh.
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
-- db-tests/drift-check.sql đọc đúng ba thứ này nhưng drift-check.sh là một
-- lệnh chạy tay, không nằm trong run.sh.
BEGIN;

DO $$
DECLARE
  r RECORD;
  v_names text[] := ARRAY['refresh_interval_courts','set_session_court_bookings',
                          'set_session_shuttle_usage','update_session_details'];
  v_found int := 0;
BEGIN
  FOR r IN
    SELECT p.proname, p.prosecdef,
           coalesce(array_to_string(p.proconfig, ','), '-') AS cfg,
           coalesce(p.proacl::text, '-')                    AS acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = ANY(v_names)
  LOOP
    v_found := v_found + 1;

    IF NOT r.prosecdef THEN
      RAISE EXCEPTION 'FAIL %() is SECURITY INVOKER, must be SECURITY DEFINER', r.proname;
    END IF;

    IF r.cfg <> 'search_path=public, pg_temp' THEN
      RAISE EXCEPTION 'FAIL %() has search_path "%", must be "search_path=public, pg_temp"', r.proname, r.cfg;
    END IF;

    IF r.acl = '-' THEN
      RAISE EXCEPTION 'FAIL %() has a NULL proacl — default privileges are back and PUBLIC can EXECUTE', r.proname;
    END IF;
    IF r.acl ~ '[{,]=X/' THEN
      RAISE EXCEPTION 'FAIL %() still grants EXECUTE to PUBLIC (acl %)', r.proname, r.acl;
    END IF;
    IF r.acl ~ '[{,]anon=' THEN
      RAISE EXCEPTION 'FAIL %() still grants EXECUTE to anon (acl %)', r.proname, r.acl;
    END IF;
    IF r.acl !~ '[{,]authenticated=X/' THEN
      RAISE EXCEPTION 'FAIL %() no longer grants EXECUTE to authenticated (acl %) — the app cannot call it', r.proname, r.acl;
    END IF;

    RAISE NOTICE 'ok   %() is SECURITY DEFINER, pinned search_path, no PUBLIC/anon EXECUTE', r.proname;
  END LOOP;

  -- Một hàm bị đổi tên hoặc biến mất phải làm đỏ, không được lặng lẽ bỏ qua.
  IF v_found <> array_length(v_names, 1) THEN
    RAISE EXCEPTION 'FAIL expected % hardened functions, found %', array_length(v_names, 1), v_found;
  END IF;
END $$;

ROLLBACK;
