import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import SessionDetailView from '@/views/SessionDetailView.vue'
import SessionExtraCharges from '@/components/SessionExtraCharges.vue'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { supabase } from '@/lib/supabase'
import source from '@/views/SessionDetailView.vue?raw'

const BASE_FIXTURES: Record<string, any> = {
  view_session_summary: {
    id: 'session-1',
    title: 'Buổi test',
    status: 'waiting_for_payment',
    session_date: '2026-09-14T11:00:00Z',
    start_time: '2026-09-14T11:00:00Z',
    end_time: '2026-09-14T13:00:00Z',
    price_per_hour: 100000,
    court_fee_addon: 0,
    court_fee_total: 200000,
    shuttle_fee_total: 50000,
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

// Per-test state: fixtures by table, forced errors by table, the recorded query calls and the toast spy.
const h = vi.hoisted(() => ({
  fixtures: {} as Record<string, any>,
  errors: {} as Record<string, any>,
  pending: new Set<string>(),
  upsertError: null as any,
  calls: [] as { table: string; m: string; args: any[] }[],
  toast: { error: vi.fn(), success: vi.fn(), info: vi.fn() },
}))

function makeQueryBuilder(table: string) {
  const result = table in h.fixtures ? h.fixtures[table] : []
  let isUpsert = false
  const builder: any = {}
  for (const m of ['select', 'eq', 'order', 'in', 'single', 'update', 'upsert', 'delete']) {
    builder[m] = vi.fn((...args: any[]) => {
      h.calls.push({ table, m, args })
      if (m === 'upsert') isUpsert = true
      return builder
    })
  }
  builder.then = (resolve: any, reject: any) => {
    if (h.pending.has(table)) return new Promise(() => {}).then(resolve, reject)
    const error = (isUpsert && h.upsertError) || h.errors[table] || null
    return Promise.resolve({ data: error ? null : result, error }).then(resolve, reject)
  }
  return builder
}

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn((table: string) => makeQueryBuilder(table)),
    rpc: vi.fn(),
    removeChannel: vi.fn(),
    channel: vi.fn(() => {
      const channel: any = { on: vi.fn(() => channel), subscribe: vi.fn(() => channel) }
      return channel
    }),
  },
}))
vi.mock('vue-toastification', () => ({ useToast: () => h.toast }))

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
const t = (key: string, args?: Record<string, any>) => useLangStore().t(key, args)

beforeEach(() => {
  h.fixtures = structuredClone(BASE_FIXTURES)
  h.errors = {}
  h.pending.clear()
  h.upsertError = null
  h.calls = []
  h.toast.error.mockClear()
  h.toast.success.mockClear()
  vi.mocked(supabase.rpc)
    .mockReset()
    .mockResolvedValue({ data: [], error: null } as any)
})

afterEach(() => {
  activeWrapper?.unmount()
  vi.restoreAllMocks()
})

// Overrides the summary row and any table fixture before mounting.
function withSession(summary: Record<string, any> = {}, tables: Record<string, any> = {}) {
  h.fixtures.view_session_summary = { ...h.fixtures.view_session_summary, ...summary }
  Object.assign(h.fixtures, tables)
}

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

// ---- S6: overview, edit form and attendance ----

const iv = (id: string, from: string, to: string) => ({
  id,
  session_id: 'session-1',
  idx: 0,
  start_time: `2026-09-14T${from}:00Z`,
  end_time: `2026-09-14T${to}:00Z`,
})
const member = (id: string, display_name: string) => ({
  id,
  display_name,
  role: 'member',
  is_active: true,
})
// m1 is registered and present in i2 only; m2 is registered and absent; m3 and m4 are still available.
const ATTENDANCE_TABLES = {
  session_intervals: [iv('i1', '11:00', '12:00'), iv('i2', '12:00', '13:00')],
  members: [member('m1', 'An'), member('m2', 'Binh'), member('m3', 'Chi'), member('m4', 'Dung')],
  session_registrations: [
    { id: 'r1', session_id: 'session-1', member_id: 'm1', member: member('m1', 'An') },
    { id: 'r2', session_id: 'session-1', member_id: 'm2', member: member('m2', 'Binh') },
  ],
  interval_presence: [{ interval_id: 'i2', member_id: 'm1', is_present: true }],
}
const openAttendance = () => withSession({ status: 'open' }, ATTENDANCE_TABLES)

const button = (w: ReturnType<typeof mount>, label: string) =>
  w.findAll('button').find((b) => b.text() === label)!
const overview = (w: ReturnType<typeof mount>) => w.get('#overview-section')
const cards = (w: ReturnType<typeof mount>) => w.findAll('[data-ds="Registration Card"]')
const rows = (w: ReturnType<typeof mount>) => w.findAll('tr[data-ds="Attendance Row"]')
const PALETTE_CLASS =
  /(?:^|[^a-z-])((?:bg|text|border|ring|divide|from|via|to|outline|fill|stroke|placeholder|decoration|accent|caret)-(?:gray|red|green|amber|blue|emerald|brand|slate|zinc|neutral|stone|orange|yellow|lime|teal|cyan|sky|indigo|violet|purple|fuchsia|pink|rose)-\d+)/g
const upserts = () => h.calls.filter((c) => c.m === 'upsert')

