import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'dashboard',
      component: () => import('../views/DashboardView.vue'),
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
    },
    {
      path: '/members',
      name: 'members',
      component: () => import('../views/MemberView.vue'),
    },
  ],
})

// Optional: Add navigation guards if needed
// router.beforeEach((to, from, next) => {
//   const authStore = useAuthStore()
//   if (to.name !== 'login' && !authStore.isAuthenticated && to.meta.requiresAuth) {
//     next({ name: 'login' })
//   } else {
//     next()
//   }
// })

export default router