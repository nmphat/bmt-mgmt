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
    data-ds="Bottom Nav"
    :data-ds-active="
      isActive('/')
        ? 'Home'
        : isActive('/members')
          ? 'Members'
          : isActive('/sessions')
            ? 'Sessions'
            : 'None'
    "
    class="fixed inset-x-0 bottom-0 z-40 border-t border-line-divider bg-surface-card/95 px-2 pt-2 pb-[max(8px,env(safe-area-inset-bottom))] shadow-[0_-12px_28px_rgba(15,23,42,0.12)] backdrop-blur md:hidden"
    aria-label="Primary mobile navigation"
  >
    <div class="mx-auto grid max-w-md grid-cols-3 gap-1">
      <RouterLink
        to="/"
        data-ds="Bottom Nav Item"
        :data-ds-state="isActive('/') ? 'Active' : 'Inactive'"
        class="flex min-h-11 flex-col items-center justify-center gap-1 rounded-xl px-2 py-2 text-xs font-bold transition-colors duration-200 active:scale-95 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-line-focus"
        :class="
          isActive('/')
            ? 'bg-surface-brand-subtle text-fg-brand'
            : 'text-fg-secondary hover:bg-surface-subtle'
        "
        :aria-current="isActive('/') ? 'page' : undefined"
      >
        <Home class="size-5" aria-hidden="true" />
        <span>{{ t('nav.debtHome') }}</span>
      </RouterLink>

      <RouterLink
        to="/members"
        data-ds="Bottom Nav Item"
        :data-ds-state="isActive('/members') ? 'Active' : 'Inactive'"
        class="flex min-h-11 flex-col items-center justify-center gap-1 rounded-xl px-2 py-2 text-xs font-bold transition-colors duration-200 active:scale-95 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-line-focus"
        :class="
          isActive('/members')
            ? 'bg-surface-brand-subtle text-fg-brand'
            : 'text-fg-secondary hover:bg-surface-subtle'
        "
        :aria-current="isActive('/members') ? 'page' : undefined"
      >
        <Users class="size-5" aria-hidden="true" />
        <span>{{ t('nav.members') }}</span>
      </RouterLink>

      <RouterLink
        to="/sessions"
        data-ds="Bottom Nav Item"
        :data-ds-state="isActive('/sessions') ? 'Active' : 'Inactive'"
        class="flex min-h-11 flex-col items-center justify-center gap-1 rounded-xl px-2 py-2 text-xs font-bold transition-colors duration-200 active:scale-95 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-line-focus"
        :class="
          isActive('/sessions')
            ? 'bg-surface-brand-subtle text-fg-brand'
            : 'text-fg-secondary hover:bg-surface-subtle'
        "
        :aria-current="isActive('/sessions') ? 'page' : undefined"
      >
        <CalendarDays class="size-5" aria-hidden="true" />
        <span>{{ t('nav.sessions') }}</span>
      </RouterLink>
    </div>
  </nav>
</template>
