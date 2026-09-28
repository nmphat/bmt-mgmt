import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import LoginView from '@/views/LoginView.vue'
import { supabase } from '@/lib/supabase'

const push = vi.fn()

vi.mock('@/lib/supabase', () => ({
  supabase: { auth: { signInWithPassword: vi.fn() } },
}))

vi.mock('vue-router', async (importOriginal) => {
  const actual = await importOriginal<typeof import('vue-router')>()
  return { ...actual, useRoute: () => ({ query: {} }), useRouter: () => ({ push }) }
})

vi.mock('vue-toastification', () => ({
  useToast: () => ({ error: vi.fn(), success: vi.fn() }),
}))

const signIn = vi.mocked(supabase.auth.signInWithPassword)

function mountLogin() {
  setActivePinia(createPinia())
  return mount(LoginView)
}

async function fillAndSubmit(w: ReturnType<typeof mountLogin>) {
  await w.get('#email-address').setValue('a@b.vn')
  await w.get('#password').setValue('secret')
  await w.get('form').trigger('submit')
}

describe('LoginView (I/O matrix: Login submit)', () => {
  beforeEach(() => {
    signIn.mockReset()
    push.mockReset()
  })

  it('runs handleLogin on submit; the submit Button is Disabled while loading', async () => {
    let resolve!: (v: unknown) => void
    signIn.mockReturnValue(new Promise((r) => (resolve = r)) as any)
    const w = mountLogin()
    const btn = () => w.get('button[type="submit"]')
    expect(btn().attributes('data-ds')).toBe('Button')
    expect(btn().attributes('data-ds-state')).toBe('Default')
    expect(btn().attributes('disabled')).toBeUndefined()

    await fillAndSubmit(w)
    expect(signIn).toHaveBeenCalledWith({ email: 'a@b.vn', password: 'secret' })
    expect(btn().attributes('data-ds-state')).toBe('Disabled')
    expect(btn().attributes('disabled')).toBeDefined()

    resolve({ error: null })
    await flushPromises()
    expect(push).toHaveBeenCalledWith('/')
    expect(btn().attributes('data-ds-state')).toBe('Default')
  })

  it('shows errorMsg as a Field Message Error Center', async () => {
    signIn.mockResolvedValue({ error: { message: 'Invalid login' } } as any)
    const w = mountLogin()
    expect(w.find('[data-ds="Field Message"]').exists()).toBe(false)
    await fillAndSubmit(w)
    await flushPromises()
    const msg = w.get('[data-ds="Field Message"]')
    expect(msg.attributes('data-ds-tone')).toBe('Error')
    expect(msg.attributes('data-ds-align')).toBe('Center')
    expect(msg.text()).toBe('Invalid login')
    expect(push).not.toHaveBeenCalled()
  })
})
