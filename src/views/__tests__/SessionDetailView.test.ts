import { describe, it, expect, vi, afterEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import SessionDetailView from '@/views/SessionDetailView.vue'
import SessionExtraCharges from '@/components/SessionExtraCharges.vue'
import { useAuthStore } from '@/stores/auth'

const TABLE_FIXTURES: Record<string, any> = {
  view_session_summary: {
    id: 'session-1',
    title: 'Buổi test',
    status: 'waiting_for_payment',
    session_date: '2026-09-14T11:00:00Z',
  },
  sessions: { shuttle_usage: [] },
  session_costs_snapshot: [
    {
      id: 'snap-1',
      session_id: 'session-1',
      member_id: 'm1',
      final_amount: 120000,
      paid_amount: 0,
      payment_code: 'CL000001',
      status: 'pending',
      court_fee_amount: 80000,
      shuttle_fee_amount: 40000,
      extra_fee_amount: 0,
      member: { display_name: 'Nguyễn Văn A' },
    },
  ],
}

function makeQueryBuilder(table: string) {
  const result = table in TABLE_FIXTURES ? TABLE_FIXTURES[table] : []
  const builder: any = {
    select: vi.fn(() => builder),
    eq: vi.fn(() => builder),
    order: vi.fn(() => builder),
    in: vi.fn(() => builder),
    single: vi.fn(() => builder),
    then: (resolve: any, reject: any) =>
      Promise.resolve({ data: result, error: null }).then(resolve, reject),
  }
  return builder
}

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn((table: string) => makeQueryBuilder(table)),
    rpc: vi.fn().mockResolvedValue({ data: [], error: null }),
    removeChannel: vi.fn(),
  },
}))

vi.mock('vue-router', async (importOriginal) => {
  const actual = await importOriginal<typeof import('vue-router')>()
  return {
    ...actual,
    useRoute: () => ({ params: { id: 'session-1' }, query: {}, name: 'session-detail' }),
    useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
  }
})

const STUBS = {
  PaymentQRModal: true,
  ManualPaymentModal: true,
  SessionExtraCharges: true,
  CourtBookingEditor: true,
  ShuttleUsageEditor: true,
}

let activeWrapper: ReturnType<typeof mount> | undefined

afterEach(() => activeWrapper?.unmount())

async function mountDetail(role: 'admin' | 'member' | 'guest') {
  setActivePinia(createPinia())
  const authStore = useAuthStore()
  if (role !== 'guest') {
    authStore.user = { id: 'u1' } as any
    authStore.profile = {
      id: 'u1',
      role: role === 'admin' ? 'admin' : 'member',
      display_name: 'Test User',
    }
  }
  const w = mount(SessionDetailView, { global: { stubs: STUBS } })
  activeWrapper = w
  await flushPromises()
  await flushPromises()
  return w
}

describe('SessionDetailView payment table admin gating', () => {
  it('hides admin selection controls and shows 8 header columns for a non-admin authenticated viewer', async () => {
    const w = await mountDetail('member')
    expect(w.findAll('input[type="checkbox"][value="snap-1"]')).toHaveLength(0)
    expect(w.findAll('#payments-section thead th')).toHaveLength(8)
    expect(w.find('#payments-section tbody tr:last-child td:first-child').attributes('colspan')).toBe('5')
    expect(w.findComponent(SessionExtraCharges).props('isAdmin')).toBe(false)
  })

  it('shows admin selection controls and 9 header columns for an admin', async () => {
    const w = await mountDetail('admin')
    expect(w.findAll('input[type="checkbox"][value="snap-1"]')).toHaveLength(2)
    expect(w.findAll('#payments-section thead th')).toHaveLength(9)
    expect(w.find('#payments-section tbody tr:last-child td:first-child').attributes('colspan')).toBe('6')
    expect(w.findComponent(SessionExtraCharges).props('isAdmin')).toBe(true)
  })

  it('lets a fully anonymous guest still see the payment amounts read-only', async () => {
    const w = await mountDetail('guest')
    expect(w.findAll('input[type="checkbox"][value="snap-1"]')).toHaveLength(0)
    expect(w.text()).toContain('Nguyễn Văn A')
    expect(w.text()).toContain('120.000')
  })

  it('shows the pending payment status badge with the danger token, not neutral gray', async () => {
    const w = await mountDetail('member')
    const pendingBadges = w.findAll('span').filter((span) => span.text() === 'Chưa đóng')
    expect(pendingBadges.length).toBeGreaterThan(0)
    for (const badge of pendingBadges) {
      expect(badge.classes()).toContain('bg-status-danger')
      expect(badge.classes()).toContain('text-status-danger-strong')
      expect(badge.classes()).not.toContain('bg-gray-100')
    }
  })
})
