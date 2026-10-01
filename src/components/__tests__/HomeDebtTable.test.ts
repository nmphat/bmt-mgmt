import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createMemoryHistory } from 'vue-router'
import HomeDebtTable from '@/components/HomeDebtTable.vue'
import { useLangStore } from '@/stores/lang'
import type { MemberDebtSummary } from '@/types'

// Types into the field: sets the value and fires only `input` (VTU's setValue also fires `change`).
async function type(
  w: { element: Element; trigger: (e: string) => Promise<void> },
  value: string | number,
) {
  ;(w.element as HTMLInputElement).value = String(value)
  await w.trigger('input')
}

const t = (key: string, params?: Record<string, unknown>) => useLangStore().t(key, params as any)

const m1: MemberDebtSummary = {
  member_id: 'm1',
  display_name: 'an',
  total_debt: 54000,
  unpaid_session_count: 3,
}
const m2: MemberDebtSummary = {
  member_id: 'm2',
  display_name: 'Binh',
  total_debt: 30000,
  unpaid_session_count: 1,
}

type Props = {
  members?: MemberDebtSummary[]
  loading?: boolean
  hasMore?: boolean
  search?: string
  errorMessage?: string
  isAdmin?: boolean
}

async function mountTable(props: Props = {}, attachTo?: HTMLElement) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: { template: '<div />' } },
      { path: '/member/:id', component: { template: '<div />' } },
    ],
  })
  router.push('/')
  await router.isReady()
  return mount(HomeDebtTable, {
    props: { members: [], loading: false, hasMore: false, search: '', ...props },
    global: { plugins: [router] },
    attachTo,
  })
}

type W = Awaited<ReturnType<typeof mountTable>>
const cards = (w: W) => w.findAll('[data-ds="Debt Card"]')
const dataRows = (w: W) => w.findAll('tr[data-ds="Debt Table Row"][data-ds-kind="Data"]')