describe('SessionDetailView page states', () => {
  it('shows the 48 Spinner while the session is loading', async () => {
    h.pending.add('view_session_summary')
    const w = await mountDetail('admin')
    const spinner = w.get('[data-ds="Spinner"]')
    expect(spinner.attributes('data-ds-size')).toBe('48')
    expect(spinner.attributes('role')).toBe('status')
  })

  it('shows an Alert Danger with a refresh Button when the summary query fails, and refetches', async () => {
    h.errors.view_session_summary = { message: 'boom' }
    const w = await mountDetail('admin')
    const alert = w.get('[data-ds="Alert"]')
    expect(alert.attributes('data-ds-tone')).toBe('Danger')
    expect(alert.attributes('role')).toBe('alert')
    expect(alert.attributes('aria-live')).toBe('polite')
    expect(alert.text()).toContain(t('session.dataLoadError'))
    const refresh = alert.get('[data-ds="Button"]')
    expect(refresh.attributes('data-ds-style')).toBe('Outline Danger')
    expect(refresh.attributes('data-ds-size')).toBe('Default')
    expect(refresh.text()).toBe(t('session.refreshSession'))
    const before = h.calls.filter((c) => c.table === 'view_session_summary' && c.m === 'single')
    await refresh.trigger('click')
    await flushPromises()
    const after = h.calls.filter((c) => c.table === 'view_session_summary' && c.m === 'single')
    expect(after.length).toBe(before.length + 1)
  })
})

describe('SessionDetailView overview', () => {
  it.each([
    ['open', 'Open'],
    ['waiting_for_payment', 'Waiting For Payment'],
    ['done', 'Done'],
    ['cancelled', 'Cancelled'],
    ['archived', 'Cancelled'],
  ])('status %s renders Session Status Badge %s', async (status, expected) => {
    withSession({ status })
    const w = await mountDetail('member')
    expect(overview(w).get('[data-ds="Session Status Badge"]').attributes('data-ds-status')).toBe(
      expected,
    )
  })

  it('shows 2 Neutral Stat Tiles while open, plus a Brand tile once waiting for payment', async () => {
    withSession({ status: 'open' })
    let w = await mountDetail('member')
    let tiles = overview(w).findAll('[data-ds="Stat Tile"]')
    expect(tiles.map((x) => x.attributes('data-ds-tone'))).toEqual(['Neutral', 'Neutral'])
    w.unmount()

    withSession({ status: 'waiting_for_payment' })
    w = await mountDetail('member')
    tiles = overview(w).findAll('[data-ds="Stat Tile"]')
    expect(tiles.map((x) => x.attributes('data-ds-tone'))).toEqual(['Neutral', 'Neutral', 'Brand'])
    expect(tiles[2]!.text()).toContain(t('session.totalCollected'))
  })

  it('shows the read-only hint to a guest in an Alert Neutral Box', async () => {
    withSession({ status: 'open' })
    const w = await mountDetail('guest')
    const alert = overview(w).get('[data-ds="Alert"]')
    expect(alert.attributes('data-ds-tone')).toBe('Neutral')
    expect(alert.attributes('data-ds-style')).toBe('Box')
    expect(alert.text()).toBe(t('session.readOnlyHint'))
  })

  it('gives an admin of an open session the edit, cancel and finalize actions', async () => {
    withSession({ status: 'open' })
    const w = await mountDetail('admin')
    const edit = overview(w).get(`button[aria-label="${t('session.editSession')}"]`)
    expect(edit.attributes('data-ds')).toBe('Icon Button')
    const cancel = button(overview(w) as any, t('session.cancelSession'))
    expect(cancel.attributes('data-ds-style')).toBe('Secondary')
    expect(cancel.text()).not.toContain('🚫')
    const finalize = button(overview(w) as any, t('session.finalize'))
    expect(finalize.attributes('data-ds-style')).toBe('Primary')
    expect(finalize.find('svg[class*="lucide-lock"]').exists()).toBe(true)
  })

  it('hides the admin actions when the session is not editable', async () => {
    withSession({ status: 'open' })
    const w = await mountDetail('member')
    expect(button(overview(w) as any, t('session.finalize'))).toBeUndefined()
    expect(
      overview(w)
        .find(`button[aria-label="${t('session.editSession')}"]`)
        .exists(),
    ).toBe(false)
  })

  it('finalizes through the rpc after confirm, and does nothing when confirm is refused', async () => {
    withSession({ status: 'open' })
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false)
    const w = await mountDetail('admin')
    await button(w, t('session.finalize')).trigger('click')
    await flushPromises()
    expect(supabase.rpc).not.toHaveBeenCalledWith('finalize_session', expect.anything())
    confirm.mockReturnValue(true)
    await button(w, t('session.finalize')).trigger('click')
    await flushPromises()
    expect(supabase.rpc).toHaveBeenCalledWith('finalize_session', { p_session_id: 'session-1' })
  })

  it('cancels through sessions.update after confirm, and does nothing when confirm is refused', async () => {
    withSession({ status: 'open' })
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false)
    const w = await mountDetail('admin')
    await button(w, t('session.cancelSession')).trigger('click')
    await flushPromises()
    expect(h.calls.filter((c) => c.m === 'update')).toHaveLength(0)
    confirm.mockReturnValue(true)
    await button(w, t('session.cancelSession')).trigger('click')
    await flushPromises()
    const update = h.calls.findIndex((c) => c.m === 'update')
    expect(h.calls[update]).toEqual({
      table: 'sessions',
      m: 'update',
      args: [{ status: 'cancelled' }],
    })
    expect(h.calls[update + 1]).toEqual({ table: 'sessions', m: 'eq', args: ['id', 'session-1'] })
  })

  it('shows the cancelled banner as an Alert Neutral Banner with an X icon', async () => {
    withSession({ status: 'cancelled' })
    const w = await mountDetail('member')
    const banner = w.get('[data-ds="Alert"][data-ds-style="Banner"]')
    expect(banner.attributes('data-ds-tone')).toBe('Neutral')
    expect(banner.text()).toBe(t('session.cancelledMessage'))
    expect(banner.find('svg[class*="lucide-x"]').exists()).toBe(true)
  })
})

