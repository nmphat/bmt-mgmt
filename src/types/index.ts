export interface SessionSummary {
  id: string
  title: string
  status: 'open' | 'waiting_for_payment' | 'done' | 'cancelled'
  start_time: string // ISO UTC timestamp
  end_time: string // ISO UTC timestamp
  session_date: string // ISO string
  court_fee_total: number
  court_fee_addon: number
  total_court_cost: number
  shuttle_fee_total: number
  price_per_hour: number
  default_court_count: number
  total_intervals: number
  total_registrations: number
  total_collected: number
}

export interface MemberCost {
  member_id: string
  display_name: string
  total_court_fee: number
  total_shuttle_fee: number
  total_extra_fee: number
  final_total: number // Rounded amount
  intervals_count: number
}

// View: view_member_debt_summary
export interface MemberDebtSummary {
  member_id: string
  display_name: string
  total_debt: number
  unpaid_session_count: number
}

// View: view_member_session_details
export interface MemberSessionDetail {
  snapshot_id: string
  session_id: string
  session_title: string
  start_time: string
  final_amount: number
  paid_amount: number
  remaining_amount: number // Calculated or from view
  court_fee_amount: number
  shuttle_fee_amount: number
  status: 'paid' | 'partial' | 'pending'
  payment_code: string
}

export interface Interval {
  id: string
  start_time: string
  end_time: string
  idx: number
  active_court_count: number
}

export interface Member {
  id: string
  display_name: string
  role: 'admin' | 'member'
  is_active: boolean
  is_permanent: boolean
}

export interface SessionRegistration {
  id: string
  session_id: string
  member_id: string
  is_registered_not_attended: boolean
  member?: Member
}

export interface IntervalPresence {
  id: string
  interval_id: string
  member_id: string
  is_present: boolean
}

// Table: session_costs_snapshot
export interface CostSnapshot {
  id: string
  session_id: string
  member_id: string
  final_amount: number // The fixed cost
  paid_amount: number // Amount paid so far
  payment_code: string // Unique code (e.g., "CL8F3A21")
  status: 'pending' | 'partial' | 'paid'
  court_fee_amount: number
  shuttle_fee_amount: number
  extra_fee_amount: number
  // Join fields
  member?: { display_name: string }
}

// Table: session_court_bookings
export interface CourtBooking {
  id: string
  session_id: string
  court_name: string
  start_time: string
  end_time: string
  created_at: string
}

// Table: session_extra_charges
export interface ExtraCharge {
  id: string
  session_id: string
  member_id: string
  amount: number
  note: string
  created_at: string
  member?: { display_name: string }
}

// Table: session_payments
export interface SessionPayment {
  id: string
  amount: number
  transaction_id: string
  created_at: string
}

export interface GroupPaymentData {
  group_code: string
  total_amount: number
  snapshot_ids?: string[]
  member_count?: number
  members?: {
    name: string
    amount: number
  }[]
}

export interface BankConfig {
  id: string
  bank_id: string
  account_number: string
  account_name: string
  template: string
  is_active: boolean
}

export type BankConfigInput = Omit<BankConfig, 'id'>

export const DEFAULT_BANK_CONFIG: BankConfigInput = {
  bank_id: 'TPB',
  account_number: '10003392871',
  account_name: 'CLB CAU LONG BMT',
  template: 'compact2',
  is_active: true,
}

// Fallback for QR rendering before the DB-backed config finishes loading.
export const BANK_INFO = {
  BANK_ID: DEFAULT_BANK_CONFIG.bank_id,
  BANK_NAME: 'TPBank',
  ACCOUNT_NO: DEFAULT_BANK_CONFIG.account_number,
  ACCOUNT_NAME: DEFAULT_BANK_CONFIG.account_name,
  TEMPLATE: DEFAULT_BANK_CONFIG.template,
}
