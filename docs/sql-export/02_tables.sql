CREATE TABLE IF NOT EXISTS public.bank_config (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  bank_id text NOT NULL,
  account_number text NOT NULL,
  account_name text NOT NULL,
  template text DEFAULT 'compact'::text,
  is_active boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.group_payment_requests (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  group_code text NOT NULL,
  snapshot_ids uuid[] NOT NULL,
  total_amount numeric NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  expires_at timestamp with time zone DEFAULT (now() + '1 day'::interval),
  fingerprint text
);

CREATE TABLE IF NOT EXISTS public.members (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid,
  display_name text NOT NULL,
  role user_role DEFAULT 'member'::user_role,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sessions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  title text NOT NULL,
  start_time timestamp with time zone NOT NULL,
  end_time timestamp with time zone NOT NULL,
  court_fee_addon numeric DEFAULT 0,
  shuttle_fee_total numeric DEFAULT 0,
  status session_status DEFAULT 'open'::session_status,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  price_per_hour numeric DEFAULT 0,
  default_court_count integer DEFAULT 1,
  deleted_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.session_intervals (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  session_id uuid,
  start_time timestamp with time zone NOT NULL,
  end_time timestamp with time zone NOT NULL,
  idx integer NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  active_court_count integer DEFAULT 1
);

CREATE TABLE IF NOT EXISTS public.session_registrations (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  session_id uuid,
  member_id uuid,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.interval_presence (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  interval_id uuid,
  member_id uuid,
  is_present boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.session_costs_snapshot (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  session_id uuid,
  member_id uuid,
  final_amount numeric NOT NULL,
  payment_code text,
  paid_amount numeric DEFAULT 0,
  status payment_status DEFAULT 'pending'::payment_status,
  created_at timestamp with time zone DEFAULT now(),
  court_fee_amount numeric DEFAULT 0,
  shuttle_fee_amount numeric DEFAULT 0,
  extra_fee_amount numeric DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.session_payments (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  snapshot_id uuid,
  amount numeric NOT NULL,
  transaction_id text,
  raw_content text,
  created_at timestamp with time zone DEFAULT now(),
  payment_method text DEFAULT 'transfer'::text,
  note text
);

CREATE TABLE IF NOT EXISTS public.session_court_bookings (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  session_id uuid,
  court_name text,
  start_time timestamp with time zone NOT NULL,
  end_time timestamp with time zone NOT NULL,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.session_extra_charges (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  session_id uuid,
  member_id uuid,
  amount numeric NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now()
);