describe('SessionDetailView edit form', () => {
  async function openEdit() {
    withSession({ status: 'open' })
    const w = await mountDetail('admin')
    await overview(w)
      .get(`button[aria-label="${t('session.editSession')}"]`)
      .trigger('click')
    return w
  }

  it('builds the form from FormFields with Default Input and Select, footer on the divider token', async () => {
    const w = await openEdit()
    const form = overview(w)
    expect(form.findAll('[data-ds="Form Field"]')).toHaveLength(6)
    expect(form.findAll('[data-ds="Input"]').map((x) => x.attributes('data-ds-size'))).toEqual([
      'Default',
      'Default',
      'Default',
      'Default',
      'Default',
    ])
    expect(form.get('[data-ds="Select"]').attributes('data-ds-size')).toBe('Default')
    const footer = button(form as any, t('common.save')).element.parentElement!
    expect(footer.classList.contains('border-line-divider')).toBe(true)
    expect(footer.className).not.toContain('border-gray')
  })

  it('warns with an AlertTriangle Alert Danger, not an emoji, once the times changed', async () => {
    const w = await openEdit()
    expect(overview(w).text()).not.toContain(t('session.intervalsResetWarning'))
    await overview(w).findAll('input[type="time"]')[0]!.setValue('18:30')
    const alert = overview(w).get('[data-ds="Alert"]')
    expect(alert.attributes('data-ds-tone')).toBe('Danger')
    expect(alert.text()).toBe(t('session.intervalsResetWarning'))
    expect(
      alert
        .find('svg[class*="lucide-triangle-alert"], svg[class*="lucide-alert-triangle"]')
        .exists(),
    ).toBe(true)
    expect(overview(w).html()).not.toContain('⚠')
  })

  it('shows the end time error and disables Save when the end is not after the start', async () => {
    const w = await openEdit()
    await overview(w).findAll('input[type="time"]')[1]!.setValue('17:00')
    const message = overview(w).get('[data-ds="Field Message"]')
    expect(message.attributes('data-ds-tone')).toBe('Error')
    expect(message.text()).toBe(t('createSession.endTimeError'))
    expect(button(w, t('common.save')).attributes('disabled')).toBeDefined()
  })

  it('saves through update_session_details with the seeded court slot', async () => {
    const w = await openEdit()
    await overview(w).findAll('input[type="time"]')[0]!.setValue('18:30')
    await button(w, t('common.save')).trigger('click')
    await flushPromises()
    expect(supabase.rpc).toHaveBeenCalledWith('update_session_details', {
      p_session_id: 'session-1',
      p_title: 'Buổi test',
      p_status: 'open',
      p_court_fee_addon: 0,
      p_start_time: '2026-09-14T11:30:00.000Z',
      p_end_time: '2026-09-14T13:00:00.000Z',
      p_bookings: [
        {
          court_name: 'Sân 1',
          start_time: '2026-09-14T11:00:00.000Z',
          end_time: '2026-09-14T13:00:00.000Z',
          price_per_hour: 100000,
        },
      ],
    })
  })

  it('toasts the error when the save fails', async () => {
    const w = await openEdit()
    vi.mocked(supabase.rpc).mockResolvedValueOnce({ data: null, error: { message: 'nope' } } as any)
    await button(w, t('common.save')).trigger('click')
    await flushPromises()
    expect(h.toast.error).toHaveBeenCalledWith('nope')
  })
})

describe('SessionDetailView attendance header and member select', () => {
  it('puts a Locked Badge under the Tinted Section Header of a finalized session', async () => {
    withSession({ status: 'waiting_for_payment' }, ATTENDANCE_TABLES)
    const w = await mountDetail('admin')
    const header = w.get('#attendance-section [data-ds="Section Header"]')
    expect(header.attributes('data-ds-style')).toBe('Tinted')
    expect(header.get('h2').text()).toBe(t('session.attendance'))
    const badge = header.get('[data-ds="Badge"]')
    expect(badge.attributes('data-ds-tone')).toBe('Neutral')
    expect(badge.text()).toBe(t('session.lockedStatusLabel'))
    expect(badge.find('svg[class*="lucide-lock"]').exists()).toBe(true)
  })

  it('shows no badge for an admin on an open session', async () => {
    openAttendance()
    const w = await mountDetail('admin')
    expect(
      w.find('#attendance-section [data-ds="Section Header"] [data-ds="Badge"]').exists(),
    ).toBe(false)
  })

  it('toggles the Select Trigger between closed and open with ChevronDown and ChevronUp', async () => {
    openAttendance()
    const w = await mountDetail('admin')
    const trigger = () => w.get('[data-ds="Select Trigger"]')
    expect(trigger().attributes('data-ds-content')).toBe('Placeholder')
    expect(trigger().attributes('data-ds-open')).toBe('false')
    expect(trigger().attributes('aria-expanded')).toBe('false')
    expect(trigger().attributes('aria-haspopup')).toBeUndefined()
    expect(trigger().find('svg[class*="lucide-chevron-down"]').exists()).toBe(true)
    expect(trigger().find('svg[class*="lucide-chevron-left"]').exists()).toBe(false)

    await trigger().trigger('click')
    expect(trigger().attributes('data-ds-open')).toBe('true')
    expect(trigger().attributes('aria-expanded')).toBe('true')
    expect(trigger().find('svg[class*="lucide-chevron-up"]').exists()).toBe(true)
    expect(trigger().find('svg[class*="lucide-chevron-left"]').exists()).toBe(false)

    const menu = w.get('[data-ds="Multi-select Menu"]')
    expect(menu.attributes('data-ds-content')).toBe('Options')
    const options = menu.findAll('[data-ds="Checkbox Field"]')
    expect(options.map((o) => o.text())).toEqual(['Chi', 'Dung'])
    expect(options.every((o) => o.attributes('data-ds-style') === 'Option')).toBe(true)
    await options[0]!.get('input').setValue(true)
    await options[1]!.get('input').setValue(true)
    expect(trigger().attributes('data-ds-content')).toBe('Selected')
    expect(trigger().text()).toBe(t('session.selectedCount', { count: 2 }))
    expect(
      w.findAll('[data-ds="Checkbox Field"]').map((o) => o.attributes('data-ds-checked')),
    ).toEqual(['true', 'true'])
  })

  it('shows an EmptyState in the menu when no member is left', async () => {
    withSession(
      { status: 'open' },
      { ...ATTENDANCE_TABLES, members: [member('m1', 'An'), member('m2', 'Binh')] },
    )
    const w = await mountDetail('admin')
    await w.get('[data-ds="Select Trigger"]').trigger('click')
    const menu = w.get('[data-ds="Multi-select Menu"]')
    expect(menu.attributes('data-ds-content')).toBe('Empty')
    const empty = menu.get('[data-ds="Empty State"]')
    expect(empty.attributes('data-ds-style')).toBe('Plain')
    expect(empty.text()).toBe(t('session.noMoreMembers'))
  })

  it('registers each selected member and shows the Button loading while pending', async () => {
    openAttendance()
    const w = await mountDetail('admin')
    const register = () => w.get('[data-ds="Add Members Panel"] [data-ds="Button"]')
    expect(register().attributes('disabled')).toBeDefined()

    await w.get('[data-ds="Select Trigger"]').trigger('click')
    const boxes = w.findAll('[data-ds="Checkbox Field"] input')
    await boxes[0]!.setValue(true)
    await boxes[1]!.setValue(true)
    expect(register().attributes('disabled')).toBeUndefined()

    let release!: (v: any) => void
    vi.mocked(supabase.rpc).mockImplementation((name: string) =>
      name === 'add_member_to_session_full_presence'
        ? (new Promise((resolve) => (release = resolve)) as any)
        : Promise.resolve({ data: [], error: null }),
    )
    await register().trigger('click')
    expect(register().attributes('aria-busy')).toBe('true')
    expect(register().attributes('data-ds-state')).toBe('Loading')
    release({ data: null, error: null })
    await flushPromises()
    expect(supabase.rpc).toHaveBeenCalledWith('add_member_to_session_full_presence', {
      p_session_id: 'session-1',
      p_member_id: 'm3',
    })
    expect(supabase.rpc).toHaveBeenCalledWith('add_member_to_session_full_presence', {
      p_session_id: 'session-1',
      p_member_id: 'm4',
    })
  })
})

