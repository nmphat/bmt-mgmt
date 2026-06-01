CREATE OR REPLACE VIEW public.view_attendance_log AS  SELECT s.title AS session_name,
    m.display_name AS member_name,
    i.idx AS interval_index,
    i.start_time AS interval_time,
    p.is_present,
    p.id AS presence_id,
    p.member_id,
    p.interval_id
   FROM (((interval_presence p
     JOIN session_intervals i ON ((i.id = p.interval_id)))
     JOIN sessions s ON ((s.id = i.session_id)))
               JOIN members m ON ((m.id = p.member_id)))
       WHERE (s.deleted_at IS NULL);

CREATE OR REPLACE VIEW public.view_member_debt_summary AS  SELECT m.id AS member_id,
    m.display_name,
    m.user_id AS auth_user_id,
    count(scs.id) AS unpaid_session_count,
    sum((scs.final_amount - scs.paid_amount)) AS total_debt
       FROM ((session_costs_snapshot scs
         JOIN members m ON ((m.id = scs.member_id)))
         JOIN sessions s ON ((s.id = scs.session_id)))
  WHERE ((scs.status <> 'paid'::payment_status) AND (s.deleted_at IS NULL))
  GROUP BY m.id, m.display_name, m.user_id
 HAVING (sum((scs.final_amount - scs.paid_amount)) > (0)::numeric);

CREATE OR REPLACE VIEW public.view_member_session_details AS  SELECT scs.id AS snapshot_id,
    scs.member_id,
    scs.session_id,
    s.title AS session_title,
    s.start_time,
    (s.start_time)::date AS session_date,
    scs.final_amount,
    scs.court_fee_amount,
    scs.shuttle_fee_amount,
    scs.extra_fee_amount,
    scs.paid_amount,
    (scs.final_amount - scs.paid_amount) AS remaining_amount,
    scs.status,
    scs.payment_code,
    scs.created_at
        FROM (session_costs_snapshot scs
               JOIN sessions s ON ((s.id = scs.session_id)))
       WHERE (s.deleted_at IS NULL);

CREATE OR REPLACE VIEW public.view_session_summary AS  SELECT id,
    title,
    start_time,
    end_time,
    (start_time)::date AS session_date,
    status,
    price_per_hour,
    default_court_count,
    COALESCE(court_fee_addon, (0)::numeric) AS court_fee_addon,
    (COALESCE(( SELECT sum(((si.active_court_count)::numeric * (s.price_per_hour / (2)::numeric))) AS sum
           FROM session_intervals si
          WHERE (si.session_id = s.id)), (0)::numeric) + COALESCE(court_fee_addon, (0)::numeric)) AS total_court_cost,
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