describe('HomeDebtTable (I/O matrix)', () => {
  beforeEach(() => setActivePinia(createPinia()))

  // Row: Debt loading / empty
  it('loading: 3 Debt Card Skeletons and a Spinner 32 row', async () => {
    const w = await mountTable({ loading: true })
    expect(w.findAll('[data-ds="Debt Card Skeleton"]')).toHaveLength(3)
    const row = w.get('tr[data-ds="Debt Table Row"]')
    expect(row.attributes('data-ds-kind')).toBe('Loading')
    expect(row.get('[data-ds="Spinner"]').attributes('data-ds-size')).toBe('32')
    expect(w.find('[data-ds="Empty State"]').exists()).toBe(false)
  })

  it('empty: Empty State Dashed (mobile) and Plain (table) with the heading and body', async () => {
    const w = await mountTable()
    const states = w.findAll('[data-ds="Empty State"]')
    expect(states.map((s) => s.attributes('data-ds-style'))).toEqual(['Dashed', 'Plain'])
    for (const s of states) {
      expect(s.attributes('data-ds-align')).toBe('Center')
      expect(s.text()).toContain(t('debt.emptyHeading'))
      expect(s.text()).toContain(t('debt.emptyBody'))
    }
    expect(w.get('tr[data-ds="Debt Table Row"]').attributes('data-ds-kind')).toBe('Empty')
    expect(w.find('[data-ds="Debt Card Skeleton"]').exists()).toBe(false)
  })

  // Row: Debt card
  it('debt card (admin): Avatar 32, name, amount, unpaid count, Details, QR and Cash buttons', async () => {
    const w = await mountTable({ members: [m1], isAdmin: true })
    const card = cards(w)[0]!
    expect(card.attributes('data-ds-selected')).toBe('false')
    const avatar = card.get('[data-ds="Avatar"]')
    expect(avatar.attributes('data-ds-size')).toBe('32')
    expect(avatar.text()).toBe('A')
    expect(card.text()).toContain('an')
    expect(card.get('.text-3xl').text()).toMatch(/54\.000/)
    expect(card.text()).toContain(t('debt.unpaidSessionCount', { count: 3 }))
    const buttons = card.findAll('[data-ds="Button"]')
    expect(
      buttons.map((b) => [b.attributes('data-ds-size'), b.attributes('data-ds-style')]),
    ).toEqual([
      ['Default', 'Outline Brand'],
      ['Default', 'Primary'],
      ['Default', 'Outline Success'],
    ])
    expect(buttons[0]!.element.tagName).toBe('A')
    expect(buttons[0]!.attributes('href')).toBe('/member/m1')
    expect(buttons[0]!.text()).toBe(t('debt.details'))
    await buttons[1]!.trigger('click')
    expect(w.emitted('pay-single')).toEqual([['m1']])
    await buttons[2]!.trigger('click')
    expect(w.emitted('pay-cash')).toEqual([['m1']])
  })

  it('debt card (guest): no Cash button', async () => {
    const w = await mountTable({ members: [m1] })
    const buttons = cards(w)[0]!.findAll('[data-ds="Button"]')
    expect(buttons.map((b) => b.attributes('data-ds-style'))).toEqual(['Outline Brand', 'Primary'])
    expect(w.text()).not.toContain(t('payment.cashPay'))
  })

  // Row: Select
  it('select: card area click, Enter and Space toggle; the checkbox toggles once', async () => {
    const w = await mountTable({ members: [m1] }, document.body)
    const area = () => cards(w)[0]!.get('[role="button"]')
    await area().trigger('click')
    expect(cards(w)[0]!.attributes('data-ds-selected')).toBe('true')
    expect(area().attributes('aria-pressed')).toBe('true')
    expect(cards(w)[0]!.classes()).toEqual(
      expect.arrayContaining(['border-line-brand', 'bg-surface-brand-subtle']),
    )
    await area().trigger('keydown', { key: 'Enter' })
    expect(cards(w)[0]!.attributes('data-ds-selected')).toBe('false')
    await area().trigger('keydown', { key: ' ' })
    expect(cards(w)[0]!.attributes('data-ds-selected')).toBe('true')
    const box = cards(w)[0]!.get('input[type="checkbox"]')
    expect(box.attributes('data-ds-size')).toBe('24')
    expect(box.attributes('aria-label')).toBe(t('debt.selectedCount', { count: 1 }))
    // happy-dom fires the checkbox's change only when it is connected (the test mounts attached). The click
    // bubbles to the @click.stop wrapper; the selection flips exactly once per click.
    const clickBox = () => cards(w)[0]!.get('input[type="checkbox"]').trigger('click')
    await clickBox()
    expect(cards(w)[0]!.attributes('data-ds-selected')).toBe('false')
    expect(area().attributes('aria-pressed')).toBe('false')
    await clickBox()
    expect(cards(w)[0]!.attributes('data-ds-selected')).toBe('true')
    expect(area().attributes('aria-pressed')).toBe('true')
    w.unmount()
  })

  // Row: Table row
  it('table row (admin): Checkbox 16, member link, Count Pill, danger amount, QR and Cash buttons', async () => {
    const w = await mountTable({ members: [m1], isAdmin: true })
    const row = dataRows(w)[0]!
    expect(row.attributes('data-ds-selected')).toBe('false')
    for (const td of row.findAll('td')) expect(td.classes()).toContain('whitespace-nowrap')
    expect(row.get('input[type="checkbox"]').attributes('data-ds-size')).toBe('16')
    const link = row.get('a')
    expect(link.attributes('href')).toBe('/member/m1')
    expect(link.get('[data-ds="Avatar"]').text()).toBe('A')
    expect(link.text()).toContain('an')
    const pill = row.get('[data-ds="Count Pill"]')
    expect(pill.attributes('data-ds-tone')).toBe('Danger')
    expect(pill.text()).toBe('3')
    const amount = row.findAll('td')[3]!
    expect(amount.classes()).toContain('text-fg-danger')
    expect(amount.text()).toMatch(/54\.000/)
    const buttons = row.findAll('[data-ds="Button"]')
    expect(
      buttons.map((b) => [b.attributes('data-ds-size'), b.attributes('data-ds-style')]),
    ).toEqual([
      ['Small', 'Outline Brand'],
      ['Small', 'Outline Success'],
    ])
    expect(buttons[0]!.text()).toBe(t('payment.qrPay'))
    await buttons[0]!.trigger('click')
    expect(w.emitted('pay-single')).toEqual([['m1']])
    await buttons[1]!.trigger('click')
    expect(w.emitted('pay-cash')).toEqual([['m1']])
    await row.get('input[type="checkbox"]').setValue(true)
    expect(dataRows(w)[0]!.attributes('data-ds-selected')).toBe('true')
  })

  it('table row (guest): only the QR button', async () => {
    const w = await mountTable({ members: [m1] })
    const buttons = dataRows(w)[0]!.findAll('[data-ds="Button"]')
    expect(buttons.map((b) => b.attributes('data-ds-style'))).toEqual(['Outline Brand'])
  })

  // Row: Select all
  it('select all: the header checkbox selects every visible member, then clears them', async () => {
    const w = await mountTable({ members: [m1, m2] })
    const header = w.get('th[data-ds-content="Checkbox"] input[type="checkbox"]')
    await header.setValue(true)
    expect(dataRows(w).map((r) => r.attributes('data-ds-selected'))).toEqual(['true', 'true'])
    expect(cards(w).map((c) => c.attributes('data-ds-selected'))).toEqual(['true', 'true'])
    await w.get('th[data-ds-content="Checkbox"] input[type="checkbox"]').setValue(false)
    expect(dataRows(w).map((r) => r.attributes('data-ds-selected'))).toEqual(['false', 'false'])
  })

  // Row: Group bar
  it('group bar: hidden with no selection; with 2 selected shows count and total and emits pay-group', async () => {
    const w = await mountTable({ members: [m1, m2] })
    expect(w.find('[data-ds="Floating Selection Bar"]').exists()).toBe(false)
    await cards(w)[0]!.get('[role="button"]').trigger('click')
    await cards(w)[1]!.get('[role="button"]').trigger('click')
    const bar = w.get('[data-ds="Floating Selection Bar"]')
    expect(bar.attributes('data-ds-style')).toBe('Light')
    expect(bar.text()).toContain(t('debt.selectedCount', { count: 2 }))
    expect(bar.text()).toMatch(/84\.000/)
    const button = bar.get('[data-ds="Button"]')
    expect(button.attributes('data-ds-style')).toBe('Primary')
    expect(button.text()).toBe(t('debt.createGroupQR'))
    await button.trigger('click')
    expect(w.emitted('pay-group')).toEqual([[['m1', 'm2']]])
  })

  // Row: Load more
  it('load more: emits load-more; disabled with common.loading while loading; hidden without hasMore', async () => {
    const w = await mountTable({ members: [m1], hasMore: true })
    const button = () => w.get('.mt-4.text-center [data-ds="Button"]')
    expect(button().attributes('data-ds-style')).toBe('Secondary')
    expect(button().text()).toBe(t('debt.loadMore'))
    await button().trigger('click')
    expect(w.emitted('load-more')).toEqual([[]])
    await w.setProps({ loading: true })
    expect(button().attributes('disabled')).toBeDefined()
    expect(button().text()).toBe(t('common.loading'))
    await w.setProps({ hasMore: false })
    expect(w.find('.mt-4.text-center').exists()).toBe(false)
  })

  // Row: Search
  it('search: typing emits update:search with the value', async () => {
    const w = await mountTable({ members: [m1] })
    const input = w.get('input#debt-search')
    expect(input.attributes('type')).toBe('search')
    expect(w.get('[data-ds="Input"]').attributes('data-ds-size')).toBe('Large')
    expect(w.get('label[for="debt-search"]').classes()).toContain('sr-only')
    await type(input, 'an')
    expect(w.emitted('update:search')).toEqual([['an']])
  })

  it('search: emits on every input event during IME composition', async () => {
    const w = await mountTable({ members: [m1] })
    const input = w.get('input#debt-search')
    await input.trigger('compositionstart')
    await type(input, 'a')
    await type(input, 'an')
    expect(w.emitted('update:search')).toEqual([['a'], ['an']])
  })

  it('error: Alert Danger with the message', async () => {
    const w = await mountTable({ errorMessage: 'boom' })
    const alert = w.get('[data-ds="Alert"]')
    expect(alert.attributes('data-ds-tone')).toBe('Danger')
    expect(alert.attributes('role')).toBe('alert')
    expect(alert.text()).toBe('boom')
  })
})