describe('SessionDetailView registrations and presence', () => {
  it('draws a Registration Card per member with the absent and editable axes', async () => {
    openAttendance()
    const w = await mountDetail('admin')
    const [present, absent] = cards(w)
    expect(present!.attributes('data-ds-absent')).toBe('false')
    expect(present!.attributes('data-ds-editable')).toBe('true')
    expect(present!.classes()).toEqual(expect.arrayContaining(['bg-surface-card']))
    expect(present!.find('[data-ds="Badge"]').exists()).toBe(false)
    expect(absent!.attributes('data-ds-absent')).toBe('true')
    expect(absent!.classes()).toEqual(expect.arrayContaining(['bg-surface-subtle', 'opacity-90']))
    const badge = absent!.get('[data-ds="Badge"]')
    expect(badge.attributes('data-ds-tone')).toBe('Danger')
    expect(badge.text()).toBe(t('session.absent'))
    const note = absent!.get('[data-ds="Alert"]')
    expect(note.attributes('data-ds-tone')).toBe('Neutral')
    expect(note.find('svg[class*="lucide-lock"]').exists()).toBe(true)
    const toggles = (c: typeof present) =>
      c!.findAll('button').find((b) => b.text() === t('session.markAbsent'))!
    expect(toggles(present)!.attributes('aria-pressed')).toBe('false')
    expect(toggles(absent)!.attributes('aria-pressed')).toBe('true')
    expect(toggles(absent)!.attributes('data-ds-style')).toBe('Outline Danger')
    expect(toggles(present)!.attributes('data-ds-style')).toBe('Secondary')
  })

  it('hides the card actions and shows a lock note when the session is not editable', async () => {
    withSession({ status: 'waiting_for_payment' }, ATTENDANCE_TABLES)
    const w = await mountDetail('admin')
    const [present] = cards(w)
    expect(present!.attributes('data-ds-editable')).toBe('false')
    expect(present!.findAll('button')).toHaveLength(0)
    expect(present!.get('[data-ds="Alert"]').text()).toBe(t('session.lockedStatusLabel'))
    const interval = present!.get('[data-ds="Interval Check Row"]')
    expect(interval.attributes('data-ds-editable')).toBe('false')
    expect(interval.classes()).toContain('opacity-70')
    expect(interval.get('input').attributes('disabled')).toBeDefined()
  })

  it('shows a dashed empty state when nobody is registered', async () => {
    withSession({ status: 'open' }, { ...ATTENDANCE_TABLES, session_registrations: [] })
    const w = await mountDetail('admin')
    const empty = w.get('#attendance-section [data-ds="Empty State"]')
    expect(empty.attributes('data-ds-style')).toBe('Dashed Muted')
    expect(empty.attributes('data-ds-size')).toBe('Small')
    expect(empty.text()).toBe(t('session.noRegisteredMembers'))
  })

  it('upserts is_present for the ticked interval and reverts on error', async () => {
    openAttendance()
    const w = await mountDetail('admin')
    const boxes = () => rows(w)[0]!.findAll('input[type="checkbox"]')
    await boxes()[0]!.setValue(true)
    await flushPromises()
    expect(upserts().map((c) => c.args)).toEqual([
      [
        { interval_id: 'i1', member_id: 'm1', is_present: true },
        { onConflict: 'interval_id, member_id' },
      ],
    ])

    h.upsertError = { message: 'fail' }
    await boxes()[1]!.setValue(false)
    await flushPromises()
    expect(h.toast.error).toHaveBeenCalledWith(t('session.presenceUpdateError'))
    const second = cards(w)[0]!.findAll('[data-ds="Interval Check Row"]')[1]!
    expect(second.attributes('data-ds-checked')).toBe('true')
  })

  it('marks a member absent by upserting every interval as not present', async () => {
    openAttendance()
    const w = await mountDetail('admin')
    const absentBtn = cards(w)[0]!
      .findAll('button')
      .find((b) => b.text() === t('session.markAbsent'))!
    await absentBtn.trigger('click')
    await flushPromises()
    expect(upserts().map((c) => c.args)).toEqual([
      [
        [
          { interval_id: 'i1', member_id: 'm1', is_present: false },
          { interval_id: 'i2', member_id: 'm1', is_present: false },
        ],
        { onConflict: 'interval_id, member_id' },
      ],
    ])
  })

  it('removes a member through remove_member_from_session after confirm', async () => {
    openAttendance()
    vi.spyOn(window, 'confirm').mockReturnValue(true)
    const w = await mountDetail('admin')
    const remove = cards(w)[0]!
      .findAll('button')
      .find((b) => b.text() === t('common.remove'))!
    expect(remove.attributes('data-ds-style')).toBe('Outline Danger')
    await remove.trigger('click')
    await flushPromises()
    expect(supabase.rpc).toHaveBeenCalledWith('remove_member_from_session', {
      p_session_id: 'session-1',
      p_member_id: 'm1',
    })
  })

  it('draws Attendance Rows with labelled IconButtons and the sticky member column', async () => {
    openAttendance()
    const w = await mountDetail('admin')
    const [first, second] = rows(w)
    expect(first!.attributes('data-ds-absent')).toBe('false')
    expect(first!.attributes('data-ds-editable')).toBe('true')
    expect(second!.attributes('data-ds-absent')).toBe('true')
    expect(second!.classes()).toEqual(expect.arrayContaining(['bg-surface-subtle', 'opacity-60']))
    const [remove, absent] = first!.findAll('button')
    expect(remove!.attributes('aria-label')).toBe(t('session.removeRegistrationTooltip'))
    expect(absent!.attributes('aria-label')).toBe(t('session.markAbsentTooltip'))
    expect(absent!.attributes('data-ds-style')).toBe('Ghost')
    expect(second!.findAll('button')[1]!.attributes('data-ds-style')).toBe('Ghost Danger')
    expect(first!.get('td').classes()).toEqual(
      expect.arrayContaining(['sticky', 'left-0', 'after:right-0', 'after:bg-line-divider']),
    )
    expect(w.get('#attendance-section table').classes()).toContain('min-w-full')
    expect(w.get('#attendance-section table').element.parentElement!.classList).toContain(
      'overflow-x-auto',
    )
    // every th keeps whitespace-nowrap
    for (const th of w.findAll('#attendance-section thead th')) {
      expect(th.classes()).toContain('whitespace-nowrap')
    }
    expect(first!.findAll('input[type="checkbox"]').every((b) => !b.attributes('disabled'))).toBe(
      true,
    )
  })

  it('disables the desktop checkboxes once the session is finalized', async () => {
    withSession({ status: 'waiting_for_payment' }, ATTENDANCE_TABLES)
    const w = await mountDetail('admin')
    const boxes = rows(w)[0]!.findAll('input[type="checkbox"]')
    expect(boxes).toHaveLength(2)
    expect(boxes.every((b) => b.attributes('disabled') !== undefined)).toBe(true)
    expect(rows(w)[0]!.findAll('button')).toHaveLength(0)
  })
})

