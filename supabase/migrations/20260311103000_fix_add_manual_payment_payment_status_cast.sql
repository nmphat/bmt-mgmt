-- Fix add_manual_payment after migrating session_costs_snapshot.status to enum payment_status
-- Also harden manual-payment inserts with basic validation and note persistence.

CREATE OR REPLACE FUNCTION public.add_manual_payment(
  p_snapshot_id uuid,
  p_amount numeric,
  p_note text DEFAULT 'Tiền mặt'::text
)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
  v_final_amount numeric;
  v_current_paid numeric;
  v_new_paid numeric;
BEGIN
  IF p_snapshot_id IS NULL THEN
    RAISE EXCEPTION 'p_snapshot_id is required';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'p_amount must be > 0';
  END IF;

  SELECT final_amount, paid_amount
  INTO v_final_amount, v_current_paid
  FROM public.session_costs_snapshot
  WHERE id = p_snapshot_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Snapshot not found: %', p_snapshot_id;
  END IF;

  v_new_paid := COALESCE(v_current_paid, 0) + p_amount;

  INSERT INTO public.session_payments (
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

  UPDATE public.session_costs_snapshot
  SET
    paid_amount = v_new_paid,
    status = CASE
      WHEN v_new_paid >= v_final_amount THEN 'paid'::public.payment_status
      ELSE 'partial'::public.payment_status
    END
  WHERE id = p_snapshot_id;
END;
$function$;
