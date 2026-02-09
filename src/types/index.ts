export interface SessionSummary {
  id: string;
  title: string;
  status: 'draft' | 'active' | 'closed';
  session_date: string; // ISO string
  court_fee_total: number;
  shuttle_fee_total: number;
  total_intervals: number;
  total_registrations: number;
}

export interface MemberCost {
  member_id: string;
  display_name: string;
  total_court_fee: number;
  total_shuttle_fee: number;
  final_total: number; // Rounded amount
  intervals_count: number;
}

export interface Interval {
  id: string;
  start_time: string;
  end_time: string;
  idx: number;
}

export interface Member {
  id: string;
  display_name: string;
  role: 'admin' | 'member';
  is_active: boolean;
  is_permanent: boolean;
}

export interface SessionRegistration {
  id: string;
  session_id: string;
  member_id: string;
  is_registered_not_attended: boolean;
  member?: Member;
}

export interface IntervalPresence {
  id: string;
  interval_id: string;
  member_id: string;
  is_present: boolean;
}
