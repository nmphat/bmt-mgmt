import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'home',
      component: () => import('../views/HomePage.vue'),
    },
    {
      path: '/sessions',
      name: 'dashboard',
      component: () => import('../views/DashboardView.vue'),
      meta: { requiresAuth: true, requiresAdmin: true },
    },
    {
      path: '/member/:id',
      name: 'member-detail',
      component: () => import('../views/MemberDetailView.vue'),
    },
    {
      path: '/login',
      name: 'login',
      component: () => import('../views/LoginView.vue'),
    },
    {
      path: '/session/:id',
      name: 'session-detail',
      component: () => import('../views/SessionDetailView.vue'),
    },
    {
      path: '/create-session',
      name: 'create-session',
      component: () => import('../views/CreateSessionView.vue'),
      meta: { requiresAuth: true, requiresAdmin: true },
    },
    {
      path: '/members',
      name: 'members',
      component: () => import('../views/MemberView.vue'),
    },
    {
      path: '/pay',
      name: 'payment',
      component: () => import('../views/PaymentView.vue'),
    },
  ],
})

router.beforeEach(async (to, from, next) => {
  const authStore = useAuthStore()

  // Wait for auth to initialize if refreshing
  if (authStore.loading) {
    await authStore.initialize()
  }

  const requiresAuth = to.matched.some((record) => record.meta.requiresAuth)
  const requiresAdmin = to.matched.some((record) => record.meta.requiresAdmin)

  if (requiresAuth && !authStore.isAuthenticated) {
    next({ name: 'login' })
    return
  }

  if (requiresAdmin && !authStore.isAdmin) {
    // Redirect non-admins to home if they try to access admin pages
    next({ name: 'home' })
    return
  }

  next()
})

export default router
