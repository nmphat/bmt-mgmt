<script setup lang="ts">
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { Home, CalendarDays, Users, User, LogIn } from 'lucide-vue-next'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const langStore = useLangStore()
const t = computed(() => langStore.t)

interface NavItem {
  key: string
  label: () => string
  icon: unknown
  to: string
  exact?: boolean
}

const navItems = computed<NavItem[]>(() => {
  const items: NavItem[] = [
    {
      key: 'home',
      label: () => t.value('nav.home'),
      icon: Home,
      to: '/',
      exact: true,
    },
  ]

  if (authStore.isAdmin) {
    items.push({
      key: 'sessions',
      label: () => t.value('nav.sessions'),
      icon: CalendarDays,
      to: '/sessions',
    })
  }

  items.push({
    key: 'members',
    label: () => t.value('nav.members'),
    icon: Users,
    to: '/members',
  })

  if (authStore.isAuthenticated) {
    items.push({
      key: 'profile',
      label: () => t.value('auth.profile'),
      icon: User,
      to: '/profile',
    })
  } else if (!authStore.isAuthenticated) {
    items.push({
      key: 'login',
      label: () => t.value('auth.login'),
      icon: LogIn,
      to: '/login',
    })
  }

  return items
})

function isActive(item: NavItem): boolean {
  if (item.exact) return route.path === item.to
  return route.path.startsWith(item.to)
}
</script>

<template>
  <!-- Mobile Bottom Nav — hidden on md+ -->
  <nav
    class="fixed bottom-0 left-0 right-0 z-50 md:hidden bg-white border-t border-gray-200 safe-area-bottom"
    style="padding-bottom: env(safe-area-inset-bottom)"
  >
    <div class="flex items-stretch justify-around h-16">
      <router-link
        v-for="item in navItems"
        :key="item.key"
        :to="item.to"
        class="flex flex-col items-center justify-center flex-1 gap-0.5 transition-colors"
        :class="
          isActive(item)
            ? 'text-indigo-600'
            : 'text-gray-400 hover:text-gray-600 active:text-indigo-500'
        "
      >
        <component :is="item.icon" class="w-5 h-5" />
        <span class="text-[10px] font-medium leading-tight truncate max-w-[60px] text-center">{{
          item.label()
        }}</span>
        <!-- Active indicator dot -->
        <span
          v-if="isActive(item)"
          class="absolute bottom-1 w-1 h-1 rounded-full bg-indigo-600 opacity-0"
        />
      </router-link>
    </div>
  </nav>
</template>