describe('SessionDetailView S6 range', () => {
  const s6 = source.slice(0, source.indexOf('<!-- Cost Summary (Live mode) -->'))

  it('has no palette class, emoji icon or gray-50 divider before the cost section', () => {
    expect(s6.length).toBeGreaterThan(1000)
    expect([...s6.matchAll(PALETTE_CLASS)].map((m) => m[1])).toEqual([])
    expect(s6).not.toContain('🚫')
    expect(s6).not.toContain('⚠')
    expect(s6).not.toContain('&#x26A0;')
    expect(s6).not.toContain('border-gray-50')
  })

  it('has no native button, input or select besides the Select Trigger', () => {
    expect(s6.match(/<button/g)).toHaveLength(1)
    expect(s6).toContain('data-ds="Select Trigger"')
    expect(s6).not.toMatch(/<input|<select/)
  })

  it('has the ARIA of the removed inline markup rendered by the shared components', async () => {
    openAttendance()
    const w = await mountDetail('admin')
    const hidden = (root: { findAll: (s: string) => any[] }, what: string) => {
      const svgs = root.findAll('svg')
      expect(svgs.length, what).toBeGreaterThan(0)
      for (const svg of svgs) expect(svg.attributes('aria-hidden'), what).toBe('true')
    }
    // IconButton aria-label and the aria-hidden icon inside: refresh and edit
    for (const label of [t('session.refreshSession'), t('session.editSession')]) {
      const btn = overview(w).get(`button[aria-label="${label}"]`)
      expect(btn.attributes('data-ds')).toBe('Icon Button')
      hidden(btn, label)
    }
    for (const svg of overview(w).findAll('[data-ds="Button"] svg')) {
      expect(svg.attributes('aria-hidden')).toBe('true')
    }
    // Locked Badge Lock and card lock-note Alert Lock, mobile card UserX / Trash2 Button icons
    const card = cards(w)[1]!
    hidden(card.get('[data-ds="Alert"]'), 'card lock note')
    for (const label of [t('session.markAbsent'), t('common.remove')]) {
      hidden(card.findAll('button').find((b) => b.text() === label)!, label)
    }
    // Interval checkbox aria-label survives through Checkbox
    expect(cards(w)[0]!.get('input[type="checkbox"]').attributes('aria-label')).toContain('An')
    // the close X of the edit form is a labelled IconButton with an aria-hidden icon
    await overview(w)
      .get(`button[aria-label="${t('session.editSession')}"]`)
      .trigger('click')
    const close = overview(w).get(`button[aria-label="${t('common.cancel')}"]`)
    expect(close.attributes('data-ds')).toBe('Icon Button')
    hidden(close, 'close')
  })

  it('has aria-hidden on the Locked Badge Lock and the cancelled Banner X', async () => {
    withSession({ status: 'waiting_for_payment' }, ATTENDANCE_TABLES)
    const w = await mountDetail('admin')
    const badge = w.get('#attendance-section [data-ds="Section Header"] [data-ds="Badge"]')
    expect(badge.get('svg').attributes('aria-hidden')).toBe('true')
    w.unmount()
    withSession({ status: 'cancelled' })
    const c = await mountDetail('member')
    expect(
      c.get('[data-ds="Alert"][data-ds-style="Banner"] svg').attributes('aria-hidden'),
    ).toBe('true')
  })

  it('announces the in-session error Alert with role alert and aria-live polite', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({ data: null, error: { message: 'x' } } as any)
    const w = await mountDetail('member')
    const alert = w.get('.space-y-4 > [data-ds="Alert"]')
    expect(alert.attributes('data-ds-tone')).toBe('Danger')
    expect(alert.attributes('role')).toBe('alert')
    expect(alert.attributes('aria-live')).toBe('polite')
    expect(alert.text()).toContain(t('session.paymentDataLoadError'))
  })
})

