<script setup lang="ts">
import { computed } from 'vue'
import { RouterLink, useRoute } from 'vue-router'
import { CalendarDays, Home, Users } from 'lucide-vue-next'
import { useLangStore } from '@/stores/lang'

const route = useRoute()
const langStore = useLangStore()
const t = computed(() => langStore.t)

const isActive = (path: '/' | '/members' | '/sessions') => {
  if (path === '/') {
    return route.path === '/'
  }

  if (path === '/members') {
    return route.path === '/members' || route.path.startsWith('/member/')
  }

  return route.path === '/sessions' || route.path.startsWith('/session/')
}
</script>

<template>
  <nav
    class="fixed inset-x-0 bottom-0 z-40 border-t border-gray-200 bg-white/95 px-2 pt-2 pb-[max(8px,env(safe-area-inset-bottom))] shadow-[0_-12px_28px_rgba(15,23,42,0.12)] backdrop-blur md:hidden"
    aria-label="Primary mobile navigation"
  >
    <div class="mx-auto grid max-w-md grid-cols-3 gap-1">
      <RouterLink
        to="/"
        class="flex min-h-11 flex-col items-center justify-center gap-1 rounded-xl px-2 py-2 text-xs font-bold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
        :class="isActive('/') ? 'bg-indigo-50 text-indigo-600' : 'text-gray-600 hover:bg-gray-50'"
        :aria-current="isActive('/') ? 'page' : undefined"
      >
        <Home class="h-5 w-5" aria-hidden="true" />
        <span>{{ t('nav.debtHome') }}</span>
      </RouterLink>

      <RouterLink
        to="/members"
        class="flex min-h-11 flex-col items-center justify-center gap-1 rounded-xl px-2 py-2 text-xs font-bold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
        :class="
          isActive('/members') ? 'bg-indigo-50 text-indigo-600' : 'text-gray-600 hover:bg-gray-50'
        "
        :aria-current="isActive('/members') ? 'page' : undefined"
      >
        <Users class="h-5 w-5" aria-hidden="true" />
        <span>{{ t('nav.members') }}</span>
      </RouterLink>

      <RouterLink
        to="/sessions"
        class="flex min-h-11 flex-col items-center justify-center gap-1 rounded-xl px-2 py-2 text-xs font-bold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
        :class="
          isActive('/sessions') ? 'bg-indigo-50 text-indigo-600' : 'text-gray-600 hover:bg-gray-50'
        "
        :aria-current="isActive('/sessions') ? 'page' : undefined"
      >
        <CalendarDays class="h-5 w-5" aria-hidden="true" />
        <span>{{ t('nav.sessions') }}</span>
      </RouterLink>
    </div>
  </nav>
</template>
