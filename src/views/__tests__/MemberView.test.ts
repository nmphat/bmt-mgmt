import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createMemoryHistory } from 'vue-router'
import MemberView from '@/views/MemberView.vue'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'

// One Supabase chain builder per `from()` call; the record keeps the chain for exact payload assertions.
const h = vi.hoisted(() => ({
  result: { data: null, error: null } as any,
  chains: [] as { table: string; calls: { m: string; args: any[] }[] }[],
  toast: { error: vi.fn(), success: vi.fn(), info: vi.fn() },
}))

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn((table: string) => {
      const record = { table, calls: [] as { m: string; args: any[] }[] }
      h.chains.push(record)
      const builder: any = {}
      for (const method of ['select', 'eq', 'order', 'insert', 'update', 'delete', 'single']) {
        builder[method] = vi.fn((...args: any[]) => {
          record.calls.push({ m: method, args })
          return builder
        })
      }
      builder.then = (resolve: any) => resolve(h.result)
      return builder
    }),
  },
}))
vi.mock('vue-toastification', () => ({ useToast: () => h.toast }))

const t = (key: string, params?: Record<string, unknown>) => useLangStore().t(key, params as any)

const member = (
  id: string,
  display_name: string,
  role: 'admin' | 'member' = 'member',
  is_active = true,
) => ({ id, display_name, role, is_active })

type Who = 'admin' | 'member' | 'guest'

async function mountMembers(who: Who) {
  setActivePinia(createPinia())
  const auth = useAuthStore()
  if (who !== 'guest') {
    auth.user = { id: 'u1', email: 'an@club.vn' } as any
    auth.profile = { id: 'm1', role: who, display_name: 'an' }
  }
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: { template: '<div />' } },
      { path: '/member/:id', component: { template: '<div />' } },
    ],
  })
  router.push('/')
  await router.isReady()
  const w = mount(MemberView, { global: { plugins: [router] } })
  await flushPromises()
  await flushPromises()
  return { w }
}

type W = Awaited<ReturnType<typeof mountMembers>>['w']
const chainWith = (method: string) => h.chains.find((c) => c.calls.some((x) => x.m === method))
const chainArgs = (method: string) =>
  chainWith(method)?.calls.find((x) => x.m === method)?.args as any[] | undefined
const pageAction = (w: W) => w.get('[data-ds="Page Header"] [data-ds="Button"]')
const addForm = (w: W) => w.get('form.grid')
// View mode: 0 = edit, 1 = delete. Edit mode: 0 = save, 1 = cancel.
const rowIcon = (w: W, i = 0) => w.get('tbody tr').findAll('[data-ds="Icon Button"]')[i]!
const rowEdit = (w: W) => rowIcon(w, 0)
const rowDelete = (w: W) => rowIcon(w, 1)
const rowSave = (w: W) => rowIcon(w, 0)
const rowCancel = (w: W) => rowIcon(w, 1)

