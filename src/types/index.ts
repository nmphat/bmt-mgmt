export interface SessionSummary {
  id: string
  title: string
  status: 'draft' | 'active' | 'closed'
  session_date: string // ISO string
  court_fee_total: number
  shuttle_fee_total: number
  total_intervals: number
  total_registrations: number
}

export interface MemberCost {
  member_id: string
  display_name: string
  total_court_fee: number
  total_shuttle_fee: number
  final_total: number // Rounded amount
  intervals_count: number
}

export interface Interval {
  id: string
  start_time: string
  end_time: string
  idx: number
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
  // Join fields
  member?: { display_name: string }
}

// Table: session_payments
export interface SessionPayment {
  id: string
  amount: number
  transaction_id: string
  created_at: string
}

// Bank Config (Hardcode for now or fetch from DB)
export const BANK_INFO = {
  BANK_ID: 'MB', // Example: MB, VCB, ACB
  ACCOUNT_NO: '3030191957777',
  TEMPLATE: 'compact2',
}
