-- Bộ kiểm chứng cho 2026-09-09-phase0-security.sql
-- Thuần đọc: không CREATE, DROP, UPDATE, INSERT, hay SET nào tồn tại quá
-- phiên chạy. An toàn để dán và chạy lại nhiều lần, cả trước lẫn sau
-- migration -- dùng để so hai lần chạy với nhau.

-- 1. Ai còn gọi được các RPC ghi tiền?
-- Kỳ vọng SAU migration: add_manual_payment, finalize_session,
-- remove_member_from_session -> anon = false, authenticated = true;
-- create_group_payment, check_qr_status -> anon = true, authenticated = true;
-- handle_new_user -> anon = false, authenticated = false.
SELECT p.proname,
       has_function_privilege('anon', p.oid, 'execute')          AS anon,
       has_function_privilege('authenticated', p.oid, 'execute') AS authenticated,
       p.prosecdef                                               AS security_definer,
       coalesce(array_to_string(p.proconfig, ','), '-')          AS config
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('add_manual_payment','finalize_session','remove_member_from_session',
                    'create_group_payment','check_qr_status','handle_new_user')
ORDER BY p.proname;

-- 2. Hai policy mở toàn quyền còn không?
-- Kỳ vọng SAU migration: 0 dòng.
SELECT tablename, policyname FROM pg_policies
WHERE schemaname = 'public' AND policyname = 'Public Access';

-- 3. Số liệu tiền -- phải không đổi qua migration.
-- Kỳ vọng SAU migration: giống hệt lần chạy TRƯỚC migration, không lệch
-- một đồng nào -- migration này không chạm vào dữ liệu.
SELECT count(*) AS snapshots,
       sum(paid_amount) AS total_paid,
       sum(final_amount) AS total_final,
       count(*) FILTER (WHERE status = 'paid') AS paid_rows,
       count(*) FILTER (WHERE status = 'partial') AS partial_rows,
       count(*) FILTER (WHERE status = 'pending') AS pending_rows
FROM session_costs_snapshot;

-- 4. ACL thô cạnh has_function_privilege, để thấy VÌ SAO quyền còn hay mất
-- chứ không chỉ việc nó còn hay mất. Trên Supabase, anon có thể có EXECUTE
-- qua hai đường độc lập: PostgreSQL cấp mặc định cho PUBLIC (hiện trong
-- proacl dạng "=X/postgres") và Supabase tự cấp thẳng cho anon (dạng
-- "anon=X/postgres"). Revoke thiếu một trong hai đường thì
-- has_function_privilege vẫn trả về true dù trông như đã revoke.
-- Kỳ vọng SAU migration: proacl của ba RPC admin không còn "anon=X..." lẫn
-- "=X..." cho quyền execute; handle_new_user tương tự không còn cho cả
-- anon lẫn authenticated.
SELECT p.proname,
       p.proacl,
       has_function_privilege('anon', p.oid, 'execute')          AS anon_can_execute,
       has_function_privilege('authenticated', p.oid, 'execute') AS authenticated_can_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('add_manual_payment','finalize_session','remove_member_from_session',
                    'create_group_payment','check_qr_status','handle_new_user')
ORDER BY p.proname;

-- 5. Còn sót hàm dò tạm nào của phase 0 không?
-- Kỳ vọng LUÔN LUÔN: 0 -- kể cả trước, giữa, và sau migration, trừ đúng
-- khoảnh khắc ai đó đang giữa bước tạo _phase0_verify_guard() để kiểm hành
-- vi. Một probe SECURITY DEFINER còn sót trên production tự nó là một lỗ
-- hổng.
SELECT count(*) AS leftover_phase0_probes
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname LIKE '_phase0%';
