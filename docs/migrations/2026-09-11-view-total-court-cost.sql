-- Migration: view_session_summary.total_court_cost dùng giá theo sân
--
-- ── ĐÃ BỊ THAY THẾ, VÀ ĐÂY LÀ LÝ DO FILE VẪN CÒN ─────────────────────────
-- Nội dung GỐC của file này là bản view tính theo TỪNG interval
-- (CASE WHEN si.court_cost > 0 THEN si.court_cost ELSE acc * price/2 END).
-- 2026-09-11-court-pricing-guards.sql thay nó bằng bản chốt mô hình giá MỘT
-- LẦN cho cả buổi -- và sắp theo tên file, 'court-pricing-guards' đứng TRƯỚC
-- 'view-total-court-cost'. Một người chạy lại cả thư mục theo thứ tự tên file
-- vì thế áp bản cũ SAU bản mới và lặng lẽ hoàn tác lại bản sửa tiền: dựng lại
-- được trong container, db-tests/11_calc_with_court_cost.test.sql đỏ với
-- "expected 60000, got 110000".
--
-- Cách chữa không phải là đọc kỹ hơn hay nhớ thứ tự. Thân file này đã được
-- thay bằng ĐÚNG định nghĩa hiện hành trong docs/sql-export/05_views.sql, nên
-- chạy nó ở bất kỳ vị trí nào, bao nhiêu lần cũng được, trước hay sau
-- court-pricing-guards, đều cho ra cùng một view đúng. Không còn gì cũ trong
-- file để hoàn tác. Nội dung gốc nằm trong git history
-- (43674cc:docs/migrations/2026-09-11-view-total-court-cost.sql).
--
-- db-tests/drift-check.sql nay có truy vấn pg_get_viewdef, nên một production
-- còn đang chạy bản per-interval hiện ra trong diff thay vì diff sạch.
-- ────────────────────────────────────────────────────────────────────────
--
-- Trạng thái: ĐÃ ÁP LÊN PRODUCTION (và sau đó court-pricing-guards ghi đè
-- bằng bản đúng). Chạy lại là no-op.

BEGIN;

SET LOCAL lock_timeout = '5s';

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

COMMIT;

-- Kiểm tra sau khi chạy: phải trả về 'session-level' ở mọi thứ tự chạy.
-- SELECT CASE WHEN pg_get_viewdef('public.view_session_summary'::regclass)
--               ~ 'si.court_cost > ' THEN 'per-interval (SAI)'
--             ELSE 'session-level (đúng)' END;

-- Rollback: không có. CREATE OR REPLACE là idempotent và định nghĩa này
-- chính là định nghĩa hiện hành của docs/sql-export/05_views.sql.