// ---- S7: cost summary, payments and the section ribbon ----

const costRow = (id: string, name: string, total: number, extra: number) => ({
  member_id: id,
  display_name: name,
  final_total: total,
  intervals_count: 2,
  total_court_fee: 80000,
  total_shuttle_fee: 40000,
  total_extra_fee: extra,
})
const COSTS = [costRow('m1', 'An', 140000, 20000), costRow('m2', 'Binh', 110000, -10000)]
const withCosts = (data: any[]) =>
  vi.mocked(supabase.rpc).mockImplementation(((name: string) =>
    Promise.resolve({
      data: name === 'calculate_session_costs' ? data : [],
      error: null,
    })) as any)

const snap = (id: string, member_id: string, name: string, status: string, paid = 0) => ({
  id,
  session_id: 'session-1',
  member_id,
  final_amount: 120000,
  paid_amount: paid,
  payment_code: `CL${id}`,
  status,
  court_fee_amount: 80000,
  shuttle_fee_amount: 40000,
  extra_fee_amount: 0,
  member: { display_name: name },
})
const SNAPSHOTS = [
  snap('snap-1', 'm1', 'Nguyễn Văn A', 'pending'),
  snap('snap-2', 'm2', 'Binh', 'partial', 50000),
  snap('snap-3', 'm3', 'Chi', 'paid', 120000),
]
const payCards = (w: ReturnType<typeof mount>) => w.findAll('[data-ds="Payment Card"]')
const payRows = (w: ReturnType<typeof mount>) => w.findAll('tr[data-ds="Payment Table Row"]')
const classesOf = (w: { classes: () => string[] }) => w.classes()

describe('SessionDetailView S7 cost summary', () => {
  it('renders a Tinted SectionHeader with the live suffix inside the h2', async () => {
    withSession({ status: 'open' })
    const w = await mountDetail('member')
    const header = w.get('#costs-section [data-ds="Section Header"]')
    expect(header.attributes('data-ds-style')).toBe('Tinted')
    const h2 = header.get('h2')
    expect(h2.text()).toBe(`${t('session.costSummary')} (${t('session.live')})`)
    expect(h2.get('span').text()).toBe(`(${t('session.live')})`)
  })

  it('shows the mobile Amount Panel and Cost Cards while live', async () => {
    withSession({ status: 'open' })
    withCosts(COSTS)
    const w = await mountDetail('member')
    const panel = w.get('#costs-section [data-ds="Amount Panel"]')
    expect(panel.attributes('data-ds-tone')).toBe('Success')
    expect(panel.text()).toContain(t('session.live'))
    const cards = w.findAll('#costs-section [data-ds="Cost Card"]')
    expect(cards.map((c) => c.attributes('data-ds-extra'))).toEqual(['Positive', 'Negative'])
    const extraRows = cards.map(
      (c) =>
        c
          .findAll('[data-ds="Key Value Row"]')
          .find((r) => r.text().includes(t('session.extraFee')))!,
    )
    expect(extraRows.map((r) => r.attributes('data-ds-tone'))).toEqual(['Debt', 'Credit'])
    expect(extraRows.map((r) => r.attributes('data-ds-value-tone'))).toEqual(['Debt', 'Success'])
    const last = cards[0]!.findAll('[data-ds="Key Value Row"]').at(-1)!
    expect(last.attributes('data-ds-tone')).toBe('Credit')
    expect(last.text()).toContain(t('session.surplusFund'))
  })

  it('shows the empty text when there are no costs', async () => {
    withSession({ status: 'open' })
    const w = await mountDetail('member')
    expect(w.findAll('#costs-section [data-ds="Cost Card"]')).toHaveLength(0)
    expect(w.get('#costs-section').text()).toContain(t('session.liveCostsEmpty'))
  })

  it('renders the desktop cost table with 6 header cells and Cost Table Rows', async () => {
    withSession({ status: 'open' })
    withCosts([...COSTS, costRow('m3', 'Chi', 90000, 0)])
    const w = await mountDetail('member')
    const heads = w.findAll('#costs-section thead [data-ds="Table Header Cell"]')
    expect(heads.map((x) => x.attributes('data-ds-align'))).toEqual([
      'Left',
      'Right',
      'Center',
      'Right',
      'Right',
      'Right',
    ])
    const rowsEl = w.findAll('#costs-section tr[data-ds="Cost Table Row"]')
    expect(rowsEl.map((r) => r.attributes('data-ds-extra'))).toEqual([
      'Positive',
      'Negative',
      'Zero',
    ])
    expect(rowsEl[2]!.findAll('td').at(-1)!.text()).toBe('—')
    const surplus = w.get('#costs-section tr[data-ds="Surplus Table Row"]')
    expect(surplus.attributes('data-ds-table')).toBe('Cost')
    expect(surplus.get('td').attributes('colspan')).toBe('5')
    for (const cell of w.findAll('#costs-section td, #costs-section th')) {
      expect(cell.classes()).toContain('whitespace-nowrap')
    }
  })

  it.each(['waiting_for_payment', 'done'])('shows the empty text when %s', async (status) => {
    withSession({ status })
    withCosts(COSTS)
    const w = await mountDetail('member')
    expect(w.findAll('#costs-section [data-ds="Cost Card"]')).toHaveLength(0)
    expect(w.get('#costs-section').text()).toContain(t('session.liveCostsEmpty'))
  })
})