describe('MemberView (I/O matrix)', () => {
  beforeEach(() => {
    h.result = { data: null, error: null }
    h.chains = []
    h.toast.error.mockReset()
    h.toast.success.mockReset()
    h.toast.info.mockReset()
  })
  afterEach(() => vi.restoreAllMocks())

  // Row: Members loading / empty / list
  it('loading: Spinner 48 while the list fetch is pending', async () => {
    h.result = new Promise(() => {})
    const { w } = await mountMembers('admin')
    const spinner = w.get('[data-ds="Spinner"]')
    expect(spinner.attributes('data-ds-size')).toBe('48')
    expect(w.find('article').exists()).toBe(false)
    expect(w.find('tbody tr').exists()).toBe(false)
  })

  it('empty: Empty State Card Center with member.emptyState', async () => {
    h.result = { data: [], error: null }
    const { w } = await mountMembers('admin')
    const empty = w.get('[data-ds="Empty State"]')
    expect(empty.attributes('data-ds-style')).toBe('Card')
    expect(empty.attributes('data-ds-align')).toBe('Center')
    expect(empty.text()).toBe(t('member.emptyState'))
    expect(w.find('article').exists()).toBe(false)
    expect(w.find('tbody tr').exists()).toBe(false)
  })

  it('list: Page Header Title Action, one Member Card and one table row per member, sorted by name', async () => {
    h.result = { data: [member('m1', 'Binh'), member('m2', 'An')], error: null }
    const { w } = await mountMembers('admin')
    const header = w.get('[data-ds="Page Header"]')
    expect(header.attributes('data-ds-layout')).toBe('Title Action')
    expect(header.get('h1').text()).toBe(t('member.title'))
    const cards = w.findAll('article')
    expect(cards).toHaveLength(2)
    expect(cards.map((c) => c.get('h2').text())).toEqual(['An', 'Binh'])
    const rows = w.findAll('tbody tr')
    expect(rows).toHaveLength(2)
    expect(rows[0]!.get('td').text()).toBe('An')
    const heads = w.findAll('[data-ds="Table Header Cell"]')
    expect(heads.map((c) => c.attributes('data-ds-align'))).toEqual([
      'Left',
      'Left',
      'Center',
      'Right',
    ])
    expect(heads.map((c) => c.attributes('data-ds-content'))).toEqual([
      'Text',
      'Text',
      'Text',
      'Text',
    ])
    expect(heads.map((c) => c.text())).toEqual([
      t('member.name'),
      t('member.role'),
      t('member.active'),
      t('common.actions'),
    ])
  })

  it('fetch error: toast.error member.fetchError and the empty state', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    h.result = { data: null, error: new Error('network') }
    const { w } = await mountMembers('admin')
    expect(h.toast.error).toHaveBeenCalledWith(t('member.fetchError'))
    expect(w.get('[data-ds="Empty State"]').text()).toBe(t('member.emptyState'))
  })

  // Row: Members guest
  it('guest: Page Header action, row edit / delete hidden; Details link to /member/<id> shown', async () => {
    h.result = { data: [member('m1', 'An')], error: null }
    const { w } = await mountMembers('guest')
    expect(w.get('[data-ds="Page Header"]').find('[data-ds="Button"]').exists()).toBe(false)

    const row = w.get('tbody tr')
    expect(row.find('[data-ds="Icon Button"]').exists()).toBe(false)
    const desktopDetails = row.get('a[href="/member/m1"]')
    expect(desktopDetails.attributes('data-ds')).toBe('Button')
    expect(desktopDetails.attributes('data-ds-size')).toBe('Small')
    expect(desktopDetails.attributes('data-ds-style')).toBe('Ghost')
    expect(desktopDetails.attributes('title')).toBe(t('debt.details'))

    const card = w.get('article')
    expect(card.findAll('[data-ds="Button"]')).toHaveLength(1)
    const mobileDetails = card.get('a[href="/member/m1"]')
    expect(mobileDetails.attributes('data-ds-style')).toBe('Outline Brand')
    expect(mobileDetails.attributes('data-ds-size')).toBe('Default')
    expect(mobileDetails.attributes('aria-label')).toBe(
      t('member.viewDetailsFor', { name: 'An' }),
    )
    expect(mobileDetails.find('svg.lucide-chevron-right').exists()).toBe(true)
  })

  // Row: Add member
  it('add member: insert([{display_name: trimmed, role: admin, is_active: true}]) and the form closes', async () => {
    h.result = { data: [member('m1', 'An')], error: null }
    const { w } = await mountMembers('admin')
    await pageAction(w).trigger('click')
    const form = addForm(w)
    await form.get('input[type="text"]').setValue('  Chi  ')
    await form.get('select').setValue('admin')
    h.result = { data: [member('m9', 'Chi', 'admin')], error: null }
    await form.trigger('submit')
    await flushPromises()

    expect(chainArgs('insert')![0]).toEqual([
      { display_name: 'Chi', role: 'admin', is_active: true },
    ])
    expect(h.toast.success).toHaveBeenCalledWith(t('toast.memberAdded'))
    expect(w.find('form.grid').exists()).toBe(false)
    expect(w.findAll('article')).toHaveLength(2)
  })

  it('add member: "create another" checked keeps the form open', async () => {
    h.result = { data: [], error: null }
    const { w } = await mountMembers('admin')
    await pageAction(w).trigger('click')
    const form = addForm(w)
    await form.get('input[type="text"]').setValue('Chi')
    const boxes = form.findAll('input[type="checkbox"]')
    await boxes[1]!.setValue(true)
    h.result = { data: [member('m9', 'Chi')], error: null }
    await form.trigger('submit')
    await flushPromises()
    expect(h.toast.success).toHaveBeenCalledWith(t('toast.memberAdded'))
    expect(w.find('form.grid').exists()).toBe(true)
  })

  it('add member: blank name -> member.nameRequired, insert not called', async () => {
    h.result = { data: [], error: null }
    const { w } = await mountMembers('admin')
    await pageAction(w).trigger('click')
    await addForm(w).trigger('submit')
    await flushPromises()
    expect(h.toast.error).toHaveBeenCalledWith(t('member.nameRequired'))
    expect(chainWith('insert')).toBeUndefined()
  })

  it('add member: duplicate name -> member.duplicateName, insert not called', async () => {
    h.result = { data: [member('m1', 'An')], error: null }
    const { w } = await mountMembers('admin')
    await pageAction(w).trigger('click')
    const form = addForm(w)
    await form.get('input[type="text"]').setValue('  an ')
    await form.trigger('submit')
    await flushPromises()
    expect(h.toast.error).toHaveBeenCalledWith(t('member.duplicateName'))
    expect(chainWith('insert')).toBeUndefined()
  })

  it('add member: Create Button data-ds-state Loading and disabled while actionLoading', async () => {
    h.result = { data: [], error: null }
    const { w } = await mountMembers('admin')
    await pageAction(w).trigger('click')
    await addForm(w).get('input[type="text"]').setValue('Chi')
    h.result = new Promise(() => {})
    await addForm(w).trigger('submit')
    const create = () => addForm(w).get('button[type="submit"]')
    expect(create().attributes('type')).toBe('submit')
    expect(create().attributes('data-ds-state')).toBe('Loading')
    expect(create().attributes('disabled')).toBeDefined()
  })

  // Row: Row badges
  it('row badges: Role Badge Default Admin/Member, Member Active Badge on mobile, Check / X in the table', async () => {
    h.result = {
      data: [member('a1', 'Admin User', 'admin', true), member('m1', 'Member User', 'member', false)],
      error: null,
    }
    const { w } = await mountMembers('member')

    const roles = w.findAll('[data-ds="Role Badge"]')
    expect(roles).toHaveLength(4)
    expect(roles.map((b) => b.attributes('data-ds-role'))).toEqual([
      'Admin',
      'Member',
      'Admin',
      'Member',
    ])
    expect(roles.map((b) => b.attributes('data-ds-size'))).toEqual([
      'Default',
      'Default',
      'Default',
      'Default',
    ])

    const active = w.findAll('[data-ds="Member Active Badge"]')
    expect(active).toHaveLength(2)
    expect(active.map((b) => b.attributes('data-ds-active'))).toEqual(['true', 'false'])
    expect(active.map((b) => b.text())).toEqual([
      t('member.activeStatus'),
      t('member.inactiveStatus'),
    ])

    expect(w.get('tbody').findAll('svg.lucide-check')).toHaveLength(1)
    expect(w.get('tbody').findAll('svg.lucide-x')).toHaveLength(1)
  })

  // Row: Edit member (desktop and mobile)
  it('edit member (mobile card): update payload with updated_at + .eq(id), leaves edit mode', async () => {
    h.result = { data: [member('m1', 'An', 'member', true)], error: null }
    const { w } = await mountMembers('admin')
    const editBtn = w
      .get('article')
      .findAll('[data-ds="Button"]')
      .find((b) => b.text().includes(t('common.edit')))!
    await editBtn.trigger('click')
    const form = w.get('article form')
    await form.get('input[type="text"]').setValue('An 2')
    h.result = { data: null, error: null }
    await form.trigger('submit')
    await flushPromises()

    const chain = chainWith('update')!
    expect(chain.calls.map((c) => c.m)).toEqual(['update', 'eq'])
    expect(chain.calls[0]!.args[0]).toMatchObject({
      display_name: 'An 2',
      role: 'member',
      is_active: true,
    })
    expect(typeof chain.calls[0]!.args[0].updated_at).toBe('string')
    expect(chain.calls[1]!.args).toEqual(['id', 'm1'])
    expect(w.find('article form').exists()).toBe(false)
    expect(w.get('article').get('h2').text()).toBe('An 2')
  })

  it('edit member (desktop row): Input Small and Select Small with aria-labels, save leaves edit mode', async () => {
    h.result = { data: [member('m1', 'An', 'member', true)], error: null }
    const { w } = await mountMembers('admin')
    await rowEdit(w).trigger('click')
    const input = w.get('tbody tr input[type="text"]')
    expect(input.attributes('aria-label')).toBe(t('member.displayName'))
    const select = w.get('tbody tr select')
    expect(select.attributes('aria-label')).toBe(t('member.role'))
    expect(w.get('tbody tr [data-ds="Input"]').attributes('data-ds-size')).toBe('Small')
    expect(w.get('tbody tr [data-ds="Select"]').attributes('data-ds-size')).toBe('Small')
    expect(w.get('tbody tr').classes()).toContain('bg-surface-subtle')

    await input.setValue('An 3')
    h.result = { data: null, error: null }
    await rowSave(w).trigger('click')
    await flushPromises()
    expect(chainArgs('update')![0]).toMatchObject({ display_name: 'An 3' })
    expect(w.find('tbody tr input').exists()).toBe(false)
  })

  it('edit member: blank / duplicate name -> toast, update not called; cancel restores view mode', async () => {
    h.result = { data: [member('m1', 'An'), member('m2', 'Binh')], error: null }
    const { w } = await mountMembers('admin')
    await rowEdit(w).trigger('click')
    await w.get('tbody tr input[type="text"]').setValue('   ')
    await rowSave(w).trigger('click')
    await flushPromises()
    expect(h.toast.error).toHaveBeenCalledWith(t('member.nameRequired'))
    expect(chainWith('update')).toBeUndefined()

    await w.get('tbody tr input[type="text"]').setValue('Binh')
    await rowSave(w).trigger('click')
    await flushPromises()
    expect(h.toast.error).toHaveBeenCalledWith(t('member.duplicateName'))
    expect(chainWith('update')).toBeUndefined()

    await rowCancel(w).trigger('click')
    await flushPromises()
    expect(w.find('tbody tr input').exists()).toBe(false)
    expect(w.findAll('tbody tr')[0]!.get('[data-ds="Role Badge"]').exists()).toBe(true)
  })

  // Row: Delete member
  it('delete member: delete().eq(id) after confirm and the member is removed', async () => {
    h.result = { data: [member('m1', 'An')], error: null }
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true)
    const { w } = await mountMembers('admin')
    await rowDelete(w).trigger('click')
    await flushPromises()
    const chain = chainWith('delete')!
    expect(chain.calls.map((c) => c.m)).toEqual(['delete', 'eq'])
    expect(chain.calls[1]!.args).toEqual(['id', 'm1'])
    expect(confirm).toHaveBeenCalledWith(t('member.deleteConfirm', { name: 'An' }))
    expect(w.findAll('tbody tr')).toHaveLength(0)
    expect(h.toast.success).toHaveBeenCalledWith(t('toast.memberDeleted'))
  })

  it('delete member: confirm false does not call delete', async () => {
    h.result = { data: [member('m1', 'An')], error: null }
    vi.spyOn(window, 'confirm').mockReturnValue(false)
    const { w } = await mountMembers('admin')
    await rowDelete(w).trigger('click')
    await flushPromises()
    expect(chainWith('delete')).toBeUndefined()
    expect(w.findAll('tbody tr')).toHaveLength(1)
  })
})
