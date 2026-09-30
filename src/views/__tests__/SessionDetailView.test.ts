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