describe('SessionDetailView S7 payments', () => {
  const waiting = () =>
    withSession({ status: 'waiting_for_payment' }, { session_costs_snapshot: SNAPSHOTS })

  it('shows the empty text with no snapshots', async () => {
    withSession({ status: 'waiting_for_payment' }, { session_costs_snapshot: [] })
    const w = await mountDetail('member')
    expect(w.get('#payments-section').text()).toContain(t('session.paymentSnapshotsEmpty'))
    expect(payCards(w)).toHaveLength(0)
  })

  it('renders Payment Cards per status and admin gating', async () => {
    waiting()
    const w = await mountDetail('admin')
    const cards = payCards(w)
    expect(cards.map((c) => c.attributes('data-ds-status'))).toEqual(['Partial', 'Paid', 'Pending'])
    expect(cards.map((c) => c.attributes('data-ds-admin'))).toEqual(['true', 'false', 'true'])
    expect(w.get('#payments-section [data-ds="Amount Panel"]').attributes('data-ds-tone')).toBe(
      'Success',
    )
    const badges = cards.map((c) => c.get('[data-ds="Payment Status Badge"]'))
    expect(badges.map((b) => b.attributes('data-ds-status'))).toEqual([
      'Partial',
      'Paid',
      'Pending',
    ])
    expect(badges[2]!.classes()).toEqual(
      expect.arrayContaining(['bg-status-danger', 'text-status-danger-strong']),
    )
    expect(badges[0]!.classes()).toContain('bg-status-warning')
    expect(badges[1]!.classes()).toContain('bg-status-success')
    // Checkbox Tile only for admin and not paid
    expect(cards.map((c) => c.find('[data-ds="Checkbox Tile"]').exists())).toEqual([
      true,
      false,
      true,
    ])
    // actions
    const [, paid, pending] = cards
    const qr = pending!.findAll('[data-ds="Button"]')
    expect(qr.map((b) => b.attributes('data-ds-style'))).toEqual([
      'Outline Brand',
      'Outline Success',
    ])
    expect(qr.every((b) => b.attributes('data-ds-size') === 'Default')).toBe(true)
    expect(qr[0]!.find('svg[class*="lucide-qr-code"]').exists()).toBe(true)
    const indicator = paid!.get('[data-ds="Paid Indicator"]')
    expect(indicator.attributes('data-ds-style')).toBe('Banner')
    expect(indicator.text()).toBe(t('payment.done'))
    expect(paid!.findAll('[data-ds="Button"]')).toHaveLength(0)
  })

  it('hides the cash button and the tile from a member', async () => {
    waiting()
    const w = await mountDetail('member')
    const cards = payCards(w)
    expect(cards.every((c) => c.attributes('data-ds-admin') === 'false')).toBe(true)
    expect(cards.some((c) => c.find('[data-ds="Checkbox Tile"]').exists())).toBe(false)
    expect(cards[2]!.findAll('[data-ds="Button"]')).toHaveLength(1)
    expect(cards[2]!.text()).not.toContain(t('payment.cashPay'))
  })

  it('renders Payment Table Rows with checkbox or StatusIcon, buttons and inline paid indicator', async () => {
    waiting()
    const w = await mountDetail('admin')
    const rowsEl = payRows(w)
    expect(rowsEl.map((r) => r.attributes('data-ds-status'))).toEqual([
      'Partial',
      'Paid',
      'Pending',
    ])
    expect(rowsEl.every((r) => r.attributes('data-ds-admin') === 'true')).toBe(true)
    expect(rowsEl.map((r) => r.attributes('data-ds-selected'))).toEqual(['false', 'false', 'false'])
    const box = rowsEl[2]!.get('input[type="checkbox"]')
    expect(box.attributes('data-ds-size')).toBe('20')
    expect(box.attributes('aria-label')).toBe(
      `${t('session.groupPaymentBar', { count: 1 })}: Nguyễn Văn A`,
    )
    const icon = rowsEl[1]!.get('[data-ds="Status Icon"]')
    expect(icon.attributes('data-ds-kind')).toBe('Check')
    expect(icon.attributes('data-ds-size')).toBe('20')
    expect(icon.text()).toBe(t('payment.paid'))
    const buttons = rowsEl[2]!.findAll('[data-ds="Button"]')
    expect(buttons.map((b) => b.attributes('data-ds-size'))).toEqual(['Small', 'Small'])
    expect(buttons.every((b) => b.classes().includes('w-full'))).toBe(true)
    expect(buttons[0]!.attributes('aria-label')).toBe(`${t('payment.qrPay')}: Nguyễn Văn A`)
    expect(buttons[1]!.attributes('aria-label')).toBe(`${t('payment.cashPay')}: Nguyễn Văn A`)
    expect(rowsEl[1]!.get('[data-ds="Paid Indicator"]').attributes('data-ds-style')).toBe('Inline')
    const surplus = w.get('#payments-section tr[data-ds="Surplus Table Row"]')
    expect(surplus.attributes('data-ds-table')).toBe('Payment')
    const heads = w.findAll('#payments-section thead [data-ds="Table Header Cell"]')
    expect(heads).toHaveLength(9)
    expect(heads[0]!.attributes('data-ds-content')).toBe('Empty')
    expect(heads[0]!.classes()).toContain('w-12')
    for (const cell of w.findAll('#payments-section td, #payments-section th')) {
      expect(cell.classes()).toContain('whitespace-nowrap')
    }
  })

  it('opens the QR and cash modals with the member name', async () => {
    waiting()
    const w = await mountDetail('admin')
    const card = payCards(w)[2]!
    const [qr, cash] = card.findAll('[data-ds="Button"]')
    await qr!.trigger('click')
    expect(w.findComponent({ name: 'PaymentQRModal' }).props()).toMatchObject({
      show: true,
      memberName: 'Nguyễn Văn A',
    })
    await cash!.trigger('click')
    expect(w.findComponent({ name: 'ManualPaymentModal' }).props()).toMatchObject({
      show: true,
      memberName: 'Nguyễn Văn A',
    })
  })

  it('shows the floating bar for a ticked snapshot and hides it at 0', async () => {
    waiting()
    const w = await mountDetail('admin')
    expect(w.find('[data-ds="Floating Selection Bar"]').exists()).toBe(false)
    const box = w.get('input[type="checkbox"][value="snap-1"]')
    await box.setValue(true)
    const bar = w.get('[data-ds="Floating Selection Bar"]')
    expect(bar.attributes('data-ds-style')).toBe('Brand')
    expect(bar.text()).toContain(t('session.groupPaymentBar', { count: 1 }))
    const amount = new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(
      120000,
    )
    expect(bar.text()).toContain(t('session.totalSelected', { amount }))
    const btn = bar.get('[data-ds="Button"]')
    expect(btn.attributes('data-ds-size')).toBe('Default')
    expect(btn.attributes('data-ds-style')).toBe('Inverse')
    expect(btn.find('svg[class*="lucide-qr-code"]').exists()).toBe(true)
    expect(payRows(w)[2]!.attributes('data-ds-selected')).toBe('true')
    await box.setValue(false)
    expect(w.find('[data-ds="Floating Selection Bar"]').exists()).toBe(false)
  })

  it('creates the group payment with the selected ids and shows loading while pending', async () => {
    waiting()
    let resolve!: (v: any) => void
    vi.mocked(supabase.rpc).mockImplementation(((name: string) =>
      name === 'create_group_payment'
        ? new Promise((r) => (resolve = r))
        : Promise.resolve({ data: [], error: null })) as any)
    const w = await mountDetail('admin')
    await w.get('input[type="checkbox"][value="snap-1"]').setValue(true)
    await w.get('[data-ds="Floating Selection Bar"] [data-ds="Button"]').trigger('click')
    expect(supabase.rpc).toHaveBeenCalledWith('create_group_payment', {
      p_snapshot_ids: ['snap-1'],
    })
    expect(
      w.get('[data-ds="Floating Selection Bar"] [data-ds="Button"]').attributes('data-ds-state'),
    ).toBe('Loading')
    resolve({ data: { group_code: 'G1', total_amount: 120000 }, error: null })
    await flushPromises()
  })

  it('toasts the group payment error', async () => {
    waiting()
    vi.mocked(supabase.rpc).mockImplementation(((name: string) =>
      Promise.resolve(
        name === 'create_group_payment'
          ? { data: null, error: { message: 'x' } }
          : { data: [], error: null },
      )) as any)
    vi.spyOn(console, 'error').mockImplementation(() => {})
    const w = await mountDetail('admin')
    await w.get('input[type="checkbox"][value="snap-1"]').setValue(true)
    await w.get('[data-ds="Floating Selection Bar"] [data-ds="Button"]').trigger('click')
    await flushPromises()
    expect(h.toast.error).toHaveBeenCalledWith(t('session.groupPaymentError'))
  })

  it('renders the section ribbon with the active tab and scrolls on click', async () => {
    waiting()
    const scroll = vi.fn()
    if (!Element.prototype.scrollIntoView) Element.prototype.scrollIntoView = () => {}
    vi.spyOn(Element.prototype, 'scrollIntoView').mockImplementation(scroll)
    const w = await mountDetail('member')
    const nav = w.get('nav[data-ds="Section Tab Bar"]')
    // the page renders at the top, so the ribbon starts on Overview whatever the status
    expect(nav.attributes('data-ds-active')).toBe('Overview')
    const tabs = nav.findAll('[data-ds="Section Tab"]')
    expect(tabs).toHaveLength(4)
    expect(tabs.map((x) => x.attributes('data-ds-state'))).toEqual([
      'Active',
      'Inactive',
      'Inactive',
      'Inactive',
    ])
    expect(tabs[0]!.attributes('aria-current')).toBe('true')
    // the wrapper is not attached to the document, so resolve the section ids inside it
    vi.spyOn(document, 'getElementById').mockImplementation(
      (id) => w.find(`#${id}`).element as HTMLElement,
    )
    scroll.mockClear()
    await tabs[2]!.trigger('click')
    expect(scroll.mock.contexts).toContain(w.get('#costs-section').element)
    expect(nav.attributes('data-ds-active')).toBe('Costs')
    expect(tabs[2]!.attributes('data-ds-state')).toBe('Active')
    await tabs[3]!.trigger('click')
    expect(nav.attributes('data-ds-active')).toBe('Payments')
  })
})

describe('SessionDetailView S7 range', () => {
  const s7 = source.slice(source.indexOf('<!-- Cost Summary (Live mode) -->'))

  it('has no palette class and no divider/input alias in the whole file', () => {
    expect([...source.matchAll(PALETTE_CLASS)].map((m) => m[1])).toEqual([])
    expect(source).not.toMatch(/(?:bg|text|border|divide|ring)-(?:divider|input)\b/)
  })

  it('has no native button besides the Select Trigger and the Section Tab, and no input or select', () => {
    expect(source.match(/<button/g)).toHaveLength(2)
    expect(s7.match(/<button/g)).toHaveLength(1)
    expect(s7).toContain('data-ds="Section Tab"')
    expect(source).not.toMatch(/<input|<select/)
  })
})
