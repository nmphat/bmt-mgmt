import { describe, it, expect, vi } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import DashboardView from '@/views/DashboardView.vue'
import { useAuthStore } from '@/stores/auth'

function makeQueryBuilder() {
  const builder: any = {
    select: vi.fn(() => builder),
    order: vi.fn(() => builder),
    in: vi.fn(() => builder),
    then: (resolve: any, reject: any) =>
      Promise.resolve({ data: [], error: null }).then(resolve, reject),
  }
  return builder
}

let lastBuilder: any

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn(() => {
      lastBuilder = makeQueryBuilder()
      return lastBuilder
    }),
  },
}))

async function mountDashboard(isAdmin: boolean) {
  setActivePinia(createPinia())
  const authStore = useAuthStore()
  authStore.profile = isAdmin
    ? { id: 'a1', role: 'admin', display_name: 'Admin' }
    : { id: 'm1', role: 'member', display_name: 'Member' }
  const w = mount(DashboardView)
  await flushPromises()
  await flushPromises()
  return w
}

describe('DashboardView session list permission filter', () => {
  it('filters to finalized statuses for non-admin, applies no status filter for admin', async () => {
    await mountDashboard(false)
    expect(lastBuilder.in).toHaveBeenCalledWith('status', ['waiting_for_payment', 'done'])

    await mountDashboard(true)
    expect(lastBuilder.in).not.toHaveBeenCalled()
  })
})
