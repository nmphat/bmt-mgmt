import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createMemoryHistory } from 'vue-router'
import CreateSessionView from '@/views/CreateSessionView.vue'
import CourtBookingEditor from '@/components/session/CourtBookingEditor.vue'
import { useAuthStore } from '@/stores/auth'
import { supabase } from '@/lib/supabase'

vi.mock('@/lib/supabase', () => ({
  supabase: { rpc: vi.fn() },
}))

vi.mock('vue-toastification', () => ({
  useToast: () => ({ error: vi.fn(), success: vi.fn() }),
}))

const rpc = vi.mocked(supabase.rpc)

async function mountCreate() {
  setActivePinia(createPinia())
  useAuthStore().user = { id: 'u1' } as any
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/:p(.*)*', name: 'any', component: { template: '<div />' } }],
  })
  router.push('/create-session')
  await router.isReady()
  const w = mount(CreateSessionView, { global: { plugins: [router] } })
  await flushPromises()
  return w
}

const submit = (w: Awaited<ReturnType<typeof mountCreate>>) => w.get('button[type="submit"]')
const setValid = async (w: Awaited<ReturnType<typeof mountCreate>>, valid: boolean) => {
  w.getComponent(CourtBookingEditor).vm.$emit('update:valid', valid)
  await flushPromises()
}

describe('CreateSessionView (I/O matrix: Create submit)', () => {
  beforeEach(() => {
    rpc.mockReset()
  })

  it('the submit Button is Large Primary and enabled when nothing blocks it', async () => {
    const w = await mountCreate()
    await setValid(w, true)
    expect(submit(w).attributes('data-ds-size')).toBe('Large')
    expect(submit(w).attributes('data-ds-style')).toBe('Primary')
    expect(submit(w).attributes('disabled')).toBeUndefined()
    expect(submit(w).attributes('data-ds-state')).toBe('Default')
  })

  it('disabled while loading', async () => {
    rpc.mockReturnValue(new Promise(() => {}) as any)
    const w = await mountCreate()
    await setValid(w, true)
    await w.get('#title').setValue('Buổi test')
    await w.get('form').trigger('submit')
    await flushPromises()
    expect(rpc).toHaveBeenCalledWith('create_session_with_bookings', expect.any(Object))
    expect(submit(w).attributes('disabled')).toBeDefined()
    expect(submit(w).attributes('data-ds-state')).toBe('Disabled')
  })

  it('submits the bound form values, court fee as a number', async () => {
    rpc.mockResolvedValue({ data: 'new-id', error: null } as any)
    const w = await mountCreate()
    await setValid(w, true)
    await w.get('#title').setValue('Buổi thứ Tư')
    await w.get('#date').setValue('2026-10-01')
    await w.get('#startTime').setValue('17:30')
    await w.get('#endTime').setValue('19:30')
    await w.get('#courtFee').setValue('50000')
    await setValid(w, true)
    await w.get('form').trigger('submit')
    await flushPromises()
    expect(rpc).toHaveBeenCalledWith(
      'create_session_with_bookings',
      expect.objectContaining({
        p_title: 'Buổi thứ Tư',
        p_start_time: new Date('2026-10-01T17:30:00+07:00').toISOString(),
        p_end_time: new Date('2026-10-01T19:30:00+07:00').toISOString(),
        p_created_by: 'u1',
        p_court_fee_addon: 50000,
      }),
    )
    const payload = rpc.mock.calls[0]![1] as Record<string, unknown>
    expect(typeof payload.p_court_fee_addon).toBe('number')
  })

  it('disabled when bookings are invalid, enabled again when valid', async () => {
    const w = await mountCreate()
    await setValid(w, false)
    expect(submit(w).attributes('disabled')).toBeDefined()
    await setValid(w, true)
    expect(submit(w).attributes('disabled')).toBeUndefined()
  })

  it('sessionTimeInvalid: disabled, Error Field Message, #endTime aria-invalid', async () => {
    const w = await mountCreate()
    await setValid(w, true)
    expect(w.get('#endTime').attributes('aria-invalid')).toBeUndefined()
    expect(w.find('[data-ds="Field Message"][data-ds-tone="Error"]').exists()).toBe(false)

    await w.get('#endTime').setValue('17:00')
    await setValid(w, true) // isolate sessionTimeInvalid from the editor's own check
    expect(submit(w).attributes('disabled')).toBeDefined()
    const endTime = w.get('#endTime')
    expect(endTime.attributes('aria-invalid')).toBe('true')
    const msg = w.get('[data-ds="Field Message"][data-ds-tone="Error"]')
    expect(endTime.attributes('aria-describedby')).toBe(msg.attributes('id'))

    await w.get('#endTime').setValue('20:00')
    await setValid(w, true)
    expect(submit(w).attributes('disabled')).toBeUndefined()
    expect(w.get('#endTime').attributes('aria-invalid')).toBeUndefined()
  })
})
